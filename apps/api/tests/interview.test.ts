import { env } from "cloudflare:test";
import { beforeAll, it, expect, vi } from "vitest";
import { initializeDatabase } from "./migrations";
import { accountFor, complete, detail, settingsFor } from "../src/store";
import { requestInterview, retryInterview, interviewFor } from "../src/interview";
import { runJob } from "../src/jobs";
import { streamedInterview } from "../src/ai";
import { interviewSchemaFor } from "../src/interview";
import type { Env } from "../src/platform";
const e = {...env,MANAGED_AI_ENABLED:"true",OPENROUTER_API_KEY:"test",JOBS:{create:async()=>({id:"test"})}} as unknown as Env;
beforeAll(()=>initializeDatabase(e.DB));
async function fixture(style="standard") {
 const a=await accountFor(e,crypto.randomUUID()),id=crypto.randomUUID();
 await e.DB.prepare("UPDATE accounts SET status='active' WHERE id=?").bind(a.id).run();
 await e.DB.prepare("INSERT INTO challenges(id,account_id,lifecycle,data,created_at,available_at) VALUES(?,?,'in_progress',?,'now','now')").bind(id,a.id,JSON.stringify({title:"Queue",prompt:"Design a reliable job queue.",topic:"Backend",interviewStyle:style})).run();
 await e.DB.prepare("INSERT INTO sessions(challenge_id,answer,revision,updated_at) VALUES(?,'Use a queue',2,'now')").bind(id).run();
 return {a:a.id,id};
}
function streamed(result: object) { return new Response('data: ' + JSON.stringify({choices:[{delta:{content:JSON.stringify({move:"ask_one",...result})}}]}) + '\n\ndata: [DONE]\n\n',{status:200}); }
function provider(result: object) { return vi.spyOn(globalThis,"fetch").mockImplementation(async()=>streamed(result)); }
it("commits exactly one answer snapshot and rejects stale or competing devices",async()=>{
 const {a,id}=await fixture(),cmd=crypto.randomUUID(),input={kind:"answer",text:"Use a queue",revision:2};
 const results=await Promise.allSettled([requestInterview(e,a,id,cmd,input),requestInterview(e,a,id,crypto.randomUUID(),input)]);
 expect(results.filter(r=>r.status==="fulfilled")).toHaveLength(1);
 const state=await interviewFor(e,a,id);expect(state.turns).toHaveLength(1);expect(state.turns[0].text).toBe("Use a queue");
 const winner=state.turns[0].id;
 expect((await requestInterview(e,a,id,winner,input)).turns).toHaveLength(1);
 await expect(requestInterview(e,a,id,winner,{...input,text:"Other"})).rejects.toMatchObject({code:"command_reused"});
 const d=await detail(e,a,id);expect(d.session).toMatchObject({answer:"",revision:3});
 await expect(requestInterview(e,a,id,crypto.randomUUID(),input)).rejects.toBeTruthy();
 const other=await fixture();await expect(interviewFor(e,other.a,id)).rejects.toMatchObject({status:404});
});
it("clarification preserves the draft and prompt; answers advance only through a completed follow-up",async()=>{
 const {a,id}=await fixture();const cmd=crypto.randomUUID();
 await requestInterview(e,a,id,cmd,{kind:"clarification",text:"What scale?",revision:2});
 let mock=provider({outcome:"reply",text:"Assume one thousand jobs per minute."});await runJob(e,cmd);mock.mockRestore();
 let d=await detail(e,a,id);expect(d.session).toMatchObject({answer:"Use a queue",revision:3});expect(d.interview.prompt).toBe("Design a reliable job queue.");
 const answer=crypto.randomUUID();await requestInterview(e,a,id,answer,{kind:"answer",text:"Use a queue",revision:3});
 mock=provider({outcome:"follow_up",text:"What happens if a worker crashes?"});await runJob(e,answer);mock.mockRestore();
 d=await detail(e,a,id);expect(d.interview.prompt).toBe("What happens if a worker crashes?");expect(d.interview.turns).toHaveLength(2);
});
it("retries response generation without duplicating or resubmitting the answer",async()=>{
 const {a,id}=await fixture(),cmd=crypto.randomUUID();await requestInterview(e,a,id,cmd,{kind:"answer",text:"Use a queue",revision:2});
 await e.DB.prepare("UPDATE jobs SET status='failed' WHERE id=?").bind(cmd).run();
 const next=crypto.randomUUID();await retryInterview(e,a,id,cmd,next);await retryInterview(e,a,id,cmd,next);
 const mock=provider({outcome:"follow_up",text:"How do retries work?"});await runJob(e,next);mock.mockRestore();
 const state=await interviewFor(e,a,id);expect(state.turns).toHaveLength(1);expect(state.turns[0].jobId).toBe(next);expect(state.prompt).toBe("How do retries work?");
});
it("completion freezes shared turns, cancels pending replies and rejects late writes",async()=>{
 const {a,id}=await fixture(),cmd=crypto.randomUUID();await requestInterview(e,a,id,cmd,{kind:"answer",text:"Use a queue",revision:2});
 const mock=vi.spyOn(globalThis,"fetch").mockImplementation(async()=>{
  await complete(e,a,id,crypto.randomUUID(),"",3,await settingsFor(e,a));
  return streamed({outcome:"follow_up",text:"Late question"});
 });
 await expect(runJob(e,cmd)).rejects.toBeTruthy();mock.mockRestore();
 const d=await detail(e,a,id);expect(d.lifecycle).toBe("completed");expect(d.interview.turns[0].result).toBeNull();
 const frozen=await e.DB.prepare("SELECT data FROM completion_context WHERE challenge_id=?").bind(id).first<{data:string}>();
 expect(JSON.parse(frozen!.data).interview[0]).toMatchObject({answer:"Use a queue",kind:"answer",delivery:"unknown"});
 await expect(requestInterview(e,a,id,crypto.randomUUID(),{kind:"hint",revision:4})).rejects.toMatchObject({code:"inactive"});
});
it.each(["quick","standard","in_depth"])("retains %s style independently of engineering level",async style=>{
 const {a,id}=await fixture(style);expect((await interviewFor(e,a,id)).style).toBe(style);
});
it("Quick continues until the user explicitly finishes",async()=>{
 const {a,id}=await fixture("quick"),first=crypto.randomUUID();
 await requestInterview(e,a,id,first,{kind:"answer",text:"Use a queue",revision:2});
 let mock=provider({outcome:"follow_up",text:"What happens on redelivery?"});await runJob(e,first);mock.mockRestore();
 await e.DB.prepare("UPDATE sessions SET answer='Use a stable idempotency key',revision=4 WHERE challenge_id=?").bind(id).run();
 const second=crypto.randomUUID();await requestInterview(e,a,id,second,{promptId:first,kind:"answer",text:"Use a stable idempotency key",revision:4});
 mock=provider({outcome:"follow_up",text:"Must not be called"});await runJob(e,second);expect(mock).toHaveBeenCalled();mock.mockRestore();
 expect((await interviewFor(e,a,id)).wrapUp).toBe(false);
});
it("normalizes unavailable styles while retaining old-client idempotency",async()=>{
 const {a,id}=await fixture();const cmd=crypto.randomUUID();
 const input={kind:"clarification",text:"What scale?",revision:2,style:"in_depth"};
 await requestInterview(e,a,id,cmd,input);
 expect((await interviewFor(e,a,id)).style).toBe("standard");
 const job=await e.DB.prepare("SELECT input FROM jobs WHERE id=?").bind(cmd).first<{input:string}>();
 expect(JSON.parse(job!.input).context.interview.style).toBe("standard");
 await requestInterview(e,a,id,cmd,input);
 await expect(requestInterview(e,a,id,cmd,{...input,style:"quick"})).rejects.toMatchObject({code:"command_reused"});
 const mock=provider({outcome:"reply",text:"Assume a thousand users."});await runJob(e,cmd);mock.mockRestore();
 await expect(requestInterview(e,a,id,crypto.randomUUID(),{kind:"answer",text:"Use a queue",revision:2,style:"quick"})).rejects.toMatchObject({code:"revision_conflict"});
 expect((await interviewFor(e,a,id)).style).toBe("standard");
 await requestInterview(e,a,id,crypto.randomUUID(),{kind:"answer",text:"Use a queue",revision:3});
 expect((await detail(e,a,id)).interviewStyle).toBe("standard");
});
it("publishes real provider text before completion and scopes stream readers",async()=>{
 const {partialInterviewText}=await import("../src/ai");
 const {interviewStreamSnapshot}=await import("../src/interview");
 expect(partialInterviewText('{"text":"Hello\\nwor')).toBe("Hello\nwor");
 expect(partialInterviewText('{"text":"a\\u00')).toBe("a");
 const {a,id}=await fixture(),cmd=crypto.randomUUID();
 await requestInterview(e,a,id,cmd,{kind:"answer",text:"Use a queue",revision:2});
 let controller!: ReadableStreamDefaultController<Uint8Array>;
 const encoder=new TextEncoder();
 const body=new ReadableStream<Uint8Array>({start(c){controller=c;}});
 const mock=vi.spyOn(globalThis,"fetch").mockResolvedValue(new Response(body));
 const work=runJob(e,cmd);
 const emit=(text:string)=>controller.enqueue(encoder.encode('data: '+JSON.stringify({choices:[{delta:{content:text}}]})+'\n\n'));
 emit('{"move":"ask_one","text":"What happens');
 try {
  await vi.waitFor(async()=>expect((await interviewStreamSnapshot(e,a,id,cmd)).text).toBe("What happens"));
  expect((await interviewFor(e,a,id)).turns[0].result).toBeNull();
  const other=await fixture();await expect(interviewStreamSnapshot(e,other.a,id,cmd)).rejects.toMatchObject({status:404});
  emit(' on retry?"}');controller.enqueue(encoder.encode('data: [DONE]\n\n'));controller.close();
  await work;
  expect(await interviewStreamSnapshot(e,a,id,cmd)).toMatchObject({status:"completed",text:"What happens on retry?"});
 } finally {mock.mockRestore();}
});

it("captures bounded account-scoped historical evidence with a pinned prompt edition", async()=>{
 const {a,id}=await fixture(), other=await fixture();
 await e.DB.prepare("UPDATE challenges SET lifecycle='completed' WHERE id=?").bind(other.id).run();
 for(let n=0;n<10;n++) await e.DB.prepare("INSERT INTO challenges(id,account_id,lifecycle,data,created_at,available_at) VALUES(?,?,'skipped',?,'2026-09-10','now')").bind(crypto.randomUUID(),a,JSON.stringify({title:'Cache '+n,scenario:'Cache service',conceptIds:['caching']})).run();
 const cmd=crypto.randomUUID(); await requestInterview(e,a,id,cmd,{kind:'answer',text:'Use a queue',revision:2});
 const job=await e.DB.prepare("SELECT input FROM jobs WHERE id=?").bind(cmd).first<{input:string}>();
 const context=JSON.parse(job!.input).context;
 expect(context.promptVersion).toBe('interviewer-standard-v4');
 expect(context.historicalSnapshot.attempts).toHaveLength(8);
 expect(context.historicalSnapshot.attempts.every((x:any)=>x.status==='skipped' && x.feedback===null)).toBe(true);
 expect(JSON.stringify(context.historicalSnapshot)).not.toContain(other.id);
 expect(JSON.stringify(context.historicalSnapshot)).not.toContain(id);
});
it("atomically submits unsynced text without weakening legacy or revision checks", async () => {
 const {a,id}=await fixture(), cmd=crypto.randomUUID();
 const input={kind:"answer",text:"My latest unsynced reasoning",revision:2,saveDraft:true};
 await expect(requestInterview(e,a,id,crypto.randomUUID(),{...input,saveDraft:false})).rejects.toMatchObject({code:"revision_conflict"});
 const states=await Promise.allSettled([requestInterview(e,a,id,cmd,input),requestInterview(e,a,id,crypto.randomUUID(),input)]);
 expect(states.filter(s=>s.status==="fulfilled")).toHaveLength(1);
 const state=await interviewFor(e,a,id);
 expect(state.turns).toHaveLength(1);expect(state.turns[0].text).toBe(input.text);
 expect((await detail(e,a,id)).session).toMatchObject({answer:"",revision:3});
 await requestInterview(e,a,id,state.turns[0].id,input);
 expect((await interviewFor(e,a,id)).turns).toHaveLength(1);
});

it("drains provider tokens while a partial write is slow, with only one writer", async () => {
 const {a}=await fixture();
 const pieces=['{"move":"chat","text":"','Hello',' there',' from',' this',' streamed',' reply',' today.','"}'];
 const chunks=pieces.map(content=>'data: '+JSON.stringify({choices:[{delta:{content}}]})+'\n\n').concat('data: [DONE]\n\n');
 let reads=0, release!:()=>void, active=0, peak=0;
 const gate=new Promise<void>(resolve=>{release=resolve;});
 const mock=vi.spyOn(globalThis,"fetch").mockImplementation(async()=>new Response(new ReadableStream({pull(controller){ if(reads<chunks.length) controller.enqueue(new TextEncoder().encode(chunks[reads++])); else controller.close(); }})));
 const writes:string[]=[];
 const result=streamedInterview(e,a,await settingsFor(e,a),{},interviewSchemaFor("answer"),async text=>{ active++;peak=Math.max(peak,active); if(writes.length===0) await gate; writes.push(text);active--; });
 try {
   await vi.waitFor(()=>expect(reads).toBe(chunks.length));
 } finally { release(); }
 try { expect((await result).text).toBe("Hello there from this streamed reply today.");expect(peak).toBe(1);expect(writes.at(-1)).toBe("Hello there from this streamed reply today."); } finally {mock.mockRestore();}
});
