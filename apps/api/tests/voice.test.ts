import {env} from 'cloudflare:test';
import {beforeAll,it,expect,vi} from 'vitest';
import {initializeDatabase} from './migrations';
import {accountFor,complete,detail,settingsFor} from '../src/store';
import {startVoice,voiceEvents,delegateVoice,voiceCapability} from '../src/voice';
import {requestInterview} from '../src/interview';
import type {Env} from '../src/platform';
const e={...env,VOICE_ENABLED:'true',OPENAI_API_KEY:'test',MANAGED_AI_ENABLED:'true',OPENROUTER_API_KEY:'test',JOBS:{create:async()=>({id:'test'})}} as unknown as Env;
beforeAll(()=>initializeDatabase(e.DB));
async function fixture(){const account=await accountFor(e,crypto.randomUUID()),id=crypto.randomUUID();await e.DB.prepare("UPDATE accounts SET status='active' WHERE id=?").bind(account.id).run();await e.DB.prepare("INSERT INTO challenges(id,account_id,lifecycle,data,created_at,available_at) VALUES(?,?,'in_progress',?,'now','now')").bind(id,account.id,JSON.stringify({title:'Queue',prompt:'Design a job queue',topic:'System design'})).run();await e.DB.prepare("INSERT INTO sessions(challenge_id,answer,revision,updated_at) VALUES(?,'Unfinished typed answer',2,'now')").bind(id).run();return {a:account.id,id};}
function connection(){return vi.spyOn(globalThis,'fetch').mockResolvedValue(new Response(JSON.stringify({session:{id:'live_test'},transport:{sdp:'answer'}}),{status:201}));}
const fragment={id:'event1',sequence:0,speaker:'user',text:'Use a durable queue.',startMs:0,endMs:1000};
it('reserves one paid voice session, rejects competing starts and preserves drafts',async()=>{const {a,id}=await fixture(),mock=connection();try{const outcomes=await Promise.allSettled([startVoice(e,a,id,crypto.randomUUID(),{sdp:'offer',revision:2}),startVoice(e,a,id,crypto.randomUUID(),{sdp:'offer',revision:2})]);expect(outcomes.filter(r=>r.status==='fulfilled')).toHaveLength(1);expect(mock).toHaveBeenCalledTimes(1);const d=await detail(e,a,id);expect(d.session).toMatchObject({answer:'Unfinished typed answer',revision:2});await expect(requestInterview(e,a,id,crypto.randomUUID(),{kind:'hint',revision:2})).rejects.toMatchObject({code:'voice_active'});await expect(complete(e,a,id,crypto.randomUUID(),'answer',2,await settingsFor(e,a))).rejects.toMatchObject({code:'voice_active'});}finally{mock.mockRestore();}});
it('deduplicates concurrent fragments, rejects collisions and isolates accounts',async()=>{const {a,id}=await fixture(),cmd=crypto.randomUUID(),mock=connection();try{await startVoice(e,a,id,cmd,{sdp:'offer',revision:2});}finally{mock.mockRestore();}await Promise.all([voiceEvents(e,a,id,cmd,{fragments:[fragment]}),voiceEvents(e,a,id,cmd,{fragments:[fragment]})]);expect((await detail(e,a,id)).interview.turns[0].voice).toHaveLength(1);await expect(voiceEvents(e,a,id,cmd,{fragments:[{...fragment,text:'other'}]})).rejects.toMatchObject({code:'voice_event_conflict'});const other=await fixture();await expect(voiceEvents(e,other.a,id,cmd,{fragments:[]})).rejects.toMatchObject({status:404});});
it('freezes voice content at completion without generating another response',async()=>{const {a,id}=await fixture(),cmd=crypto.randomUUID(),mock=connection();try{await startVoice(e,a,id,cmd,{sdp:'offer',revision:2});}finally{mock.mockRestore();}await voiceEvents(e,a,id,cmd,{fragments:[fragment],closed:true,finalized:true});await complete(e,a,id,crypto.randomUUID(),'',2,await settingsFor(e,a));const frozen=await e.DB.prepare('SELECT data FROM completion_context WHERE challenge_id=?').bind(id).first<any>();expect(JSON.parse(frozen.data).interview[0].voice[0].text).toBe(fragment.text);await expect(voiceEvents(e,a,id,cmd,{fragments:[{...fragment,id:'late',sequence:1}]})).rejects.toMatchObject({code:'inactive'});await voiceEvents(e,a,id,cmd,{fragments:[fragment]});expect((await detail(e,a,id)).interview.turns).toHaveLength(1);});
it('failed configuration performs no paid startup',async()=>{const {a,id}=await fixture(),mock=connection();try{await expect(startVoice({...e,OPENAI_API_KEY:undefined},a,id,crypto.randomUUID(),{sdp:'offer',revision:2})).rejects.toMatchObject({code:'voice_unavailable'});expect(mock).not.toHaveBeenCalled();}finally{mock.mockRestore();}});
it('closed sessions cannot delegate new paid work',async()=>{const {a,id}=await fixture(),cmd=crypto.randomUUID(),mock=connection();try{await startVoice(e,a,id,cmd,{sdp:'offer',revision:2});await voiceEvents(e,a,id,cmd,{fragments:[],closed:true,finalized:false});await expect(delegateVoice(e,a,id,cmd,{id:'d1'})).rejects.toMatchObject({code:'inactive'});expect(mock).toHaveBeenCalledTimes(1);}finally{mock.mockRestore();}});
it('does not activate a session if the question was skipped during provider startup',async()=>{const {a,id}=await fixture(),cmd=crypto.randomUUID();const mock=vi.spyOn(globalThis,'fetch').mockImplementation(async()=>{await e.DB.prepare("UPDATE challenges SET lifecycle='skipped' WHERE id=?").bind(id).run();return new Response(JSON.stringify({session:{id:'live_late'},transport:{sdp:'answer'}}));});try{await expect(startVoice(e,a,id,cmd,{sdp:'offer',revision:2})).rejects.toMatchObject({code:'inactive'});const row=await e.DB.prepare('SELECT status FROM voice_sessions WHERE id=?').bind(cmd).first<any>();expect(row.status).toBe('uncertain');}finally{mock.mockRestore();}});

it('voice capability is read-only, account-scoped and reflects the daily limit', async()=>{
 const {a}=await fixture(), other=await fixture();
 expect((await voiceCapability(e,a)).available).toBe(true);
 expect((await voiceCapability({...e,VOICE_ENABLED:'false'},a)).available).toBe(false);
 const day=new Date().toISOString().slice(0,10);
 await e.DB.prepare("INSERT INTO usage(account_id,day,kind,count) VALUES(?,?,'voice_start',6)").bind(a,day).run();
 expect((await voiceCapability(e,a)).available).toBe(false);
 expect((await voiceCapability(e,other.a)).available).toBe(true);
 expect((await e.DB.prepare("SELECT count FROM usage WHERE account_id=? AND day=? AND kind='voice_start'").bind(a,day).first<any>()).count).toBe(6);
});

it('unlimited voice is an exact account override and still records usage', async()=>{
 const {a,id}=await fixture(), other=await fixture();
 const owner={...e,VOICE_UNLIMITED_ACCOUNTS: a};
 const day=new Date().toISOString().slice(0,10);
 for (const account of [a,other.a]) await e.DB.prepare("INSERT INTO usage(account_id,day,kind,count) VALUES(?,?,'voice_start',6)").bind(account,day).run();
 expect((await voiceCapability(owner,a)).available).toBe(true);
 expect((await voiceCapability(owner,other.a)).available).toBe(false);
 expect((await voiceCapability({...owner,VOICE_ENABLED:'false'},a)).available).toBe(false);
 expect((await voiceCapability({...owner,VOICE_UNLIMITED_ACCOUNTS:a+'-suffix'},a)).available).toBe(false);
 const mock=connection();
 try {
  const session=crypto.randomUUID();
  await startVoice(owner,a,id,session,{sdp:'offer',revision:2}); expect(mock).toHaveBeenCalledTimes(1);
  await e.DB.prepare("INSERT INTO usage(account_id,day,kind,count) VALUES(?,?,'voice_reasoning',40)").bind(a,day).run();
  mock.mockResolvedValue(new Response(JSON.stringify({choices:[{message:{content:'What happens on a retry?'}}],usage:{prompt_tokens:1,completion_tokens:1}}),{status:200}));
  expect(await delegateVoice(owner,a,id,session,{id:'over-limit'})).toEqual({text:'What happens on a retry?'});
  expect((await e.DB.prepare("SELECT count FROM usage WHERE account_id=? AND day=? AND kind='voice_reasoning'").bind(a,day).first<any>()).count).toBe(41);
 }
 finally { mock.mockRestore(); }
 expect((await e.DB.prepare("SELECT count FROM usage WHERE account_id=? AND day=? AND kind='voice_start'").bind(a,day).first<any>()).count).toBe(7);
});
