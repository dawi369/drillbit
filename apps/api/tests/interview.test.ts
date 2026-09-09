import { env } from "cloudflare:test";
import { beforeAll, it, expect, vi } from "vitest";
import { initializeDatabase } from "./migrations";
import { accountFor, complete, detail, settingsFor } from "../src/store";
import { requestInterview, retryInterview, interviewFor } from "../src/interview";
import { runJob } from "../src/jobs";
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
function provider(result: object) { return vi.spyOn(globalThis,"fetch").mockResolvedValue(new Response(JSON.stringify({choices:[{message:{content:JSON.stringify(result)}}]}),{status:200})); }
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
  return new Response(JSON.stringify({choices:[{message:{content:JSON.stringify({outcome:"follow_up",text:"Late question"})}}]}),{status:200});
 });
 await runJob(e,cmd);mock.mockRestore();
 const d=await detail(e,a,id);expect(d.lifecycle).toBe("completed");expect(d.interview.turns[0].result).toBeNull();
 const frozen=await e.DB.prepare("SELECT data FROM completion_context WHERE challenge_id=?").bind(id).first<{data:string}>();
 expect(JSON.parse(frozen!.data).interview[0]).toMatchObject({answer:"Use a queue",kind:"answer",delivery:"unknown"});
 await expect(requestInterview(e,a,id,crypto.randomUUID(),{kind:"hint",revision:4})).rejects.toMatchObject({code:"inactive"});
});
it.each(["quick","standard","in_depth"])("retains %s style independently of engineering level",async style=>{
 const {a,id}=await fixture(style);expect((await interviewFor(e,a,id)).style).toBe(style);
});
it("Quick wraps after its focused follow-up without another provider call",async()=>{
 const {a,id}=await fixture("quick"),first=crypto.randomUUID();
 await requestInterview(e,a,id,first,{kind:"answer",text:"Use a queue",revision:2});
 let mock=provider({outcome:"follow_up",text:"What happens on redelivery?"});await runJob(e,first);mock.mockRestore();
 await e.DB.prepare("UPDATE sessions SET answer='Use a stable idempotency key',revision=4 WHERE challenge_id=?").bind(id).run();
 const second=crypto.randomUUID();await requestInterview(e,a,id,second,{promptId:first,kind:"answer",text:"Use a stable idempotency key",revision:4});
 mock=provider({outcome:"follow_up",text:"Must not be called"});await runJob(e,second);expect(mock).not.toHaveBeenCalled();mock.mockRestore();
 expect((await interviewFor(e,a,id)).wrapUp).toBe(true);
});
