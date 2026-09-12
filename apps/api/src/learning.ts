import { isSocialOpening } from "./prompts/interviewer";
import { reflectionSchema } from "./domain";
import type { Env } from "./platform";

/** A quote must actually occur in user work; the model cannot certify authorship. */
export function groundReflection(raw: unknown, context: any) {
  const result = reflectionSchema.parse(raw);
  const answers = [context.answer, context.session?.answer,
    ...(Array.isArray(context.interview) ? context.interview : context.interview?.turns ?? [])
      .flatMap((t: any) => t.kind === "voice" ? [(t.voice ?? []).filter((f:any)=>f.speaker === "user").map((f:any)=>f.text).join("")] : t.kind === "answer" ? [t.answer ?? t.text] : [])]
    .filter((s): s is string => typeof s === "string" && s.trim().length > 0);
  const socialOnly = answers.length === 0 || answers.every(answer => isSocialOpening(answer)
    || /^(hey!?\s*)?nice to meet you[,!. ]*(this is just practice[.!]?)?$/i.test(answer.trim()));
  if (socialOnly) return {...result, summary: "We got acquainted; there isn’t a design to reflect on yet.", worked: [],
    improve: "When you’re ready, pick one piece of the problem to start with.",
    takeaway: "A small first decision is enough to get going.", strengths: [], gaps: [], evidence: [],
    nextExercise: "Choose one component in the original question and explain its responsibility."};
  result.nextExercise ??= result.improve;
  const concepts: string[] = context.question?.conceptIds ?? context.conceptIds ?? [];
  const assisted = !!context.exampleViewed || (context.adoptions?.length ?? 0) > 0
    || (context.help ?? []).some((h: any) => h.body)
    || (Array.isArray(context.interview) ? context.interview : context.interview?.turns ?? [])
      .some((t: any) => ["hint", "example"].includes(t.kind));
  result.evidence = (result.evidence ?? []).filter(e => concepts.includes(e.conceptId)
    && answers.some(answer => answer.includes(e.quote)))
    .filter((e,index,all) => all.findIndex(other => other.conceptId === e.conceptId && other.quote === e.quote && other.signal === e.signal) === index)
    .map(e => ({ ...e, assistance: assisted ? "assisted" as const : "unknown" as const }));
  return result;
}

/** Counts are practice exposure. Observations remain attributed model feedback. */
export async function learningEvidence(env: Env, account: string, level?: string) {
  const rows = await env.DB.prepare(`SELECT c.id,c.completed_at,r.data FROM challenges c
    JOIN reflections r ON r.challenge_id=c.id WHERE c.account_id=? AND c.lifecycle='completed' AND (? IS NULL OR json_extract(c.data,'$.engineeringLevel')=?)
    ORDER BY c.completed_at DESC,c.id DESC LIMIT 100`).bind(account,level ?? null,level ?? null)
    .all<{id:string;completed_at:string;data:string}>();
  return rows.results.flatMap(row => {
    const parsed = reflectionSchema.safeParse(JSON.parse(row.data));
    return (parsed.success ? parsed.data.evidence ?? [] : []).map(e => ({...e, sessionId:row.id, at:row.completed_at}));
  });
}
