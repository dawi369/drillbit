import { z } from "zod";
import { timestamp } from "./domain";
import { consumeUsage, type Env } from "./platform";

/** Where the app can show the paywall; the database enforces the same list. */
export const PAYWALL_PLACEMENTS = ["practice_rep", "voice_session", "knowledge_map", "first_rep"] as const;
export const paywallViewSchema = z.object({ placement: z.enum(PAYWALL_PLACEMENTS) });

/**
 * Counts one paywall presentation for the signed-in account: placement and time, nothing else. A generous daily
 * cap keeps a looping client from filling the table; the app never waits on this.
 */
export async function recordPaywallView(env: Env, account: string, raw: unknown) {
  const { placement } = paywallViewSchema.parse(raw);
  await consumeUsage(env, account, "paywall_view", 50, "That’s a lot of paywalls for one day.");
  await env.DB.prepare("INSERT INTO paywall_views(account_id,placement,created_at) VALUES(?,?,?)").bind(account, placement, timestamp()).run();
}
