import { Temporal } from '@js-temporal/polyfill';
import { activeChallenge, createJob, detail, settingsFor } from './store';
import { consumeUsage, type Env } from './platform';

export async function dailyQuestion(env: Env, account: string, now = new Date()) {
 const settings = await settingsFor(env,account);
 const day = Temporal.Instant.from(now.toISOString()).toZonedDateTimeISO(settings.timezone).toPlainDate().toString();
 const claimed = await env.DB.prepare('INSERT OR IGNORE INTO daily_visits(account_id,local_day,created_at) VALUES(?,?,?) RETURNING local_day').bind(account,day,now.toISOString()).first();
 // Existing cloud work always wins over a stale or empty device cache.
 let active = await activeChallenge(env,account);
 if (!active) {
  await env.DB.prepare("UPDATE challenges SET lifecycle='ready' WHERE id=(SELECT id FROM challenges WHERE account_id=? AND lifecycle='prepared' ORDER BY created_at DESC LIMIT 1) AND NOT EXISTS(SELECT 1 FROM challenges WHERE account_id=? AND lifecycle IN ('ready','in_progress'))").bind(account,account).run();
  active = await activeChallenge(env,account);
 }
 if (active) return {day,challenge:await detail(env,account,active.id)};
 const pending = await env.DB.prepare("SELECT * FROM jobs WHERE account_id=? AND kind='generate' AND status IN ('pending','running') LIMIT 1").bind(account).first();
 if (pending) return {day,job:pending};
 if (!claimed) return {day};
 // A failed check/generation consumes today's automatic opportunity; Retry is explicit.
 await consumeUsage(env,account,'generate',10);
 return {day,job:await createJob(env,account,crypto.randomUUID(),'generate',null,{settings})};
}
