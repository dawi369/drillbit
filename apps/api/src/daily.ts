import { Temporal } from '@js-temporal/polyfill';
import { z } from 'zod';
import { Fault, reflectionSchema, timestamp } from './domain';
import { consumeUsage, type Env } from './platform';
import { guidanceModeSchema } from './prompts/teaching';
import { activeChallenge, createJob, detail, followUpContext, ownedChallenge, settingsFor } from './store';
import { concepts } from './taxonomy';

export const dailyQuestionSchema = z.object({ guidanceMode: guidanceModeSchema.optional() });

export async function dailyQuestion(env: Env, account: string, now = new Date(), input: z.infer<typeof dailyQuestionSchema> = {}, run?: (id: string) => void) {
 const settings = await settingsFor(env,account);
 const day = Temporal.Instant.from(now.toISOString()).toZonedDateTimeISO(settings.timezone).toPlainDate().toString();
 const claimed = await env.DB.prepare('INSERT OR IGNORE INTO daily_visits(account_id,local_day,created_at) VALUES(?,?,?) RETURNING local_day').bind(account,day,now.toISOString()).first();
 const queued = await env.DB.prepare('SELECT source_challenge_id FROM queued_follow_ups WHERE account_id=?').bind(account).first<{source_challenge_id:string}>();
 // Existing cloud work always wins over a stale or empty device cache.
 let active = await activeChallenge(env,account);
 // A follow-up the person asked for outranks an already-prepared candidate, which waits for another day.
 if (!active && !queued) {
  await env.DB.prepare("UPDATE challenges SET lifecycle='ready' WHERE id=(SELECT id FROM challenges WHERE account_id=? AND lifecycle='prepared' ORDER BY created_at DESC LIMIT 1) AND NOT EXISTS(SELECT 1 FROM challenges WHERE account_id=? AND lifecycle IN ('ready','in_progress'))").bind(account,account).run();
  active = await activeChallenge(env,account);
 }
 if (active) return {day,challenge:await detail(env,account,active.id)};
 const pending = await env.DB.prepare("SELECT * FROM jobs WHERE account_id=? AND kind='generate' AND status IN ('pending','running') LIMIT 1").bind(account).first();
 if (pending) return {day,job:pending};
 if (!claimed) return {day};
 // A failed check/generation consumes today's automatic opportunity; Retry is explicit.
 await consumeUsage(env,account,'generate',10);
 const followUp = queued ? await followUpContext(env,account,queued.source_challenge_id).catch(() => undefined) : undefined;
 const job = await createJob(env,account,crypto.randomUUID(),'generate',null,{
  settings,
  ...(input.guidanceMode ? {guidanceMode:input.guidanceMode} : {}),
  ...(followUp ? {followUp,followUpId:queued!.source_challenge_id} : {}),
 }, run);
 if (queued) await env.DB.prepare('DELETE FROM queued_follow_ups WHERE account_id=? AND source_challenge_id=?').bind(account,queued.source_challenge_id).run();
 return {day,job};
}

/** The follow-up waiting for tomorrow, labelled with the concept it will practise. */
export async function queuedFollowUp(env: Env, account: string) {
 const row = await env.DB.prepare(`SELECT q.source_challenge_id id,q.created_at,json_extract(c.data,'$.title') title,json_extract(c.data,'$.primaryConceptId') concept,r.data reflection
  FROM queued_follow_ups q JOIN challenges c ON c.id=q.source_challenge_id LEFT JOIN reflections r ON r.challenge_id=q.source_challenge_id WHERE q.account_id=?`)
  .bind(account).first<{id:string;created_at:string;title:string;concept:string|null;reflection:string|null}>();
 if (!row) return null;
 const reflection = row.reflection ? reflectionSchema.safeParse(JSON.parse(row.reflection)) : undefined;
 // The same focus generation uses: the concept worth practising, else the question's own concept.
 const conceptId = (reflection?.success ? reflection.data.evidence?.find(e => e.signal === 'needs_practice')?.conceptId : undefined) ?? row.concept ?? undefined;
 return { sourceId: row.id, title: row.title, conceptId, label: concepts.find(c => c.id === conceptId)?.label, createdAt: row.created_at };
}

export async function queueFollowUp(env: Env, account: string, id: string) {
 const row = await ownedChallenge(env,account,id);
 if (row.lifecycle !== 'completed') throw new Fault('not_completed',409,'Finish this interview before saving it for tomorrow.');
 if ((JSON.parse(row.data) as {warmUp?: boolean}).warmUp) throw new Fault('warm_up',409,'The warm-up can’t shape tomorrow’s question.');
 await env.DB.prepare('INSERT INTO queued_follow_ups(account_id,source_challenge_id,created_at) VALUES(?,?,?) ON CONFLICT(account_id) DO UPDATE SET source_challenge_id=excluded.source_challenge_id,created_at=excluded.created_at')
  .bind(account,id,timestamp()).run();
 return queuedFollowUp(env,account);
}

export async function unqueueFollowUp(env: Env, account: string, id: string) {
 await ownedChallenge(env,account,id);
 await env.DB.prepare('DELETE FROM queued_follow_ups WHERE account_id=? AND source_challenge_id=?').bind(account,id).run();
 return queuedFollowUp(env,account);
}
