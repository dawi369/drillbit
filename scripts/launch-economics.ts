/**
 * Launch economics under "two free reps, then Pro" (31 October 2026). Free users cost once, so the unit is a cohort of
 * downloads, not a month of active users (scripts/simulate-pricing.ts still models the older 3-a-day freemium).
 * Expected values, no randomness: every number in the output traces to a constant below. Never reads private data.
 * Usage: bun scripts/launch-economics.ts   (writes .local/launch-economics.md)
 */
import { mkdirSync, writeFileSync } from "node:fs";

// ── Prices (App Store Connect; Config/Drillbit.storekit matches) ─────────────────────────────────────────
const PRICE = { weekly: 7.99, weeklyIntro: 1.99, yearly: 99.99 };
const REFUNDS = 0.03;
const kept = (gross: number, appleCut: number) => gross * (1 - appleCut) * (1 - REFUNDS);

// ── Measured costs (production ai_runs 31 Oct; OpenAI live voice billed per open second) ─────────────────
const COST = { question: 0.0018, turn: 0.001, feedback: 0.0009, help: 0.001, retry: 1.1, voiceMinute: 0.051 };
const rep = (turns: number, help: number) => (COST.question + turns * COST.turn + COST.feedback + help * COST.help) * COST.retry;
const FIXED_PER_MONTH = 99 / 12 + 5; // Apple Developer, Cloudflare Workers Paid. Clerk is free below 50,000 retained users.

// ── Limits (production wrangler vars) ────────────────────────────────────────────────────────────────────
const FREE = { reps: 2, turns: 8, help: 2, introSessions: 3, sessionMinutes: 3 };
// repsPerDay counts reps practised (second message sent); question writing has its own guard of 20 a day.
const PRO = { repsPerDay: 10, sessionMinutes: 20, minutesPerDay: 60, minutesPerWeek: 75 };
// A rolling 7-day cap allows up to five full weeks' worth inside a 30-day month (100 min on days 1, 8, 15, 22, 29).
const PRO_MAX_MINUTES_30_DAYS = 5 * PRO.minutesPerWeek;

// ── Expected behaviour (assumptions until real numbers arrive) ───────────────────────────────────────────
const FUNNEL = { rep1: 0.6, rep2: 0.35, triesVoice: 0.4, freeVoiceMinutes: 5, unopenedQuestion: 0.15 };
// Pro usage per month by segment. A "mock" is about 20 minutes of voice (one session at the cap).
const SEGMENT = {
  idle: { reps: 0, voice: 0 }, // paid but between prep bursts (yearly)
  text: { reps: 25, voice: 0 },
  light: { reps: 20, voice: 45 }, // a mock or two a month
  prepping: { reps: 16, voice: 280 }, // about three mocks a week
  heavy: { reps: 35, voice: 325 }, // sits on the weekly cap every week
};
type Seg = keyof typeof SEGMENT;
const MIX: Record<"weekly" | "yearly", Partial<Record<Seg, number>>> = {
  weekly: { text: 0.2, light: 0.3, prepping: 0.35, heavy: 0.15 }, // bought mid-prep
  yearly: { idle: 0.35, text: 0.25, light: 0.2, prepping: 0.15, heavy: 0.05 }, // bursts across the year
};
const BASE = {
  appleCut: 0.15, // overridden per table: CUTS below
  yearlyShare: 0.35, // of new subscribers
  introOnly: 0.45, // weekly buyers who cancel after the $1.99 week
  fullWeeks: 7, // full-price weeks for weekly buyers who stay (about 14% weekly churn)
  voicePrice: 1,
  heavyShift: 0, // moves this share of every non-idle segment into "heavy"
};
type A = typeof BASE;

const segCost = (s: Seg, a: A) => SEGMENT[s].reps * rep(6, 1) + SEGMENT[s].voice * COST.voiceMinute * a.voicePrice;
function monthCost(plan: "weekly" | "yearly", a: A) {
  const mix = { ...MIX[plan] } as Record<Seg, number>;
  if (a.heavyShift) for (const s of ["text", "light", "prepping"] as Seg[]) if (mix[s]) { const m = mix[s] * a.heavyShift; mix[s] -= m; mix.heavy = (mix.heavy ?? 0) + m; }
  return (Object.entries(mix) as [Seg, number][]).reduce((t, [s, w]) => t + w * segCost(s, a), 0);
}

/** First-year value of one new subscriber: what Apple pays out minus what their usage costs. */
function subscriber(plan: "weekly" | "yearly", a: A) {
  if (plan === "yearly") {
    const revenue = kept(PRICE.yearly, a.appleCut), cost = 12 * monthCost("yearly", a);
    return { revenue, cost, net: revenue - cost, months: 12 };
  }
  const weeks = 1 + (1 - a.introOnly) * a.fullWeeks;
  const revenue = kept(PRICE.weeklyIntro, a.appleCut) + (1 - a.introOnly) * a.fullWeeks * kept(PRICE.weekly, a.appleCut);
  // The intro week is the most intense one: a full prepping week for everyone.
  const introCost = (SEGMENT.prepping.voice / 4.33) * COST.voiceMinute * a.voicePrice + 4 * rep(6, 1);
  const cost = introCost + (1 - a.introOnly) * a.fullWeeks * (monthCost("weekly", a) / 4.33);
  return { revenue, cost, net: revenue - cost, months: weeks / 4.33 };
}
const payer = (a: A) => {
  const w = subscriber("weekly", a), y = subscriber("yearly", a);
  return { w, y, net: (1 - a.yearlyShare) * w.net + a.yearlyShare * y.net, revenue: (1 - a.yearlyShare) * w.revenue + a.yearlyShare * y.revenue };
};

/** What a download that never pays costs, expected and worst case. */
const freeExpected = (a: A) =>
  (FUNNEL.rep1 + FUNNEL.rep2) * rep(5, 1) + FUNNEL.unopenedQuestion * COST.question * COST.retry
  + FUNNEL.rep1 * FUNNEL.triesVoice * FUNNEL.freeVoiceMinutes * COST.voiceMinute * a.voicePrice;
const freeWorst = FREE.reps * rep(FREE.turns, FREE.help) + FREE.introSessions * FREE.sessionMinutes * COST.voiceMinute;

const $ = (v: number, d = 0) => (v < 0 ? "–" : "") + "$" + Math.abs(v).toLocaleString("en-US", { minimumFractionDigits: d, maximumFractionDigits: d });
const L: string[] = []; const out = (s = "") => { L.push(s); console.log(s); };

// ── 1. How much people can use it ────────────────────────────────────────────────────────────────────────
out("## 1. Caps and the most a user can cost\n");
out(`- Free, worst case, once: ${FREE.reps} maxed reps (${$(rep(FREE.turns, FREE.help), 3)} each) + ${FREE.introSessions}×${FREE.sessionMinutes} voice minutes = **${$(freeWorst, 2)}**`);
const maxProMonth = PRO.repsPerDay * 30 * rep(6, 1) + PRO_MAX_MINUTES_30_DAYS * COST.voiceMinute;
const maxProWeek = PRO.repsPerDay * 7 * rep(6, 1) + PRO.minutesPerWeek * COST.voiceMinute;
out(`- Pro, worst case: ${$(maxProWeek, 2)} a week (${PRO.repsPerDay} reps every day + ${PRO.minutesPerWeek} voice minutes), up to ${$(maxProMonth, 2)} in a 30-day month (${PRO_MAX_MINUTES_30_DAYS} voice minutes)`);
out(`- Voice alone at the weekly cap: ${$(PRO.minutesPerWeek * COST.voiceMinute, 2)} a week; a full-price week keeps ${$(kept(PRICE.weekly, 0.15), 2)} (15% cut) or ${$(kept(PRICE.weekly, 0.3), 2)} (30%)`);
out(`- Yearly keeps ${$(kept(PRICE.yearly, 0.15) / 12, 2)} a month (15% cut); voice at the cap every week costs ${$(PRO.minutesPerWeek * 4.33 * COST.voiceMinute, 2)} a month`);

// ── 2. How much we expect them to use it ─────────────────────────────────────────────────────────────────
out("\n## 2. Expected use\n");
out("| Pro segment | Reps a month | Voice minutes a month | Cost a month |\n|---|---|---|---|");
for (const s of Object.keys(SEGMENT) as Seg[]) out(`| ${s} | ${SEGMENT[s].reps} | ${SEGMENT[s].voice} | ${$(segCost(s, BASE), 2)} |`);
out(`\nAverage month: weekly subscriber ${$(monthCost("weekly", BASE), 2)}, yearly subscriber ${$(monthCost("yearly", BASE), 2)}.`);
out(`A download that never pays: ${$(freeExpected(BASE), 3)} expected, ${$(freeWorst, 2)} at most.`);
// Apple keeps 15% under the Small Business Program (under $1M a year, enrolled) and 30% otherwise; every table shows both.
const CUTS = [0.15, 0.3] as const;
const withCut = (cut: number, change: Partial<A> = {}) => ({ ...BASE, ...change, appleCut: cut });
out(`\nFirst-year value of one new subscriber:\n`);
out("| | " + CUTS.map(c => `Apple ${c * 100}%: keeps / costs / net`).join(" | ") + " |\n|---|" + CUTS.map(() => "---").join("|") + "|");
for (const [label, pick] of [["Weekly", "w"], ["Yearly", "y"]] as const)
  out(`| ${label} | ` + CUTS.map(c => { const q = payer(withCut(c))[pick]; return `${$(q.revenue, 2)} / ${$(q.cost, 2)} / **${$(q.net, 2)}**`; }).join(" | ") + " |");
out(`| Blended (${BASE.yearlyShare * 100}% yearly) | ` + CUTS.map(c => `**${$(payer(withCut(c)).net, 2)}** net`).join(" | ") + " |");

// ── 3. Conversion scenarios per 1,000 downloads ─────────────────────────────────────────────────────────
const RATES: [string, number][] = [["Very low", 0.01], ["Low", 0.03], ["Expected", 0.06], ["High", 0.1], ["Very high", 0.15]];
out("\n## 3. Per 1,000 downloads, first year (download-to-paid by day 35)\n");
out("| Scenario | Paying | Non-payers' cost | " + CUTS.map(c => `Cohort net, Apple ${c * 100}%`).join(" | ") + " |\n|---|---|---|" + CUTS.map(() => "---").join("|") + "|");
for (const [name, r] of RATES) {
  const payers = 1000 * r, freeCost = (1000 - payers) * freeExpected(BASE);
  out(`| ${name} (${r * 100}%) | ${payers} | ${$(-freeCost)} | ` + CUTS.map(c => `**${$(payers * payer(withCut(c)).net - freeCost)}**`).join(" | ") + " |");
}
for (const c of CUTS) {
  const net = payer(withCut(c)).net;
  out(`\nBreak-even conversion at Apple ${c * 100}%: ${(100 * freeExpected(BASE) / (net + freeExpected(BASE))).toFixed(2)}% expected; ${(100 * freeWorst / (net + freeWorst)).toFixed(1)}% if every non-payer maxes the free voice intro.`);
}

// ── 4. Monthly picture at a steady download rate ────────────────────────────────────────────────────────
for (const c of CUTS) {
  const q = payer(withCut(c));
  out(`\n## 4${c === 0.15 ? "a" : "b"}. Month 12 at a steady download rate, Apple ${c * 100}% (yearly subscribers have piled up; weekly ones turn over)\n`);
  out("| Downloads a month | " + RATES.map(([n, r]) => `${n} (${r * 100}%)`).join(" | ") + " |\n|---|" + RATES.map(() => "---").join("|") + "|");
  for (const d of [300, 1_000, 5_000, 20_000]) {
    const cells = RATES.map(([, r]) => {
      const newPay = d * r;
      // Each month's cohort contributes its weekly value once and its yearly value spread over 12 months; after 12 months both are steady.
      return $(newPay * (1 - BASE.yearlyShare) * q.w.net + newPay * BASE.yearlyShare * q.y.net - (d - newPay) * freeExpected(BASE) - FIXED_PER_MONTH);
    });
    out(`| ${d.toLocaleString("en-US")} | ${cells.join(" | ")} |`);
  }
}

// ── 5. What moves it ────────────────────────────────────────────────────────────────────────────────────
out("\n## 5. Sensitivity: blended net per paying user, first year\n");
const CASES: [string, Partial<A>][] = [
  ["Base", {}],
  ["Mostly yearly (70%)", { yearlyShare: 0.7 }],
  ["Mostly weekly (10% yearly)", { yearlyShare: 0.1 }],
  ["Most weekly buyers quit after the $1.99 week (70%)", { introOnly: 0.7 }],
  ["Weekly buyers stay longer (14 full weeks)", { fullWeeks: 14 }],
  ["Voice costs 50% more", { voicePrice: 1.5 }],
  ["Voice costs half", { voicePrice: 0.5 }],
  ["A third of each segment becomes heavy voice", { heavyShift: 0.33 }],
  ["Everyone heavy (stress test)", { heavyShift: 1 }],
];
out("| Case | " + CUTS.map(c => `Apple ${c * 100}%: weekly / yearly / blended (break-even)`).join(" | ") + " |\n|---|" + CUTS.map(() => "---").join("|") + "|");
for (const [name, change] of CASES) {
  out(`| ${name} | ` + CUTS.map(c => {
    const a = withCut(c, change), q = payer(a), f = freeExpected(a);
    return `${$(q.w.net, 2)} / ${$(q.y.net, 2)} / **${$(q.net, 2)}** (${q.net > 0 ? (100 * f / (q.net + f)).toFixed(2) + "%" : "never"})`;
  }).join(" | ") + " |");
}

mkdirSync(".local", { recursive: true });
writeFileSync(".local/launch-economics.md", L.join("\n") + "\n");
console.log("\nSaved to .local/launch-economics.md");
