import { timestamp } from "./domain";
import type { Env } from "./platform";

export type Plan = "free" | "pro";

/** Caps per plan. Pro's are fair-use guards against runaway cost, never shown as a quota. */
export function limits(env: Env, plan: Plan) {
  const n = (value: string | undefined, fallback: number) => {
    const parsed = Number(value);
    return Number.isFinite(parsed) && parsed > 0 ? parsed : fallback;
  };
  return plan === "pro"
    ? {
      repsPerDay: n(env.PRO_REPS_PER_DAY, 30),
      generationsPerDay: n(env.PRO_REPS_PER_DAY, 30),
      voiceStartsPerDay: n(env.PRO_VOICE_STARTS_PER_DAY, 20),
      voiceSessionSeconds: n(env.PRO_VOICE_SESSION_MINUTES, 20) * 60,
      voiceReasoningPerDay: 400,
      voiceFreeLifetime: Infinity,
      voiceTasteDays: 0,
      dailyQuestion: true,
    }
    : {
      repsPerDay: n(env.FREE_REPS_PER_DAY, 3),
      // Failed and refunded preparations also count here, so this sits above the rep allowance.
      generationsPerDay: 10,
      voiceStartsPerDay: n(env.FREE_VOICE_LIFETIME, 3),
      voiceSessionSeconds: n(env.FREE_VOICE_SESSION_MINUTES, 3) * 60,
      voiceReasoningPerDay: 40,
      voiceFreeLifetime: n(env.FREE_VOICE_LIFETIME, 3),
      voiceTasteDays: n(env.FREE_VOICE_TASTE_DAYS, 7),
      dailyQuestion: false,
    };
}

const listed = (value: string | undefined, account: string) =>
  (value ?? "").split(",").map(id => id.trim()).filter(Boolean).includes(account);

/**
 * Who pays decides what the account may do. Everyone is Pro while the gate is off (invite beta);
 * with it on, Pro comes from a verified App Store entitlement or an environment allowlist.
 */
export async function planFor(env: Env, account: string): Promise<Plan> {
  const override = await planOverride(env, account);
  if (override) return override;
  if (env.PRACTICE_GATE !== "true") return "pro";
  if (listed(env.PRACTICE_UNLIMITED_ACCOUNTS, account) || listed(env.VOICE_UNLIMITED_ACCOUNTS, account) || listed(env.DEVELOPER_ACCOUNTS, account)) return "pro";
  const row = await env.DB.prepare(
    "SELECT 1 FROM entitlements WHERE account_id=? AND status IN ('active','grace') AND (active_until IS NULL OR active_until>?) LIMIT 1",
  ).bind(account, timestamp()).first();
  return row ? "pro" : "free";
}

/** A developer's chosen plan, ahead of billing and the gate; nil for everyone else. */
export async function planOverride(env: Env, account: string): Promise<Plan | undefined> {
  if (!listed(env.DEVELOPER_ACCOUNTS, account)) return undefined;
  const row = await env.DB.prepare("SELECT plan_override FROM accounts WHERE id=?").bind(account).first<{ plan_override: Plan | null }>();
  return row?.plan_override ?? undefined;
}

export function nextUtcMidnight(now = timestamp()) {
  const next = new Date(now.slice(0, 10) + "T00:00:00.000Z");
  next.setUTCDate(next.getUTCDate() + 1);
  return next.toISOString();
}
export const utcDayStart = (now = timestamp()) => now.slice(0, 10) + "T00:00:00.000Z";
