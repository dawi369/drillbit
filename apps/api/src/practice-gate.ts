import { Fault, timestamp } from "./domain";
import { limits, nextUtcMidnight, planFor, utcDayStart } from "./plans";
import type { Env } from "./platform";

/** Free reps apply to free accounts only; the gate flag and allowlists resolve through the plan. */
export async function onFreeReps(env: Env, account: string) {
  return (await planFor(env, account)) === "free";
}

/** Reps spent since UTC midnight: questions prepared as free reps, or preparations still running. A swap shares its stamp, so it counts once. */
export function freeRepsSpent(account: string, since = utcDayStart()) {
  return {
    sql: "(SELECT COUNT(DISTINCT t) FROM (SELECT json_extract(data,'$.freeRepAt') t FROM challenges WHERE account_id=? UNION ALL SELECT json_extract(input,'$.freeRepAt') FROM jobs WHERE account_id=? AND kind='generate' AND status IN ('pending','running')) WHERE t>=?)",
    binds: [account, account, since] as unknown[],
  };
}

/** True when today's free reps are all spent; used as the atomic guard on preparation inserts. */
export function freeRepTaken(env: Env, account: string, since = utcDayStart()) {
  const spent = freeRepsSpent(account, since);
  return { sql: `(${spent.sql} >= ?)`, binds: [...spent.binds, limits(env, "free").repsPerDay] };
}

export async function practiceAccess(env: Env, account: string, now = timestamp()) {
  const plan = await planFor(env, account);
  if (plan === "pro") return { plan, freeReps: false, available: true, nextFreeRepAt: null };
  const limit = limits(env, "free").repsPerDay;
  const spent = freeRepsSpent(account, utcDayStart(now));
  const row = await env.DB.prepare("SELECT " + spent.sql + " AS n").bind(...spent.binds).first<{ n: number }>();
  const remaining = Math.max(0, limit - (row?.n ?? 0));
  const resetsAt = nextUtcMidnight(now);
  return remaining > 0
    ? { plan, freeReps: true, available: true, nextFreeRepAt: null, remaining, limit, resetsAt }
    : { plan, freeReps: true, available: false, nextFreeRepAt: resetsAt, remaining, limit, resetsAt };
}

export const practiceGateFault = () => new Fault("practice_gate", 402, "That’s today’s free reps. More come back tomorrow, or go Pro.");

/** Starting a rep without a generation (Library, retry) checks first; the one-active-challenge constraint bounds the race. */
export async function claimFreeRep(env: Env, account: string) {
  if (!(await onFreeReps(env, account))) return {};
  const taken = freeRepTaken(env, account);
  if (await env.DB.prepare("SELECT 1 WHERE " + taken.sql).bind(...taken.binds).first()) throw practiceGateFault();
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
