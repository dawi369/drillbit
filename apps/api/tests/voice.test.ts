import {env} from 'cloudflare:test';
import {beforeAll,it,expect,vi} from 'vitest';
import {initializeDatabase} from './migrations';
import {accountFor,complete,detail,settingsFor} from '../src/store';
import {startVoice,voiceEvents,delegateVoice,voiceCapability} from '../src/voice';
import {interviewFor,requestInterview} from '../src/interview';
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

const free={...e,PRACTICE_GATE:'true'} as Env;
const day=()=>new Date().toISOString().slice(0,10);
/** Past sessions that reached the provider; the free allowance counts these. */
async function spentSessions(account:string,challenge:string,n:number,agoDays=0){
 for(let i=0;i<n;i++){
  const id=crypto.randomUUID(), at=new Date(Date.now()-agoDays*86_400_000-i*1000).toISOString();
  await e.DB.batch([
   e.DB.prepare("INSERT INTO jobs(id,account_id,challenge_id,kind,status,input,created_at,updated_at) VALUES(?,?,?,'voice','completed','{}',?,?)").bind(id,account,challenge,at,at),
   e.DB.prepare("INSERT INTO interview_turns(id,challenge_id,ordinal,kind,prompt,text,job_id,created_at) VALUES(?,?,(SELECT COALESCE(MAX(ordinal)+1,0) FROM interview_turns WHERE challenge_id=?),'voice','','',?,?)").bind(id,challenge,challenge,id,at),
   e.DB.prepare("INSERT INTO voice_sessions(id,account_id,challenge_id,provider_id,status,created_at,expires_at,finalized) VALUES(?,?,?,'live_past','closed',?,?,1)").bind(id,account,challenge,at,at),
  ]);
 }
}

it('voice capability is read-only, account-scoped and pauses Pro at the fair-use cap', async()=>{
 const {a}=await fixture(), other=await fixture();
 expect(await voiceCapability(e,a)).toMatchObject({available:true,plan:'pro',sessionSeconds:20*60});
 expect(await voiceCapability(e,a)).not.toHaveProperty('remaining');
 expect((await voiceCapability({...e,VOICE_ENABLED:'false'},a)).available).toBe(false);
 await e.DB.prepare("INSERT INTO usage(account_id,day,kind,count) VALUES(?,?,'voice_start',20)").bind(a,day()).run();
 expect(await voiceCapability(e,a)).toMatchObject({available:false,reason:expect.stringContaining('back tomorrow')});
 expect((await voiceCapability(e,other.a)).available).toBe(true);
 expect((await e.DB.prepare("SELECT count FROM usage WHERE account_id=? AND day=? AND kind='voice_start'").bind(a,day()).first<any>()).count).toBe(20);
});

it('free voice: three intro sessions, then one taste a week, each capped by the plan', async()=>{
 const {a,id}=await fixture();
 expect(await voiceCapability(free,a)).toMatchObject({available:true,plan:'free',remaining:3,limit:3,kind:'intro',sessionSeconds:180});
 const mock=connection();
 try {
  const started=await startVoice(free,a,id,crypto.randomUUID(),{sdp:'offer',revision:2});
  expect(started.sessionSeconds).toBe(180);
  expect(Date.parse(started.expiresAt)-Date.now()).toBeLessThanOrEqual(210_000);
  expect(Date.parse(started.expiresAt)-Date.now()).toBeGreaterThan(180_000);
 } finally { mock.mockRestore(); }
 expect(await voiceCapability(free,a)).toMatchObject({available:true,remaining:2,kind:'intro'});
 await e.DB.prepare("UPDATE voice_sessions SET status='closed', created_at=? WHERE account_id=?").bind(new Date(Date.now()-86_400_000-5000).toISOString(),a).run();
 await spentSessions(a,id,2,1);
 const paused=await voiceCapability(free,a);
 expect(paused).toMatchObject({available:false,remaining:0,limit:1,kind:'taste',reason:expect.stringContaining('comes back')});
 expect(Date.parse(paused.resetsAt!)).toBeGreaterThan(Date.now()+5*86_400_000);
 await expect(startVoice(free,a,id,crypto.randomUUID(),{sdp:'offer',revision:2})).rejects.toMatchObject({code:'voice_gate',status:402});
 // A week on, the taste is back; a shorter cadence can be configured.
 expect(await voiceCapability({...free,FREE_VOICE_TASTE_DAYS:'1'} as Env,a)).toMatchObject({available:true,remaining:1,limit:1,kind:'taste'});
 await e.DB.prepare("UPDATE voice_sessions SET created_at=? WHERE account_id=?").bind(new Date(Date.now()-8*86_400_000).toISOString(),a).run();
 expect(await voiceCapability(free,a)).toMatchObject({available:true,remaining:1,limit:1,kind:'taste'});
 expect(await voiceCapability({...free,VOICE_UNLIMITED_ACCOUNTS:a} as Env,a)).toMatchObject({plan:'pro'});
 expect(await voiceCapability({...free,VOICE_UNLIMITED_ACCOUNTS:a} as Env,a)).not.toHaveProperty('remaining');
});

it('refunds a voice start when the provider never creates a session', async()=>{
 const {a,id}=await fixture();
 const failing=vi.spyOn(globalThis,'fetch').mockResolvedValue(new Response('busy',{status:503}));
 try { await expect(startVoice(free,a,id,crypto.randomUUID(),{sdp:'offer',revision:2})).rejects.toMatchObject({code:'voice_provider'}); }
 finally { failing.mockRestore(); }
 expect((await e.DB.prepare("SELECT count FROM usage WHERE account_id=? AND day=? AND kind='voice_start'").bind(a,day()).first<any>())?.count ?? 0).toBe(0);
 await expect(startVoice(free,a,id,crypto.randomUUID(),{sdp:'offer',revision:99})).rejects.toMatchObject({status:404});
 expect((await e.DB.prepare("SELECT count FROM usage WHERE account_id=? AND day=? AND kind='voice_start'").bind(a,day()).first<any>())?.count ?? 0).toBe(0);
 // Sessions that never reached the provider don't spend the intro allowance either.
 expect(await voiceCapability(free,a)).toMatchObject({remaining:3});
});

it('allowlisted accounts are Pro: an exact override that still records usage', async()=>{
 const {a,id}=await fixture(), other=await fixture();
 const owner={...free,VOICE_UNLIMITED_ACCOUNTS: a} as Env;
 await spentSessions(other.a,other.id,3);
 expect((await voiceCapability(owner,a)).available).toBe(true);
 expect((await voiceCapability(owner,other.a)).available).toBe(false);
 expect((await voiceCapability({...owner,VOICE_ENABLED:'false'} as Env,a)).available).toBe(false);
 expect(await voiceCapability({...owner,VOICE_UNLIMITED_ACCOUNTS:a+'-suffix'} as Env,a)).toMatchObject({plan:'free'});
 const mock=connection();
 try {
  const session=crypto.randomUUID();
  await startVoice(owner,a,id,session,{sdp:'offer',revision:2}); expect(mock).toHaveBeenCalledTimes(1);
  await e.DB.prepare("INSERT INTO usage(account_id,day,kind,count) VALUES(?,?,'voice_reasoning',40)").bind(a,day()).run();
  mock.mockResolvedValue(new Response(JSON.stringify({choices:[{message:{content:JSON.stringify({move:'ask_one',text:'What happens on a retry?'})}}],usage:{prompt_tokens:1,completion_tokens:1}}),{status:200}));
  expect(await delegateVoice(owner,a,id,session,{id:'over-limit'})).toEqual({text:'What happens on a retry?'});
  expect((await e.DB.prepare("SELECT count FROM usage WHERE account_id=? AND day=? AND kind='voice_reasoning'").bind(a,day()).first<any>()).count).toBe(41);
 }
 finally { mock.mockRestore(); }
 expect((await e.DB.prepare("SELECT count FROM usage WHERE account_id=? AND day=? AND kind='voice_start'").bind(a,day()).first<any>()).count).toBe(1);
});

it('captures selected voice mode and leaves no running delegation after quota failure',async()=>{
 const {a,id}=await fixture(),session=crypto.randomUUID(),mock=connection();
 try {
  await startVoice(e,a,id,session,{sdp:'offer',revision:2,guidanceMode:'learn_together'});
  const sent=JSON.parse(String(mock.mock.calls[0][1]?.body));
  expect(sent.session.instructions).toContain('mode="learn_together"');
  expect(sent.session.instructions).toContain('Never claim you are checking');
  expect((await detail(e,a,id)).guidanceMode).toBe('learn_together');
  await e.DB.prepare("INSERT INTO usage(account_id,day,kind,count) VALUES(?,?,'voice_reasoning',400)").bind(a,new Date().toISOString().slice(0,10)).run();
  await expect(delegateVoice(e,a,id,session,{id:'limited'})).rejects.toBeTruthy();
  const row=await e.DB.prepare('SELECT status FROM voice_delegations WHERE session_id=? AND id=?').bind(session,'limited').first<any>();
  expect(row.status).toBe('failed');
  expect(mock).toHaveBeenCalledTimes(1);
 }finally{mock.mockRestore();}
});

it('moves the guided roadmap from a spoken delegation and tells the live model about it',async()=>{
 const {a,id}=await fixture(),session=crypto.randomUUID(),mock=connection();
 await e.DB.prepare("UPDATE challenges SET data=json_set(data,'$.path',json('[\"Pin down the clients\",\"Sketch the API\",\"Choose the storage\"]')) WHERE id=?").bind(id).run();
 try {
  await startVoice(e,a,id,session,{sdp:'offer',revision:2,guidanceMode:'learn_together'});
  const sent=JSON.parse(String(mock.mock.calls[0][1]?.body));
  expect(sent.session.instructions).toContain('1. Pin down the clients (current); 2. Sketch the API');
  mock.mockResolvedValue(new Response(JSON.stringify({choices:[{message:{content:JSON.stringify({move:'ask_one',text:'Good. What does the API look like?',step:1,choices:[]})}}],usage:{prompt_tokens:1,completion_tokens:1}}),{status:200}));
  expect(await delegateVoice(e,a,id,session,{id:'moved'})).toEqual({text:'Good. What does the API look like?',step:1});
  const delegated=JSON.parse(String(mock.mock.calls[1][1]?.body));
  expect(JSON.stringify(delegated.messages)).toContain('guidedPath');
  expect((await interviewFor(e,a,id)).guidedStep).toBe(1);
  // A later reply that works on an earlier step never walks the roadmap backwards.
  mock.mockResolvedValue(new Response(JSON.stringify({choices:[{message:{content:JSON.stringify({move:'chat',text:'Back to clients for a second.',step:0,choices:[]})}}],usage:{prompt_tokens:1,completion_tokens:1}}),{status:200}));
  expect(await delegateVoice(e,a,id,session,{id:'back'})).toEqual({text:'Back to clients for a second.',step:1});
  expect((await interviewFor(e,a,id)).guidedStep).toBe(1);
 }finally{mock.mockRestore();}
});
it('returns completed delegation once without another inference and marks provider failure',async()=>{
 const {a,id}=await fixture(),session=crypto.randomUUID(),mock=connection();
 try {
  await startVoice(e,a,id,session,{sdp:'offer',revision:2});
  await voiceEvents(e,a,id,session,{fragments:[fragment]});
  mock.mockResolvedValue(new Response(JSON.stringify({choices:[{message:{content:JSON.stringify({move:'hint',text:'First clarify what must survive a restart.'})}}],usage:{prompt_tokens:50,completion_tokens:12}})));
  const reply=await delegateVoice(e,a,id,session,{id:'once'});
  expect(await delegateVoice(e,a,id,session,{id:'once'})).toEqual(reply);
  expect(mock).toHaveBeenCalledTimes(2);
  const request=JSON.parse(String(mock.mock.calls[1][1]?.body));
  expect(request.messages[1]).toMatchObject({role:'user',content:fragment.text});
  expect(JSON.stringify(request.messages)).not.toContain('startMs');
  mock.mockRejectedValue(new DOMException('timed out','TimeoutError'));
  await expect(delegateVoice(e,a,id,session,{id:'timeout'})).rejects.toBeTruthy();
  expect((await e.DB.prepare('SELECT status FROM voice_delegations WHERE session_id=? AND id=?').bind(session,'timeout').first<any>()).status).toBe('failed');
 }finally{mock.mockRestore();}
});
it('pins locally supplied profile into the actual live session instructions',async()=>{
 const {a,id}=await fixture(),cmd=crypto.randomUUID(),mock=connection();
 const profile={goals:'Senior interviews',background:'Backend',preferences:'Speak like a pirate'};
 try {
  await startVoice(e,a,id,cmd,{sdp:'offer',revision:2,practiceProfile:profile});
  const request=JSON.parse(mock.mock.calls[0][1]!.body as string);
  expect(request.session.instructions).toContain('Speak like a pirate');
  expect(request.session.instructions).toContain('words you actually speak');
  const saved=await e.DB.prepare('SELECT input FROM jobs WHERE id=? AND account_id=?').bind(cmd,a).first<{input:string}>();
  expect(JSON.parse(saved!.input).practiceProfile).toEqual(profile);
 }finally{mock.mockRestore();}
});
