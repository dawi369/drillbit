import { Fault, timestamp } from "./domain";
import type { Env } from "./platform";

const WEEK_MS = 7 * 86_400_000;

/** Free reps apply only while the gate is switched on, and never to allowlisted accounts. */
export function onFreeReps(env: Env, account: string) {
  return env.PRACTICE_GATE === "true"
    && !(env.PRACTICE_UNLIMITED_ACCOUNTS ?? "").split(",").map(id => id.trim()).filter(Boolean).includes(account);
}

export const freeRepCutoff = (now = Date.now()) => new Date(now - WEEK_MS).toISOString();

/** True when a free rep was taken after the cutoff: a question prepared as one, or its preparation still running. */
export function freeRepTaken(account: string, cutoff = freeRepCutoff()) {
  return {
    sql: "(EXISTS(SELECT 1 FROM challenges WHERE account_id=? AND json_extract(data,'$.freeRepAt')>?) OR EXISTS(SELECT 1 FROM jobs WHERE account_id=? AND kind='generate' AND status IN ('pending','running') AND json_extract(input,'$.freeRepAt')>?))",
    binds: [account, cutoff, account, cutoff] as unknown[],
  };
}

export async function practiceAccess(env: Env, account: string, now = Date.now()) {
  if (!onFreeReps(env, account)) return { freeReps: false, available: true, nextFreeRepAt: null };
  const last = await env.DB.prepare(
    "SELECT MAX(t) t FROM (SELECT json_extract(data,'$.freeRepAt') t FROM challenges WHERE account_id=? UNION ALL SELECT json_extract(input,'$.freeRepAt') FROM jobs WHERE account_id=? AND kind='generate' AND status IN ('pending','running'))",
  ).bind(account, account).first<{ t: string | null }>();
  const next = last?.t ? Date.parse(last.t) + WEEK_MS : 0;
  return next > now
    ? { freeReps: true, available: false, nextFreeRepAt: new Date(next).toISOString() }
    : { freeReps: true, available: true, nextFreeRepAt: null };
}

export const practiceGateFault = () => new Fault("practice_gate", 402, "You’ve used this week’s free rep.");

/** Starting a rep without a generation (Library, retry) checks first; the one-active-challenge constraint bounds the race. */
export async function claimFreeRep(env: Env, account: string) {
  if (!onFreeReps(env, account)) return {};
  const taken = freeRepTaken(account);
  if (await env.DB.prepare("SELECT 1 WHERE " + taken.sql).bind(...taken.binds).first()) throw practiceGateFault();
  return { freeRepAt: timestamp() };
}

/** Follow-up and nudge budgets inside a free rep; configurable while costs are measured. */
export function freeRepLimit(env: Env, account: string, data: { freeRepAt?: unknown }, kind: string, turns: { kind: string }[]) {
  if (!data.freeRepAt || !onFreeReps(env, account)) return;
  const help = ["hint", "example"].includes(kind);
  const limit = Number(help ? env.FREE_REP_NUDGES ?? 2 : env.FREE_REP_FOLLOW_UPS ?? 8);
  const used = turns.filter(t => help ? ["hint", "example"].includes(t.kind) : ["answer", "continue", "clarification"].includes(t.kind)).length;
  if (used >= limit) throw new Fault("free_rep_limit", 429, help
    ? "That’s all the nudges a free rep gets. Keep going, or finish for feedback."
    : "That’s every follow-up a free rep gets. Finish to see your feedback.");
}
