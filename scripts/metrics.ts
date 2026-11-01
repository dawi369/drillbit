/**
 * Launch numbers from D1: the funnel, conversion, plan mix, voice use per plan, limit hits and AI cost. Aggregates
 * only: no account ids, no practice text. These are the measurements docs/paywall-plan.md sections 13–14 ask for.
 *
 *   bun scripts/metrics.ts                     # production, last 30 days, App Store purchases only
 *   bun scripts/metrics.ts --days 7            # a shorter window
 *   bun scripts/metrics.ts --sandbox           # count Sandbox purchases too (App Review, TestFlight, you)
 *   bun scripts/metrics.ts --development       # development D1
 *
 * Needs wrangler logged in to the Cloudflare account.
 */
import { execFileSync } from "node:child_process";
import { join } from "node:path";

const args = process.argv.slice(2);
const development = args.includes("--development");
const days = Math.max(1, Number(args[args.indexOf("--days") + 1]) || 30);
const environments = args.includes("--sandbox") ? "'Production','Sandbox'" : "'Production'";
const VOICE_PER_MINUTE = 0.051; // measured, docs/paywall-plan.md section 9
const root = join(import.meta.dir, "..");

const now = Date.now();
const iso = (msAgo: number) => new Date(now - msAgo).toISOString();
const DAY = 86_400_000;
const since = iso(days * DAY);
// Conversion needs cohorts old enough to have had their 35 days.
const matureFrom = iso((35 + days) * DAY), matureTo = iso(35 * DAY);

type Row = Record<string, number | string | null>;
function run(statements: string[]): Row[][] {
  const argv = ["d1", "execute", development ? "drillbit-development" : "drillbit-production", "--remote", "--json", "--command", statements.join(";\n")];
  if (!development) argv.push("--env", "production");
  const out = execFileSync(join(root, "apps/api/node_modules/.bin/wrangler"), argv, { cwd: join(root, "apps/api"), encoding: "utf8", maxBuffer: 64 * 1024 * 1024 });
  return (JSON.parse(out) as { results: Row[] }[]).map(r => r.results);
}

// A rep the person actually used: at least one typed or spoken message.
const used = (c: string) => `EXISTS(SELECT 1 FROM interview_turns t WHERE t.challenge_id=${c}.id AND t.kind IN ('answer','clarification')) OR EXISTS(SELECT 1 FROM voice_fragments f JOIN interview_turns t ON t.id=f.session_id WHERE t.challenge_id=${c}.id AND f.speaker='user')`;
const paid = (a: string, within?: string) => `EXISTS(SELECT 1 FROM entitlements e WHERE e.account_id=${a}.id AND e.environment IN (${environments})${within ? ` AND julianday(e.created_at)-julianday(${a}.created_at)<=${within}` : ""})`;
const funnel = (from: string, to: string, within?: string) => `SELECT COUNT(*) signups,
  SUM((SELECT COUNT(*) FROM challenges c WHERE c.account_id=a.id AND (${used("c")}))>=1) rep1,
  SUM((SELECT COUNT(*) FROM challenges c WHERE c.account_id=a.id AND (${used("c")}))>=2) rep2,
  SUM(${paid("a", within)}) paid
  FROM accounts a WHERE a.status='active' AND a.created_at>='${from}' AND a.created_at<'${to}'`;

const [recent, mature, plans, intro, voice, refunds, waived, limits, ai, notes] = run([
  funnel(since, iso(0)),
  funnel(matureFrom, matureTo, "35"),
  `SELECT product_id, status, COUNT(*) n FROM entitlements WHERE environment IN (${environments}) GROUP BY product_id, status ORDER BY product_id, status`,
  // Weekly buyers who stopped after the $1.99 week: expired within about eight days of buying.
  `SELECT COUNT(*) bought, SUM(status IN ('expired','revoked') AND julianday(active_until)-julianday(created_at)<=8) intro_only FROM entitlements WHERE environment IN (${environments}) AND product_id LIKE '%weekly' AND created_at>='${since}'`,
  // Voice minutes per account in the window, with the plan they're on now.
  `SELECT COALESCE((SELECT CASE WHEN e.product_id LIKE '%yearly' THEN 'yearly' ELSE 'weekly' END FROM entitlements e WHERE e.account_id=v.account_id AND e.environment IN (${environments}) AND e.status IN ('active','grace') LIMIT 1),'free') plan,
    SUM(COALESCE(v.usage_seconds,0))/60.0 minutes FROM voice_sessions v WHERE v.provider_id IS NOT NULL AND v.waived=0 AND v.created_at>='${since}' GROUP BY v.account_id`,
  `SELECT COUNT(*) n FROM challenges c WHERE json_extract(c.data,'$.freeRepAt') IS NOT NULL AND c.lifecycle IN ('skipped','expired') AND c.created_at>='${since}' AND NOT (${used("c")})`,
  `SELECT COUNT(*) n FROM voice_sessions WHERE waived=1 AND created_at>='${since}'`,
  `SELECT kind, COUNT(*) days_at_cap FROM usage WHERE day>='${since.slice(0, 10)}' AND ((kind='generate' AND count>=10) OR (kind='voice_start' AND count>=20) OR (kind='voice_note' AND count>=5)) GROUP BY kind`,
  `SELECT kind, COUNT(*) runs, ROUND(SUM(cost),4) cost FROM ai_runs WHERE created_at>='${since}' GROUP BY kind ORDER BY cost DESC`,
  `SELECT COUNT(*) n, ROUND(SUM(duration_seconds)/60.0,1) minutes FROM voice_notes WHERE created_at>='${since}'`,
]);

const pct = (part: unknown, whole: unknown) => Number(whole) ? `${((100 * Number(part)) / Number(whole)).toFixed(1)}%` : "–";
const n = (v: unknown) => Number(v ?? 0);
const quantile = (values: number[], q: number) => values.length ? values[Math.min(values.length - 1, Math.floor(q * values.length))] : 0;
const money = (v: number) => "$" + v.toFixed(2);

console.log(`Drillbit ${development ? "development" : "production"} · last ${days} days · purchases: ${environments.replaceAll("'", "")}\n`);

console.log("Funnel");
for (const [label, rows, note] of [[`signed up in the last ${days} days`, recent, "paid so far"], [`signed up 35–${35 + days} days ago`, mature, "paid within 35 days"]] as const) {
  const r = rows[0] ?? {};
  console.log(`  ${label}: ${n(r.signups)} · first rep ${n(r.rep1)} (${pct(r.rep1, r.signups)}) · both free reps ${n(r.rep2)} (${pct(r.rep2, r.signups)}) · ${note} ${n(r.paid)} (${pct(r.paid, r.signups)})`);
}

console.log("\nPlans");
if (!plans.length) console.log("  no purchases yet");
for (const r of plans) console.log(`  ${String(r.product_id).replace("dawi.drillbit.pro.", "")} ${r.status}: ${n(r.n)}`);
const active = plans.filter(r => ["active", "grace"].includes(String(r.status)));
const yearly = active.filter(r => String(r.product_id).endsWith("yearly")).reduce((t, r) => t + n(r.n), 0);
const all = active.reduce((t, r) => t + n(r.n), 0);
console.log(`  yearly share of active subscribers: ${pct(yearly, all)} (model assumes 35%)`);
console.log(`  weekly bought in window: ${n(intro[0]?.bought)} · stopped after the $1.99 week: ${n(intro[0]?.intro_only)} (${pct(intro[0]?.intro_only, intro[0]?.bought)}; model assumes 45%)`);

console.log(`\nVoice minutes per account in the window (model: yearly breaks even near 130 a month)`);
for (const plan of ["free", "weekly", "yearly"]) {
  const values = voice.filter(r => r.plan === plan).map(r => n(r.minutes)).sort((a, b) => a - b);
  console.log(`  ${plan.padEnd(6)} ${String(values.length).padStart(4)} accounts · median ${quantile(values, 0.5).toFixed(1)} · p90 ${quantile(values, 0.9).toFixed(1)} · max ${(values.at(-1) ?? 0).toFixed(1)}`);
}

console.log("\nLeaks and limits");
console.log(`  free reps refunded (skipped before a first message): ${n(refunds[0]?.n)}`);
console.log(`  free silent voice sessions: ${n(waived[0]?.n)}`);
if (!limits.length) console.log("  no one hit a daily cap");
const thresholds: Record<string, string> = { generate: "10+ questions written (free cap; Pro's is 20)", voice_start: "20 voice starts (Pro cap)", voice_note: "5 voice notes" };
for (const r of limits) console.log(`  account-days at ${thresholds[String(r.kind)] ?? r.kind}: ${n(r.days_at_cap)}`);

const textCost = ai.reduce((t, r) => t + n(r.cost), 0);
const voiceMinutes = voice.reduce((t, r) => t + n(r.minutes), 0);
console.log("\nAI cost");
for (const r of ai) console.log(`  ${String(r.kind).padEnd(12)} ${String(n(r.runs)).padStart(6)} runs  ${money(n(r.cost))}`);
console.log(`  text total ${money(textCost)} · voice about ${voiceMinutes.toFixed(0)} min ≈ ${money(voiceMinutes * VOICE_PER_MINUTE)} · together ≈ ${money(textCost + voiceMinutes * VOICE_PER_MINUTE)}`);

console.log(`\nVoice notes: ${n(notes[0]?.n)} (${n(notes[0]?.minutes)} min). Listen with: bun scripts/voice-notes.ts`);
