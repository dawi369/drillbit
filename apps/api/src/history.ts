import { learningEvidence } from "./learning";
import type { Env } from "./platform";

/** Bounded factual snapshot; no raw old answers or inferred skill scores. */
export async function historicalSnapshot(env: Env, account: string, excludeAttempt = "", relevantConcepts: string[] = []) {
  const [rows, coverage, evidence] = await Promise.all([env.DB.prepare(`SELECT c.id,c.data,c.lifecycle,c.completed_at,c.created_at,r.data AS feedback
    FROM challenges c LEFT JOIN reflections r ON r.challenge_id=c.id
    WHERE c.account_id=? AND c.id<>? AND c.lifecycle IN ('completed','skipped')
    ORDER BY COALESCE(c.completed_at,c.created_at) DESC,c.id DESC LIMIT 8`)
    .bind(account, excludeAttempt).all<{id:string;data:string;lifecycle:string;completed_at:string|null;created_at:string;feedback:string|null}>(),
    env.DB.prepare(`SELECT json_extract(q.data,'$.engineeringLevel') engineeringLevel, t.value conceptId,
      COUNT(*) completedAttempts, MAX(c.completed_at) lastPractised
      FROM questions q JOIN question_attempts x ON x.question_id=q.id JOIN challenges c ON c.id=x.challenge_id
      JOIN json_each(json_extract(q.data,'$.conceptIds')) t
      WHERE q.account_id=? AND c.account_id=? AND c.lifecycle='completed'
      GROUP BY engineeringLevel,t.value ORDER BY engineeringLevel,t.value`).bind(account,account)
      .all<{engineeringLevel:string|null;conceptId:string;completedAttempts:number;lastPractised:string|null}>(),
    learningEvidence(env,account),
  ]);
  const latest = new Map<string, typeof evidence>();
  for (const item of evidence) {
    const entries = latest.get(item.conceptId);
    if (!entries) latest.set(item.conceptId,[item]);
    else if(entries[0].sessionId === item.sessionId) entries.push(item);
  }
  const relevant = [...latest.values()].flat().sort((a,b)=>Number(relevantConcepts.includes(b.conceptId))-Number(relevantConcepts.includes(a.conceptId)));

  return {
    version: "history-v2", scope: "All-history concept exposure by level; latest 8 completed/skipped attempts; up to 6 latest concept observations from the last 100 completed reflections. Not a mastery assessment.",
    coverage: [...coverage.results].sort((a,b)=>Number(relevantConcepts.includes(b.conceptId))-Number(relevantConcepts.includes(a.conceptId)) || a.completedAttempts-b.completedAttempts || (a.lastPractised ?? "").localeCompare(b.lastPractised ?? "")).slice(0,18),
    coverageScope: "Up to 18 level/concept aggregates, question-relevant first then less-practised. Counts cover all completed history; omitted concepts are unknown, not zero.",
    learning: relevant.slice(0,6).map(item=>({conceptId:item.conceptId,signal:item.signal,observation:item.observation.slice(0,320),quote:item.quote.slice(0,240),assistance:item.assistance,sessionId:item.sessionId,at:item.at,provenance:"quoted candidate work with fallible model interpretation; newer evidence supersedes older observations"})),
    generatedAt: new Date().toISOString(),
    attempts: rows.results.map(row => {
      const q = JSON.parse(row.data), feedback = row.feedback ? JSON.parse(row.feedback) : null;
      return { attemptId: row.id, scenario: String(q.scenario ?? q.title ?? "").slice(0,100),
        engineeringLevel: q.engineeringLevel ?? null, conceptIds: Array.isArray(q.conceptIds) ? q.conceptIds.slice(0,3) : [],
        status: row.lifecycle, at: row.completed_at ?? row.created_at, assistance: "unknown; do not infer independent work",
        feedback: row.lifecycle === "completed" && feedback ? { provenance: "prior model feedback, not a skill assessment", observation: String(feedback.summary ?? "").slice(0,240), nextPractice: String(feedback.nextExercise ?? feedback.improve ?? "").slice(0,400) } : null };
    }),
  };
}
