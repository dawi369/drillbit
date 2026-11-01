import { Fault, timestamp } from "./domain";
import { limits, nextUtcMidnight, planFor, utcDayStart } from "./plans";
import type { Env } from "./platform";

/** Free reps apply to free accounts only; the gate flag and allowlists resolve through the plan. */
export async function onFreeReps(env: Env, account: string) {
  return (await planFor(env, account)) === "free";
}

/**
 * The time of the user's `n`th message (1-based) on a rep, typed (answer or question) or spoken (each utterance; it
 * takes its voice session's start time). NULL until then. `c` is the challenges alias around it.
 */
const userMessageAt = (c: string, n: number) =>
  `(SELECT ts FROM (SELECT t.created_at ts,t.ordinal o,0 s FROM interview_turns t WHERE t.challenge_id=${c}.id AND t.kind IN ('answer','clarification') UNION ALL SELECT t.created_at,t.ordinal,f.sequence FROM voice_fragments f JOIN interview_turns t ON t.id=f.session_id WHERE t.challenge_id=${c}.id AND f.speaker='user') ORDER BY o,s LIMIT 1 OFFSET ${n - 1})`;
/** When a rep became practice for Pro's daily count: its second message. */
export const practisedAt = (c: string) => userMessageAt(c, 2);
/** A free rep skipped, or swapped away, before the user said anything was never used, so it doesn't count. One
 * message already earned an interviewer reply, so from then on the rep is spent. */
export const abandonedUnused = (c: string) => `(${c}.lifecycle IN ('skipped','expired') AND ${userMessageAt(c, 1)} IS NULL)`;

/** Reps spent since `since`: questions prepared as free reps (unless abandoned unused), preparations still running,
 * and reps whose question was later deleted. A swap shares its stamp, so it counts once. */
export function freeRepsSpent(account: string, since = utcDayStart()) {
  return {
    sql: `(SELECT COUNT(DISTINCT t) FROM (SELECT json_extract(fr.data,'$.freeRepAt') t FROM challenges fr WHERE fr.account_id=? AND NOT ${abandonedUnused("fr")} UNION ALL SELECT json_extract(input,'$.freeRepAt') FROM jobs WHERE account_id=? AND kind='generate' AND status IN ('pending','running') UNION ALL SELECT stamp FROM spent_free_reps WHERE account_id=?) WHERE t>=?)`,
    binds: [account, account, account, since] as unknown[],
  };
}

/** The free allowance: a lifetime count when `FREE_REPS_LIFETIME` is set (counted since the start of time), else today's. */
function allowance(env: Env, now = timestamp()) {
  const free = limits(env, "free");
  return free.repsLifetime ? { limit: free.repsLifetime, since: "", lifetime: true } : { limit: free.repsPerDay, since: utcDayStart(now), lifetime: false };
}

/** True when the free reps are all spent; used as the atomic guard on preparation inserts. */
export function freeRepTaken(env: Env, account: string) {
  const { limit, since } = allowance(env);
  const spent = freeRepsSpent(account, since);
  return { sql: `(${spent.sql} >= ?)`, binds: [...spent.binds, limit] };
}

export async function practiceAccess(env: Env, account: string, now = timestamp()) {
  const plan = await planFor(env, account);
  if (plan === "pro") return { plan, freeReps: false, available: true, nextFreeRepAt: null };
  const { limit, since, lifetime } = allowance(env, now);
  const spent = freeRepsSpent(account, since);
  const row = await env.DB.prepare("SELECT " + spent.sql + " AS n").bind(...spent.binds).first<{ n: number }>();
  const remaining = Math.max(0, limit - (row?.n ?? 0));
  // Lifetime reps never come back, so there's no reset to show.
  const resetsAt = lifetime ? null : nextUtcMidnight(now);
  const shape = { plan, freeReps: true, remaining, limit, resetsAt, ...(lifetime ? { lifetime: true } : {}) };
  return remaining > 0 ? { ...shape, available: true, nextFreeRepAt: null } : { ...shape, available: false, nextFreeRepAt: resetsAt };
}

export const practiceGateFault = (env?: Env) => new Fault("practice_gate", 402, env && limits(env, "free").repsLifetime
  ? "That’s your free reps. Go Pro to keep practising."
  : "That’s today’s free reps. More come back tomorrow, or go Pro.");

/** Pro's fair use: reps practised today (second message since UTC midnight). Only starting a new rep checks it, so a
 * rep already open always finishes; developers are counted, never stopped. */
export async function assertProRepAvailable(env: Env, account: string, now = timestamp()) {
  if ((env.DEVELOPER_ACCOUNTS ?? "").split(",").map(id => id.trim()).includes(account)) return;
  const limit = limits(env, "pro").repsPerDay;
  const row = await env.DB.prepare(`SELECT COUNT(*) AS n FROM challenges pr WHERE pr.account_id=? AND ${practisedAt("pr")}>=?`)
    .bind(account, utcDayStart(now)).first<{ n: number }>();
  if ((row?.n ?? 0) >= limit) throw new Fault("practice_limit", 429, `That’s ${limit} reps today, which is plenty. More tomorrow.`);
}

/** Starting a rep without a generation (Library, retry) checks first; the one-active-challenge constraint bounds the race. */
export async function claimRep(env: Env, account: string) {
  if (!(await onFreeReps(env, account))) { await assertProRepAvailable(env, account); return {}; }
  const taken = freeRepTaken(env, account);
  if (await env.DB.prepare("SELECT 1 WHERE " + taken.sql).bind(...taken.binds).first()) throw practiceGateFault(env);
  return { freeRepAt: timestamp() };
}

/** Follow-up and nudge budgets inside a free rep; configurable while costs are measured. */
export async function freeRepLimit(env: Env, account: string, data: { freeRepAt?: unknown }, kind: string, turns: { kind: string }[]) {
  if (!data.freeRepAt || !(await onFreeReps(env, account))) return;
  const help = ["hint", "example"].includes(kind);
  const limit = Number(help ? env.FREE_REP_NUDGES ?? 2 : env.FREE_REP_FOLLOW_UPS ?? 8);
  const used = turns.filter(t => help ? ["hint", "example"].includes(t.kind) : ["answer", "continue", "clarification"].includes(t.kind)).length;
  if (used >= limit) throw new Fault("free_rep_limit", 429, help
    ? "That’s all the nudges and examples a free rep gets. Keep going, or finish for feedback."
    : "That’s every follow-up a free rep gets. Finish to see your feedback.");
}
