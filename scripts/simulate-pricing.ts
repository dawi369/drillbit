/**
 * Monthly profit and loss for a given number of monthly active users and share of them on Pro.
 * Monte Carlo over usage; every assumption is a named constant below, so prices, caps and costs can be changed
 * and the run repeated. Never reads private data. Usage: bun scripts/simulate-pricing.ts
 */
import { mkdirSync, writeFileSync } from "node:fs";

// ── What we charge (App Store Connect; matches Config/Drillbit.storekit) ──────────────────────────────
const PRICE = { weekly: 7.99, weeklyIntro: 1.99, yearly: 79.99 };
const APPLE_CUT = 0.15; // Small Business Program; 0.30 without it
const REFUNDS_AND_FAILED_RENEWALS = 0.03;

// ── What it costs (measured) ───────────────────────────────────────────────────────────────────────────
// Production ai_runs, 31 Oct: interview turn $0.00099, question writing $0.00176, feedback $0.00087.
// Synthetic flow evaluation, 31 Oct: whole 3–5 turn interview plus feedback, mean $0.0021.
const COST = {
  questionWriting: 0.0018,
  interviewTurn: 0.0010,
  feedback: 0.0009,
  nudgeOrExample: 0.0010,
  retryOverhead: 1.1, // malformed provider JSON is retried (about 1 in 60 replies)
  voicePerOpenMinute: 0.05, // OpenAI live voice, billed per open second, silence included
  voiceHandoffPerMinute: 0.0005, // technical reasoning hand-offs during voice
};
const FIXED_PER_MONTH = 99 / 12 /* Apple Developer */ + 5 /* Cloudflare Workers Paid */;
const INFRA_PER_USER = 0.001; // Workers requests and D1 beyond the plan's included usage
// Clerk: free up to 50,000 monthly retained users, then $25 + $0.02 per retained user (checked 31 Oct 2026).
const clerk = (mau: number) => { const retained = mau * 0.6; return retained <= 50_000 ? 0 : 25 + (retained - 50_000) * 0.02; };

// ── Limits (production wrangler vars) ──────────────────────────────────────────────────────────────────
const FREE = { repsPerDay: 3, introVoiceSessions: 3, sessionMinutes: 3, tasteEveryDays: 30, followUpsPerRep: 8, nudgesPerRep: 2 };
const PRO = { voiceMinutesPerWeek: 150, voiceMinutesPerDay: 60 };
const PRO_MONTHLY_VOICE_CAP = Math.min(PRO.voiceMinutesPerWeek * 4.33, PRO.voiceMinutesPerDay * 30);

// ── How people behave (assumptions; the sensitivity table varies the ones that matter) ────────────────
const BASE = {
  newShare: 0.35, // share of this month's free users who are new and can use the voice intro
  yearlyShare: 0.4, // share of Pro subscribers on yearly
  weeklyLifetimeWeeks: 5, // a weekly subscriber's average paid run; the first week is the intro price
  voicePrice: 1, // multiplier on voice cost
  appleCut: APPLE_CUT,
  yearlyPrice: PRICE.yearly,
  proWeeklyVoiceCap: PRO.voiceMinutesPerWeek,
  freeTasteShare: 0.5, // returning free users who take the monthly voice taste
  yearlyIdle: 0, // extra share of yearly subscriber-months with no practice at all (paid, between prep bursts)
};
type Assumptions = typeof BASE;

let seed = 20261031;
const rand = () => { seed |= 0; seed = (seed + 0x6d2b79f5) | 0; let t = Math.imul(seed ^ (seed >>> 15), 1 | seed); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
const between = (a: number, b: number) => a + (b - a) * rand();
const pick = <T,>(weights: [T, number][]) => { let r = rand(), acc = 0; for (const [v, w] of weights) { acc += w; if (r < acc) return v; } return weights[weights.length - 1][0]; };

function repCost(free: boolean) {
  const turns = free ? Math.min(FREE.followUpsPerRep, Math.round(between(3, 9))) : Math.round(between(3, 12));
  const help = free ? Math.min(FREE.nudgesPerRep, Math.round(between(0, 2))) : Math.round(between(0, 3));
  return (COST.questionWriting + turns * COST.interviewTurn + COST.feedback + help * COST.nudgeOrExample) * COST.retryOverhead;
}
const voiceCost = (minutes: number, a: Assumptions) => minutes * (COST.voicePerOpenMinute * a.voicePrice + COST.voiceHandoffPerMinute);

/** One free user's month: reps, then the voice intro if new, else maybe the monthly taste. */
function freeMonth(a: Assumptions) {
  const reps = pick<[number, number]>([[[1, 4], 0.4], [[5, 20], 0.4], [[20, 60], 0.2]]);
  let cost = 0;
  const count = Math.min(Math.round(between(...reps)), FREE.repsPerDay * 30);
  for (let i = 0; i < count; i++) cost += repCost(true);
  let minutes = 0;
  if (rand() < a.newShare) {
    const sessions = pick([[0, 0.3], [1, 0.25], [2, 0.2], [3, 0.25]] as [number, number][]);
    for (let i = 0; i < sessions; i++) minutes += between(1.5, FREE.sessionMinutes);
  } else if (rand() < a.freeTasteShare) minutes += between(1.5, FREE.sessionMinutes);
  return { cost: cost + voiceCost(minutes, a) + INFRA_PER_USER, minutes, reps: count };
}

type Segment = "text" | "light" | "prepping" | "heavy";
const SEGMENTS: Record<Segment, { reps: [number, number]; voice: [number, number] }> = {
  text: { reps: [20, 60], voice: [0, 0] },
  light: { reps: [15, 40], voice: [20, 90] },
  prepping: { reps: [10, 30], voice: [200, 450] }, // about three 25-minute mocks a week
  heavy: { reps: [20, 60], voice: [550, 700] }, // pushes the weekly cap
};
const MIX: Record<"weekly" | "yearly", [Segment, number][]> = {
  // Weekly buyers are mid-prep; yearly buyers spread it out.
  weekly: [["text", 0.2], ["light", 0.3], ["prepping", 0.35], ["heavy", 0.15]],
  yearly: [["text", 0.45], ["light", 0.3], ["prepping", 0.18], ["heavy", 0.07]],
};

/** One Pro subscriber's month at steady state: what Apple pays out, and what their usage costs. */
function proMonth(a: Assumptions) {
  const plan = rand() < a.yearlyShare ? "yearly" : "weekly";
  const idle = plan === "yearly" && rand() < a.yearlyIdle;
  const segment = pick(MIX[plan]);
  const s = SEGMENTS[segment];
  let cost = 0;
  const reps = idle ? 0 : Math.round(between(...s.reps));
  for (let i = 0; i < reps; i++) cost += repCost(false);
  const cap = Math.min(a.proWeeklyVoiceCap * 4.33, PRO.voiceMinutesPerDay * 30);
  const minutes = idle ? 0 : Math.min(between(...s.voice), cap);
  cost += voiceCost(minutes, a) + INFRA_PER_USER;
  const gross = plan === "yearly" ? a.yearlyPrice / 12
    : 4.33 * ((1 / a.weeklyLifetimeWeeks) * PRICE.weeklyIntro + (1 - 1 / a.weeklyLifetimeWeeks) * PRICE.weekly);
  const revenue = gross * (1 - a.appleCut) * (1 - REFUNDS_AND_FAILED_RENEWALS);
  return { cost, revenue, plan, segment, minutes };
}

/** One simulated month for `mau` users, `proShare` of them Pro. Large populations are sampled and scaled. */
function month(mau: number, proShare: number, a: Assumptions) {
  const pro = Math.round(mau * proShare), free = mau - pro;
  const sample = (n: number, f: () => { cost: number; revenue?: number }) => {
    const k = Math.min(n, 4000); let cost = 0, revenue = 0;
    for (let i = 0; i < k; i++) { const m = f(); cost += m.cost; revenue += m.revenue ?? 0; }
    return k ? { cost: (cost * n) / k, revenue: (revenue * n) / k } : { cost: 0, revenue: 0 };
  };
  const f = sample(free, () => freeMonth(a)), p = sample(pro, () => proMonth(a));
  const fixed = FIXED_PER_MONTH + clerk(mau);
  return { revenue: p.revenue, freeCost: f.cost, proCost: p.cost, fixed, net: p.revenue - f.cost - p.cost - fixed };
}

function run(mau: number, proShare: number, a: Assumptions = BASE, runs = 40) {
  const nets = Array.from({ length: runs }, () => month(mau, proShare, a).net).sort((x, y) => x - y);
  return { p10: nets[Math.floor(runs * 0.1)], median: nets[Math.floor(runs / 2)], p90: nets[Math.floor(runs * 0.9)] };
}

const money = (v: number) => (v < 0 ? "–" : "+") + "$" + Math.abs(v).toLocaleString("en-US", { maximumFractionDigits: 0 });
const lines: string[] = [];
const out = (s = "") => { lines.push(s); console.log(s); };

// ── 1. Unit economics ──────────────────────────────────────────────────────────────────────────────────
out("## Unit economics (per user per month, mean of 20,000 samples)\n");
const avg = (f: () => any, key: string, n = 20000) => { let t = 0; for (let i = 0; i < n; i++) t += f()[key]; return t / n; };
out(`Text rep (Free / Pro): $${avg(() => ({ c: repCost(true) }), "c").toFixed(4)} / $${avg(() => ({ c: repCost(false) }), "c").toFixed(4)}`);
out(`Voice: $${voiceCost(1, BASE).toFixed(3)} per open minute; Pro voice capped at ${Math.round(PRO_MONTHLY_VOICE_CAP)} min a month`);
out(`Free user: $${avg(() => freeMonth(BASE), "cost").toFixed(3)} a month on average`);
for (const seg of Object.keys(SEGMENTS) as Segment[]) {
  const s = SEGMENTS[seg]; let c = 0; for (let i = 0; i < 4000; i++) { let x = 0; const r = Math.round(between(...s.reps)); for (let j = 0; j < r; j++) x += repCost(false); c += x + voiceCost(Math.min(between(...s.voice), PRO_MONTHLY_VOICE_CAP), BASE); }
  out(`Pro ${seg.padEnd(8)}: $${(c / 4000).toFixed(2)} a month`);
}
const weeklyNet = 4.33 * ((1 / BASE.weeklyLifetimeWeeks) * PRICE.weeklyIntro + (1 - 1 / BASE.weeklyLifetimeWeeks) * PRICE.weekly) * (1 - APPLE_CUT) * (1 - REFUNDS_AND_FAILED_RENEWALS);
out(`Revenue kept per subscriber-month: weekly $${weeklyNet.toFixed(2)}, yearly $${((PRICE.yearly / 12) * (1 - APPLE_CUT) * (1 - REFUNDS_AND_FAILED_RENEWALS)).toFixed(2)}`);
out(`Average Pro subscriber: kept $${avg(() => proMonth(BASE), "revenue").toFixed(2)}, cost $${avg(() => proMonth(BASE), "cost").toFixed(2)}`);
for (const plan of ["weekly", "yearly"] as const) {
  const only = { ...BASE, yearlyShare: plan === "yearly" ? 1 : 0 };
  out(`  ${plan}: kept $${avg(() => proMonth(only), "revenue").toFixed(2)}, cost $${avg(() => proMonth(only), "cost").toFixed(2)}`);
}

// ── 2. The grid ────────────────────────────────────────────────────────────────────────────────────────
const users = [100, 500, 1_000, 5_000, 10_000, 50_000, 100_000];
const shares = [0.01, 0.02, 0.03, 0.05, 0.08, 0.1];
out("\n## Monthly net (median; 10th–90th percentile in brackets)\n");
out("| Active users | " + shares.map(s => `${s * 100}% Pro`).join(" | ") + " |");
out("|---|" + shares.map(() => "---").join("|") + "|");
for (const mau of users) {
  out(`| ${mau.toLocaleString("en-US")} | ` + shares.map(s => { const r = run(mau, s); return mau <= 1000 ? `${money(r.median)} (${money(r.p10)} to ${money(r.p90)})` : money(r.median); }).join(" | ") + " |");
}

// ── 3. Break-even ──────────────────────────────────────────────────────────────────────────────────────
out("\n## Pro share needed to break even\n");
for (const mau of [100, 1_000, 10_000, 100_000]) {
  let lo = 0, hi = 0.3;
  for (let i = 0; i < 18; i++) { const mid = (lo + hi) / 2; if (run(mau, mid, BASE, 12).median >= 0) hi = mid; else lo = mid; }
  out(`${mau.toLocaleString("en-US")} active users: ${(hi * 100).toFixed(1)}% Pro`);
}

// ── 4. Sensitivity ─────────────────────────────────────────────────────────────────────────────────────
out("\n## Sensitivity: 10,000 active users, 3% Pro (median monthly net)\n");
const cases: [string, Partial<Assumptions>][] = [
  ["Base case", {}],
  ["No Small Business Program (Apple 30%)", { appleCut: 0.3 }],
  ["Mostly yearly (70%)", { yearlyShare: 0.7 }],
  ["Mostly weekly (15% yearly)", { yearlyShare: 0.15 }],
  ["Weekly subs churn fast (2 weeks)", { weeklyLifetimeWeeks: 2 }],
  ["Weekly subs stay (10 weeks)", { weeklyLifetimeWeeks: 10 }],
  ["Voice costs 50% more", { voicePrice: 1.5 }],
  ["Voice costs half", { voicePrice: 0.5 }],
  ["Many new users (60% new)", { newShare: 0.6 }],
  ["Yearly subs idle half their months", { yearlyIdle: 0.5 }],
  ["Lever: yearly at $99.99", { yearlyPrice: 99.99 }],
  ["Lever: Pro voice 100 min a week", { proWeeklyVoiceCap: 100 }],
  ["Lever: no monthly free voice taste", { freeTasteShare: 0 }],
  ["Levers: yearly $99.99 + 100 min a week", { yearlyPrice: 99.99, proWeeklyVoiceCap: 100 }],
];
out("| Case | Net |\n|---|---|");
for (const [name, change] of cases) out(`| ${name} | ${money(run(10_000, 0.03, { ...BASE, ...change }).median)} |`);

mkdirSync(".local", { recursive: true });
writeFileSync(".local/pricing-simulation.md", lines.join("\n") + "\n");
console.log("\nSaved to .local/pricing-simulation.md");
