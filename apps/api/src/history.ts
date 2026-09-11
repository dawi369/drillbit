import type { Env } from "./platform";

/** Bounded factual snapshot; no raw old answers or inferred skill scores. */
export async function historicalSnapshot(env: Env, account: string, excludeAttempt = "") {
  const rows = await env.DB.prepare(`SELECT c.id,c.data,c.lifecycle,c.completed_at,c.created_at,r.data AS feedback
    FROM challenges c LEFT JOIN reflections r ON r.challenge_id=c.id
    WHERE c.account_id=? AND c.id<>? AND c.lifecycle IN ('completed','skipped')
    ORDER BY COALESCE(c.completed_at,c.created_at) DESC,c.id DESC LIMIT 8`)
    .bind(account, excludeAttempt).all<{id:string;data:string;lifecycle:string;completed_at:string|null;created_at:string;feedback:string|null}>();
  return {
    version: "history-v1", scope: "latest 8 completed or skipped attempts; not exhaustive",
    generatedAt: new Date().toISOString(),
    attempts: rows.results.map(row => {
      const q = JSON.parse(row.data), feedback = row.feedback ? JSON.parse(row.feedback) : null;
      return { attemptId: row.id, scenario: String(q.scenario ?? q.title ?? "").slice(0,100),
        engineeringLevel: q.engineeringLevel ?? null, conceptIds: Array.isArray(q.conceptIds) ? q.conceptIds.slice(0,3) : [],
        status: row.lifecycle, at: row.completed_at ?? row.created_at, assistance: "unknown; do not infer independent work",
        feedback: row.lifecycle === "completed" && feedback ? { provenance: "prior model feedback, not a skill assessment", observation: String(feedback.summary ?? "").slice(0,240), nextPractice: String(feedback.improve ?? "").slice(0,240) } : null };
    }),
  };
}
