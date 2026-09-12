import {env} from 'cloudflare:test';
import {beforeAll,it,expect} from 'vitest';
import {initializeDatabase} from './migrations';
import {accountFor,settingsFor} from '../src/store';
import {dailyQuestion} from '../src/daily';
import {reconcile} from '../src/jobs';
import type {Env} from '../src/platform';
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
