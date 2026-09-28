import { env } from 'cloudflare:test';
import { beforeAll, expect, it } from 'vitest';
import { dailyQuestion, queueFollowUp, queuedFollowUp, unqueueFollowUp } from '../src/daily';
import { reconcile } from '../src/jobs';
import type { Env } from '../src/platform';
import { accountFor, settingsFor } from '../src/store';
import { initializeDatabase } from './migrations';
const e={...env,JOBS:{create:async()=>({id:'test'})}} as unknown as Env;
beforeAll(()=>initializeDatabase(e.DB));
async function account(zone='America/New_York') {
 const a=await accountFor(e,crypto.randomUUID());
 await e.DB.prepare("UPDATE accounts SET status='active' WHERE id=?").bind(a.id).run();
 const settings=await settingsFor(e,a.id);
 await e.DB.prepare('UPDATE settings SET data=? WHERE account_id=?').bind(JSON.stringify({...settings,timezone:zone}),a.id).run();
 return a.id;
}
it('concurrent devices create one job; failure does not regenerate until the next local day',async()=>{
 const a=await account(); const now=new Date('2026-03-08T06:59:00Z');
 await Promise.all([dailyQuestion(e,a,now),dailyQuestion(e,a,now)]);
 const jobs=await e.DB.prepare("SELECT id FROM jobs WHERE account_id=? AND kind='generate'").bind(a).all();
 expect(jobs.results).toHaveLength(1);
 await e.DB.prepare("UPDATE jobs SET status='failed' WHERE account_id=?").bind(a).run();
 expect((await dailyQuestion(e,a,new Date('2026-03-08T07:01:00Z'))).job).toBeUndefined();
 expect((await dailyQuestion(e,a,new Date('2026-03-09T04:00:00Z'))).job).toBeTruthy();
});
it('keeps existing work across midnight and consumes the day even if that work later disappears',async()=>{
 const a=await account('Asia/Tokyo'),id=crypto.randomUUID();
 await e.DB.prepare("INSERT INTO challenges(id,account_id,lifecycle,data,created_at,available_at) VALUES(?,?,'in_progress',?,'now','now')").bind(id,a,JSON.stringify({title:'Queue',prompt:'Design a queue',topic:'System design'})).run();
 const first=await dailyQuestion(e,a,new Date('2026-09-12T16:00:00Z'));
 expect(first.day).toBe('2026-09-13');expect(first.challenge?.id).toBe(id);
 await e.DB.prepare("UPDATE challenges SET lifecycle='completed' WHERE id=?").bind(id).run();
 expect((await dailyQuestion(e,a,new Date('2026-09-12T17:00:00Z'))).job).toBeUndefined();
 const other=await account('Asia/Tokyo');expect((await dailyQuestion(e,other,new Date('2026-09-12T17:00:00Z'))).job).toBeTruthy();
});
it('cron does not generate questions from overdue settings or replace a ready question',async()=>{
 const a=await account();await e.DB.prepare("UPDATE settings SET next_due='2000-01-01T00:00:00Z' WHERE account_id=?").bind(a).run();
 await reconcile(e);
 expect((await e.DB.prepare("SELECT id FROM jobs WHERE account_id=? AND kind='generate'").bind(a).all()).results).toHaveLength(0);
});
async function completedSession(a:string,data:Record<string,unknown>={}) {
 const id=crypto.randomUUID();
 await e.DB.prepare("INSERT INTO challenges(id,account_id,lifecycle,data,created_at,available_at,completed_at) VALUES(?,?,'completed',?,'2026-09-27T10:00:00Z','2026-09-27T10:00:00Z','2026-09-27T10:20:00Z')")
  .bind(id,a,JSON.stringify({title:'Webhooks that land once',prompt:'Design webhook delivery.',topic:'System design',primaryConceptId:'retry-safety',...data})).run();
 await e.DB.prepare("INSERT INTO sessions(challenge_id,answer,revision,updated_at) VALUES(?,'Retry every failure.',1,'2026-09-27T10:20:00Z')").bind(id).run();
 return id;
}
const generation=async(a:string)=>(await e.DB.prepare("SELECT input FROM jobs WHERE account_id=? AND kind='generate'").bind(a).all<{input:string}>()).results.map(r=>JSON.parse(r.input));
it('a session saved for tomorrow shapes the next automatic question exactly once, even across devices',async()=>{
 const a=await account(),source=await completedSession(a);
 expect(await queueFollowUp(e,a,source)).toMatchObject({sourceId:source,title:'Webhooks that land once',conceptId:'retry-safety',label:'Retry safety & idempotency'});
 // An already-prepared candidate waits; the requested follow-up goes first.
 const prepared=crypto.randomUUID();
 await e.DB.prepare("INSERT INTO challenges(id,account_id,lifecycle,data,created_at,available_at) VALUES(?,?,'prepared',?,'now','now')").bind(prepared,a,JSON.stringify({title:'Prepared',prompt:'Prepared question',topic:'System design'})).run();
 const day=new Date('2026-09-28T13:00:00Z');
 await Promise.all([dailyQuestion(e,a,day,{guidanceMode:'mock_interview'}),dailyQuestion(e,a,day,{guidanceMode:'mock_interview'})]);
 const inputs=await generation(a);
 expect(inputs).toHaveLength(1);
 expect(inputs[0]).toMatchObject({followUpId:source,guidanceMode:'mock_interview',followUp:{question:{id:source},answer:'Retry every failure.'}});
 expect(await queuedFollowUp(e,a)).toBeNull();
 expect((await e.DB.prepare('SELECT lifecycle FROM challenges WHERE id=?').bind(prepared).first<{lifecycle:string}>())?.lifecycle).toBe('prepared');
});
it('the tomorrow queue holds one session, can be cancelled, and never takes unfinished work or a warm-up',async()=>{
 const a=await account(),first=await completedSession(a),second=await completedSession(a,{title:'Rate limiter'});
 await queueFollowUp(e,a,first);
 expect((await queueFollowUp(e,a,second))?.sourceId).toBe(second);
 expect(await unqueueFollowUp(e,a,first)).toMatchObject({sourceId:second});
 expect(await unqueueFollowUp(e,a,second)).toBeNull();
 const warm=await completedSession(a,{warmUp:true});
 await expect(queueFollowUp(e,a,warm)).rejects.toMatchObject({code:'warm_up'});
 const open=crypto.randomUUID();
 await e.DB.prepare("INSERT INTO challenges(id,account_id,lifecycle,data,created_at,available_at) VALUES(?,?,'in_progress',?,'now','now')").bind(open,a,JSON.stringify({title:'Open',prompt:'Open question',topic:'System design'})).run();
 await expect(queueFollowUp(e,a,open)).rejects.toMatchObject({code:'not_completed'});
 await expect(queueFollowUp(e,await account(),first)).rejects.toMatchObject({code:'not_found'});
 // Deleting the source cancels the queue.
 await queueFollowUp(e,a,first);
 await e.DB.prepare('DELETE FROM challenges WHERE id=?').bind(first).run();
 expect(await queuedFollowUp(e,a)).toBeNull();
});
