import { Temporal } from "@js-temporal/polyfill";
import { z } from "zod";
import { defaultLearningPlan, Fault, reflectionSchema, timestamp, type Settings } from "./domain";
import type { Env } from "./platform";
import { isSocialOpening } from "./prompts/interviewer";
import type { ChallengeRow } from "./store";
import { activeChallenge, COUNTED, detail, ownedChallenge } from "./store";

export async function todayPlan(env: Env, account: string, active: ChallengeRow | null, settings: Settings) {
  const now = timestamp();
  const local = Temporal.Instant.from(now).toZonedDateTimeISO(settings.timezone);
  const dayStart = local.startOfDay().toInstant().toString();
  const weekStart = local.subtract({days:6}).startOfDay().toInstant().toString();
  const [counts,due] = await Promise.all([
    env.DB.prepare(`SELECT COUNT(*) completed_total,
      SUM(CASE WHEN completed_at>=? THEN 1 ELSE 0 END) completed_last_seven,
      SUM(CASE WHEN completed_at>=? THEN 1 ELSE 0 END) completed_today,
      MAX(json_extract(c.data,'$.ticket')) last_ticket
      FROM challenges c WHERE account_id=? AND lifecycle='completed' AND ${COUNTED}`)
      .bind(weekStart,dayStart,account).first<{completed_total:number;completed_last_seven:number;completed_today:number;last_ticket:number|null}>(),
    env.DB.prepare("SELECT COUNT(*) count FROM recall_cards WHERE account_id=? AND due_at<=?")
      .bind(account,now).first<{count:number}>(),
  ]);
  const plan = settings.learningPlan ?? defaultLearningPlan();
  const dueCount = due?.count ?? 0;
  const recommendationLimit = plan.dailyGoalMinutes * 2;
  const recommendedRecallCount = dueCount === 0 ? 0 : dueCount === 1 ? 1 : Math.min(dueCount, Math.max(2,recommendationLimit));
  const total = counts?.completed_total ?? 0;
  const state = active?.lifecycle === "in_progress" ? "resume"
    : total === 0 && active?.lifecycle === "ready" ? "first_session"
    : dueCount > 0 ? "review_due"
    : active?.lifecycle === "ready" ? "question_ready"
    : (counts?.completed_today ?? 0) > 0 ? "complete_today" : "prepare";
  return { state, completedTotal:total, completedLastSevenDays:counts?.completed_last_seven ?? 0,
    completedToday:counts?.completed_today ?? 0, dueRecallCount:dueCount, recommendedRecallCount,
    estimatedRecallMinutes:Math.ceil(recommendedRecallCount / 2), dailyGoalMinutes:plan.dailyGoalMinutes,
    // The number the next finished session gets; unfinished tickets show it provisionally.
    nextTicket:(counts?.last_ticket ?? 0) + 1 };
}

export const recallRatingSchema = z.object({
  rating: z.enum(["again", "got_it"]),
  responseMs: z.number().int().min(0).max(3_600_000).optional(),
});

type RecallRow = { id:string; source_challenge_id:string; concept_id:string; question:string; answer:string; due_at:string; interval_days:number; repetitions:number; lapses:number; created_at:string; updated_at:string; source_title?:string|null; source_completed_at?:string|null; source_ticket?:number|null; reflection_data?:string|null };
export function presentRecall(row: RecallRow) {
  let evidence: unknown;
  if (row.reflection_data) {
    const parsed = reflectionSchema.safeParse(JSON.parse(row.reflection_data));
    evidence = parsed.success ? parsed.data.evidence?.find(item => item.conceptId === row.concept_id) : undefined;
  }
  return { id:row.id, sourceChallengeId:row.source_challenge_id, conceptId:row.concept_id,
    question:row.question, answer:row.answer, dueAt:row.due_at, intervalDays:row.interval_days,
    repetitions:row.repetitions, lapses:row.lapses, createdAt:row.created_at, updatedAt:row.updated_at,
    sourceTitle:row.source_title ?? undefined, sourceCompletedAt:row.source_completed_at ?? undefined, sourceTicket:row.source_ticket ?? undefined, evidence };
}

export async function recallDeck(env: Env, account: string) {
  const now = timestamp();
  const [rows,due] = await Promise.all([env.DB.prepare(`SELECT rc.id,rc.source_challenge_id,rc.concept_id,rc.question,rc.answer,rc.due_at,rc.interval_days,rc.repetitions,rc.lapses,rc.created_at,rc.updated_at,
    json_extract(c.data,'$.title') source_title,c.completed_at source_completed_at,json_extract(c.data,'$.ticket') source_ticket,r.data reflection_data
    FROM recall_cards rc JOIN challenges c ON c.id=rc.source_challenge_id LEFT JOIN reflections r ON r.challenge_id=rc.source_challenge_id
    WHERE rc.account_id=? ORDER BY CASE WHEN rc.due_at<=? THEN 0 ELSE 1 END,rc.due_at,rc.id LIMIT 100`)
    .bind(account,now).all<RecallRow>(), env.DB.prepare("SELECT COUNT(*) count FROM recall_cards WHERE account_id=? AND due_at<=?").bind(account,now).first<{count:number}>()]);
  return { cards: rows.results.map(presentRecall), dueCount: due?.count ?? 0 };
}

export async function reviewRecall(env: Env, account: string, cardId: string, command: string, raw: unknown) {
  const input = recallRatingSchema.parse(raw), now = timestamp();
  const previous = await env.DB.prepare("SELECT card_id,rating FROM recall_reviews WHERE id=? AND account_id=?").bind(command,account).first<{card_id:string;rating:string}>();
  if (previous) {
    if (previous.card_id !== cardId || previous.rating !== input.rating) throw new Fault("command_reused",409,"This command belongs to another review.");
    const row = await env.DB.prepare("SELECT * FROM recall_cards WHERE id=? AND account_id=?").bind(cardId,account).first<RecallRow>();
    if (!row) throw new Fault("not_found",404,"Recall card not found.");
    return { card: presentRecall(row) };
  }
  const card = await env.DB.prepare("SELECT * FROM recall_cards WHERE id=? AND account_id=?").bind(cardId,account).first<RecallRow>();
  if (!card) throw new Fault("not_found",404,"Recall card not found.");
  const repetitions = input.rating === "got_it" ? card.repetitions + 1 : 0;
  const intervalDays = input.rating === "got_it" ? [1,3,7,14,30][Math.min(card.repetitions,4)] : 0;
  const due = new Date(Date.parse(now) + (input.rating === "got_it" ? intervalDays * 86400000 : 5 * 60000)).toISOString();
  await env.DB.batch([
    env.DB.prepare("INSERT OR IGNORE INTO recall_reviews(id,account_id,card_id,rating,response_ms,reviewed_at) VALUES(?,?,?,?,?,?)")
      .bind(command,account,cardId,input.rating,input.responseMs ?? null,now),
    env.DB.prepare("UPDATE recall_cards SET due_at=?,interval_days=?,repetitions=?,lapses=lapses+?,updated_at=? WHERE id=? AND account_id=? AND updated_at=? AND EXISTS(SELECT 1 FROM recall_reviews WHERE id=? AND account_id=? AND card_id=? AND rating=?)")
      .bind(due,intervalDays,repetitions,input.rating === "again" ? 1 : 0,now,cardId,account,card.updated_at,command,account,cardId,input.rating),
  ]);
  const receipt = await env.DB.prepare("SELECT card_id,rating FROM recall_reviews WHERE id=? AND account_id=?").bind(command,account).first<{card_id:string;rating:string}>();
  if (receipt?.card_id !== cardId || receipt.rating !== input.rating) throw new Fault("command_reused",409,"This command belongs to another review.");
  const updated = await env.DB.prepare("SELECT * FROM recall_cards WHERE id=? AND account_id=?").bind(cardId,account).first<RecallRow>();
  return { card: presentRecall(updated!) };
}

export async function retryMoment(env: Env, account: string, sourceId: string, turnId: string, command: string) {
  const replay = await env.DB.prepare("SELECT challenge_id FROM retry_sources WHERE challenge_id=?").bind(command).first<{challenge_id:string}>();
  if (replay) return detail(env,account,replay.challenge_id);
  const source = await ownedChallenge(env,account,sourceId);
  if (source.lifecycle !== "completed") throw new Fault("not_completed",409,"Finish this interview before branching from it.");
  if (await activeChallenge(env,account)) throw new Fault("active_challenge",409,"Finish or skip the current interview before retrying this moment.");
  const turn = await env.DB.prepare("SELECT prompt FROM interview_turns WHERE id=? AND challenge_id=?").bind(turnId,sourceId).first<{prompt:string}>();
  if (!turn) throw new Fault("not_found",404,"Interview moment not found.");
  const { ticket: _ticket, ...original } = JSON.parse(source.data) as Record<string,unknown>;
  const now = timestamp();
  const data = { ...original, title: `${String(original.title ?? "Interview").slice(0,148)} · Retry`, prompt: turn.prompt,
    selectionReason: "Retry a moment from a completed interview", startedAt: now };
  await env.DB.batch([
    env.DB.prepare("INSERT INTO challenges(id,account_id,lifecycle,data,created_at,available_at,command_id) VALUES(?,?,'in_progress',?,?,?,?)")
      .bind(command,account,JSON.stringify(data),now,now,command),
    env.DB.prepare("INSERT INTO sessions(challenge_id,answer,revision,command_id,updated_at) VALUES(?,'',0,?,?)")
      .bind(command,command,now),
    env.DB.prepare("INSERT INTO question_attempts(challenge_id,question_id) SELECT ?,question_id FROM question_attempts WHERE challenge_id=?")
      .bind(command,sourceId),
    env.DB.prepare("INSERT INTO retry_sources(challenge_id,source_challenge_id,source_turn_id) VALUES(?,?,?)")
      .bind(command,sourceId,turnId),
  ]);
  return detail(env,account,command);
}

/** A quote must actually occur in user work; the model cannot certify authorship. */
export function groundReflection(raw: unknown, context: any) {
  const result = reflectionSchema.parse(raw);
  const turns = Array.isArray(context.interview) ? context.interview : context.interview?.turns ?? [];
  const sources = [
    { id: undefined as string|undefined, text: context.answer },
    { id: undefined as string|undefined, text: context.session?.answer },
    ...turns.flatMap((t: any) => t.kind === "voice"
      ? [{id:t.id as string|undefined,text:(t.voice ?? []).filter((f:any)=>f.speaker === "user").map((f:any)=>f.text).join("")}]
      : t.kind === "answer" ? [{id:t.id as string|undefined,text:t.answer ?? t.text}] : []),
  ].filter((source): source is {id:string|undefined;text:string} => typeof source.text === "string" && source.text.trim().length > 0);
  const answers = sources.map(source => source.text);
  const socialOnly = answers.length === 0 || answers.every(answer => isSocialOpening(answer)
    || /^(hey!?\s*)?nice to meet you[,!. ]*(this is just practice[.!]?)?$/i.test(answer.trim()));
  if (socialOnly) return {...result, summary: "We got acquainted; there isn’t a design to reflect on yet.", worked: [],
    improve: "When you’re ready, pick one piece of the problem to start with.",
    takeaway: "A small first decision is enough to get going.", strengths: [], gaps: [], evidence: [],
    nextExercise: "Choose one component in the original question and explain its responsibility.",
    ...(result.lesson ? { lesson: { learned: [], tryAlone: "Pick one piece of the problem and make a first decision on your own." } } : {}),
    ...(result.debrief ? { debrief: { verdict: "not_yet" as const, reason: "There wasn’t enough design to judge yet.",
      signals: result.debrief.signals.map(signal => ({ ...signal, rating: "not_shown" as const, note: "" })),
      toPass: "Commit to one concrete design decision and say why." } } : {})};
  result.nextExercise ??= result.improve;
  const concepts: string[] = context.question?.conceptIds ?? context.conceptIds ?? [];
  const assisted = !!context.exampleViewed || (context.adoptions?.length ?? 0) > 0
    || (context.help ?? []).some((h: any) => h.body)
    || (Array.isArray(context.interview) ? context.interview : context.interview?.turns ?? [])
      .some((t: any) => ["hint", "example"].includes(t.kind));
  result.evidence = (result.evidence ?? []).flatMap(e => {
    if (!concepts.includes(e.conceptId)) return [];
    const quote = sources.map(source => candidateWords(e.quote, source.text)).find(Boolean);
    return quote ? [{ ...e, quote }] : [];
  })
    .filter((e,index,all) => all.findIndex(other => other.conceptId === e.conceptId && other.quote === e.quote && other.signal === e.signal) === index)
    .map(e => ({ ...e, assistance: assisted ? "assisted" as const : "unknown" as const,
      sourceTurnId: sources.find(source => source.id && source.text.includes(e.quote))?.id }));
  return result;
}

// Each replacement is one character for one, so indexes in the normalised text match the original.
const straightQuotes = (text: string) => text.replace(/[\u2018\u2019\u02BC]/g, "'").replace(/[\u201C\u201D]/g, '"').replace(/\u00A0/g, " ");
/** The candidate's own words for a model quote, tolerating curly/straight quote swaps and an added or dropped final stop. */
export function candidateWords(quote: string, text: string): string | undefined {
  const source = straightQuotes(text);
  for (const candidate of new Set([quote, quote.replace(/[.!?]+$/, "")])) {
    const needle = straightQuotes(candidate).trim();
    const index = needle ? source.indexOf(needle) : -1;
    if (index >= 0) return text.slice(index, index + needle.length);
  }
}

/** Counts are practice exposure. Observations remain attributed model feedback. */
export async function learningEvidence(env: Env, account: string, level?: string) {
  const rows = await env.DB.prepare(`SELECT c.id,c.completed_at,r.data FROM challenges c
    JOIN reflections r ON r.challenge_id=c.id WHERE c.account_id=? AND c.lifecycle='completed' AND ${COUNTED} AND (? IS NULL OR json_extract(c.data,'$.engineeringLevel')=?)
    ORDER BY c.completed_at DESC,c.id DESC LIMIT 100`).bind(account,level ?? null,level ?? null)
    .all<{id:string;completed_at:string;data:string}>();
  return rows.results.flatMap(row => {
    const parsed = reflectionSchema.safeParse(JSON.parse(row.data));
    return (parsed.success ? parsed.data.evidence ?? [] : []).map(e => ({...e, sessionId:row.id, at:row.completed_at}));
  });
}
