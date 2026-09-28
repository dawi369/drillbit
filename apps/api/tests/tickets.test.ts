import {env} from 'cloudflare:test';
import {beforeAll,expect,it} from 'vitest';
import {initializeDatabase} from './migrations';
import migration from '../migrations/0013_tickets_and_tomorrow.sql?raw';
import {accountFor,complete,detail,settingsFor} from '../src/store';
import {retryMoment,todayPlan} from '../src/learning';
import type {Env} from '../src/platform';
const e={...env,JOBS:{create:async()=>({id:'test'})}} as unknown as Env;
beforeAll(()=>initializeDatabase(e.DB));
async function account() {
 const a=await accountFor(e,crypto.randomUUID());
 await e.DB.prepare("UPDATE accounts SET status='active' WHERE id=?").bind(a.id).run();
 return a.id;
}
async function finished(account:string,data:Record<string,unknown>={}) {
 const id=crypto.randomUUID(),now=new Date().toISOString();
 await e.DB.batch([
  e.DB.prepare("INSERT INTO challenges(id,account_id,lifecycle,data,created_at,available_at) VALUES(?,?,'in_progress',?,?,?)").bind(id,account,JSON.stringify({title:'Queue',prompt:'Design a durable job queue.',topic:'System design',...data}),now,now),
  e.DB.prepare("INSERT INTO sessions(challenge_id,answer,revision,updated_at) VALUES(?,'',0,?)").bind(id,now),
 ]);
 await complete(e,account,id,crypto.randomUUID(),'Use a durable queue with acknowledgements.',0,await settingsFor(e,account));
 return id;
}
const ticket=async(account:string,id:string)=>(await detail(e,account,id) as {ticket?:number}).ticket;

it('numbers finished sessions in order, keeps gaps after a delete and leaves warm-ups unnumbered',async()=>{
 const a=await account();
 const first=await finished(a),warm=await finished(a,{warmUp:true}),second=await finished(a);
 expect(await ticket(a,first)).toBe(1);
 expect(await ticket(a,warm)).toBeUndefined();
 expect(await ticket(a,second)).toBe(2);
 await e.DB.prepare('DELETE FROM challenges WHERE id=?').bind(first).run();
 expect(await ticket(a,await finished(a))).toBe(3);
 expect((await todayPlan(e,a,null,await settingsFor(e,a))).nextTicket).toBe(4);
 const other=await account();
 expect((await todayPlan(e,other,null,await settingsFor(e,other))).nextTicket).toBe(1);
});

it('a branch retry gets its own number instead of inheriting its source',async()=>{
 const a=await account(),source=await finished(a),turn=crypto.randomUUID(),at=new Date().toISOString();
 await e.DB.batch([
  e.DB.prepare("INSERT INTO jobs(id,account_id,challenge_id,kind,status,input,created_at,updated_at) VALUES(?,?,?,'interview','completed','{}',?,?)").bind(turn,a,source,at,at),
  e.DB.prepare("INSERT INTO interview_turns(id,challenge_id,ordinal,kind,prompt,text,job_id,created_at) VALUES(?,?,0,'answer','What if the worker crashes?','Retry it.',?,?)").bind(turn,source,turn,at),
 ]);
 const branch=await retryMoment(e,a,source,turn,crypto.randomUUID());
 expect((branch as {ticket?:number}).ticket).toBeUndefined();
 await complete(e,a,branch.id,crypto.randomUUID(),'Make the handler idempotent.',0,await settingsFor(e,a));
 expect(await ticket(a,branch.id)).toBe(2);
});

it('the migration backfills older sessions in completion order and skips warm-ups',async()=>{
 const a=await account(),ids=[crypto.randomUUID(),crypto.randomUUID(),crypto.randomUUID()];
 const rows:[string,string,object][]=[[ids[0],'2026-01-02T00:00:00Z',{}],[ids[1],'2026-01-01T00:00:00Z',{}],[ids[2],'2026-01-03T00:00:00Z',{warmUp:true}]];
 for (const [id,at,extra] of rows)
  await e.DB.prepare("INSERT INTO challenges(id,account_id,lifecycle,data,created_at,available_at,completed_at) VALUES(?,?,'completed',?,?,?,?)").bind(id,a,JSON.stringify({title:'Old',prompt:'An older question.',topic:'System design',...extra}),at,at,at).run();
 const backfill=migration.split(';').find(statement=>statement.includes('UPDATE challenges'))!;
 await e.DB.prepare(backfill).run();
 await e.DB.prepare(backfill).run();
 expect(await ticket(a,ids[1])).toBe(1);
 expect(await ticket(a,ids[0])).toBe(2);
 expect(await ticket(a,ids[2])).toBeUndefined();
});
