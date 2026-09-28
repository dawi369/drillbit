import { env } from "cloudflare:test";
import { beforeAll, expect, it } from "vitest";
import recallFixture from "../../../packages/contracts/fixtures/recall.json";
import tomorrowFixture from "../../../packages/contracts/fixtures/tomorrow.json";
import { wire } from "../../../packages/contracts/wire";
import { normalizeSettings } from "../src/domain";
import { exportPage } from "../src/export";
import { candidateWords, groundReflection, learningEvidence, recallDeck, retryMoment, reviewRecall, todayPlan } from "../src/learning";
import { selectConcept } from "../src/library";
import type { Env } from "../src/platform";
import { accountFor } from "../src/store";
import { initializeDatabase } from "./migrations";
const bindings = {...env,JOBS:{create:async()=>({id:"test"})}} as unknown as Env;
beforeAll(()=>initializeDatabase(bindings.DB));
const feedback = {summary:"A concrete retry design.",worked:["Stable keys"],improve:"Bound retention.",takeaway:"State a retention window.",strengths:[],gaps:[],nextExercise:"Choose and justify a retention window for retry keys.",evidence:[{conceptId:"retry-safety",quote:"Use a stable idempotency key",observation:"Identifies duplicate requests.",signal:"demonstrated",assistance:"unknown"}]};
it("keeps the recall fixture compatible with the public wire contract",()=>{
 expect(wire.RecallDeck.safeParse(recallFixture).success).toBe(true);
 expect(wire.QueuedNextResult.safeParse(tomorrowFixture).success).toBe(true);
});
it("grounds a quote in the candidate's own characters despite curly quotes or a changed final stop",()=>{
 const text="I'd send an idempotency key with every delivery so the receiver can drop repeats";
 expect(candidateWords("I’d send an idempotency key with every delivery so the receiver can drop repeats.",text)).toBe(text);
 expect(candidateWords("an idempotency key",text)).toBe("an idempotency key");
 expect(candidateWords("I’d send a request ID",text)).toBeUndefined();
 const reflection=groundReflection({...feedback,evidence:[{...feedback.evidence[0],quote:"Use a stable idempotency key.",recall:{prompt:"A retry arrives after a timeout. What stops a second charge?",answer:"The same key finds the first result."}}]},
  {question:{conceptIds:["retry-safety"]},interview:[{id:"turn",kind:"answer",answer:"Use a stable idempotency key for every payment"}]});
 expect(reflection.evidence?.[0]).toMatchObject({quote:"Use a stable idempotency key",sourceTurnId:"turn",recall:{prompt:"A retry arrives after a timeout. What stops a second charge?"}});
});
it("grounds quotes in candidate work and never upgrades unknown exposure to independent",()=>{
  const context={question:{conceptIds:["retry-safety"]},session:{answer:"Use a stable idempotency key for each payment."},help:[{body:"Choose a stable key."}]};
  expect(groundReflection(feedback,context).evidence?.[0].assistance).toBe("assisted");
  expect(groundReflection({...feedback,improve:"",gaps:[]},{...context,help:[]}).improve).toBe("");
  expect(groundReflection(feedback,{...context,help:[]}).evidence?.[0].assistance).toBe("unknown");
  const social=groundReflection(feedback,{...context,session:{answer:"Hi!"}});
  expect(social.evidence).toEqual([]);expect(social.gaps).toEqual([]);expect(social.worked).toEqual([]);
  expect(groundReflection(feedback,{...context,question:{conceptIds:["queues"]}}).evidence).toEqual([]);
  expect(groundReflection(feedback,{...context,session:{answer:""},interview:[{kind:"hint",answer:"Use a stable idempotency key"}]}).evidence).toEqual([]);
  const turnGrounded = groundReflection(feedback,{question:{conceptIds:["retry-safety"]},interview:[{id:"learner-turn",kind:"answer",prompt:"How will retries stay safe?",text:"Use a stable idempotency key for each payment."}]});
  expect(turnGrounded.evidence?.[0].sourceTurnId).toBe("learner-turn");
});

it("derives the shared daily plan in deterministic priority order", async()=>{
 const account=(await accountFor(bindings,crypto.randomUUID())).id;
 await bindings.DB.prepare("UPDATE accounts SET status='active' WHERE id=?").bind(account).run();
 const settings=normalizeSettings({timezone:"UTC",learningPlan:{version:1,objective:"learn",roleTrack:"general",weakAreas:[],dailyGoalMinutes:5}});
 expect((await todayPlan(bindings,account,null,settings)).state).toBe("prepare");
 const id=crypto.randomUUID(),now=new Date().toISOString();
 await bindings.DB.prepare("INSERT INTO challenges(id,account_id,lifecycle,data,created_at,available_at) VALUES(?,?,'ready',?,?,?)")
  .bind(id,account,JSON.stringify({title:"First",prompt:"Design a sufficiently complete service boundary.",topic:"System design"}),now,now).run();
 const ready=await bindings.DB.prepare("SELECT * FROM challenges WHERE id=?").bind(id).first<any>();
 expect((await todayPlan(bindings,account,ready,settings)).state).toBe("first_session");
});
async function seed(count:number) {
 const account=(await accountFor(bindings,crypto.randomUUID())).id;
 await env.DB.prepare("UPDATE accounts SET status='active' WHERE id=?").bind(account).run();
 const ids:string[]=[];
 for(let i=0;i<count;i++) {
  const id=crypto.randomUUID(),at=new Date(Date.UTC(2026,0,1,0,i)).toISOString();ids.push(id);
  const q=JSON.stringify({title:"Payment service",prompt:"Design safe retries.",topic:"System design",constraints:[],engineeringLevel:"senior",conceptIds:["retry-safety"],primaryConceptId:"retry-safety",evaluationCriteria:["PRIVATE"]});
  await env.DB.batch([
   env.DB.prepare("INSERT INTO challenges(id,account_id,lifecycle,data,created_at,available_at,completed_at) VALUES(?,?,'completed',?,?,?,?)").bind(id,account,q,at,at,at),
   env.DB.prepare("INSERT INTO sessions(challenge_id,answer,updated_at) VALUES(?,'Use a stable idempotency key',?)").bind(id,at),
   env.DB.prepare("INSERT INTO reflections(challenge_id,data,created_at) VALUES(?,?,?)").bind(id,JSON.stringify(feedback),at),
  ]);
 }
 return {account,ids};
}
it("exports every page without crossing account boundaries or leaking evaluator data",async()=>{
 const a=await seed(12),b=await seed(1);
 const first=await exportPage(bindings,a.account);
 expect(first.sessions).toHaveLength(10);expect(first.nextCursor).toBeTruthy();
 const last=await exportPage(bindings,a.account,first.nextCursor!);
 expect(last.sessions).toHaveLength(2);expect(last.nextCursor).toBeNull();
 expect(JSON.stringify(first)).not.toContain("PRIVATE");
 const all=[...first.sessions,...last.sessions].map(s=>s.id);
 expect(new Set(all).size).toBe(12);expect(all).not.toContain(b.ids[0]);
 expect(await learningEvidence(bindings,b.account)).toHaveLength(1);
 await expect(exportPage(bindings,a.account,"bad-cursor")).rejects.toMatchObject({code:"invalid_cursor"});
});
it("deleting a session removes its learning evidence and explicit focus wins",async()=>{
 const a=await seed(1);
 expect(await learningEvidence(bindings,a.account)).toHaveLength(1);
 expect((await selectConcept(bindings,a.account,"senior","queues")).primaryConceptId).toBe("queues");
 await env.DB.prepare("DELETE FROM challenges WHERE account_id=?").bind(a.account).run();
 expect(await learningEvidence(bindings,a.account)).toEqual([]);
});
it("exports pool eligibility even when a question has no remaining attempt",async()=>{
 const {account}=await seed(0);
 const id=crypto.randomUUID(),at="2026-01-01T00:00:00Z";
 await env.DB.prepare("INSERT INTO questions(id,account_id,data,created_at,eligibility_updated_at,eligible) VALUES(?,?,?,?,?,1)")
  .bind(id,account,JSON.stringify({title:"Retry",prompt:"Design retries",scenario:"Payment service",engineeringLevel:"senior",primaryConceptId:"retry-safety",conceptIds:["retry-safety"],evaluationCriteria:["PRIVATE"]}),at,at).run();
 const page=await exportPage(bindings,account);
 expect(page.sessions).toEqual([]);expect(page.questions[0]).toMatchObject({id,eligible:true});
 expect(JSON.stringify(page.questions)).not.toContain("PRIVATE");expect(page.nextCursor).toBeNull();
});

it("schedules recall deterministically and keeps reviews account scoped",async()=>{
 const a=await seed(1),b=await seed(0),card=crypto.randomUUID(),now="2026-01-02T00:00:00Z";
 await env.DB.prepare("INSERT INTO recall_cards(id,account_id,source_challenge_id,concept_id,question,answer,due_at,created_at,updated_at) VALUES(?,?,?,?,?,?,?,?,?)")
  .bind(card,a.account,a.ids[0],"retry-safety","How do retries stay safe?","Use a stable key.",now,now,now).run();
 expect((await recallDeck(bindings,a.account)).dueCount).toBe(1);
 await expect(reviewRecall(bindings,b.account,card,crypto.randomUUID(),{rating:"got_it"})).rejects.toMatchObject({code:"not_found"});
 const command=crypto.randomUUID();
 const first=await reviewRecall(bindings,a.account,card,command,{rating:"got_it",responseMs:1200});
 expect(first.card).toMatchObject({repetitions:1,intervalDays:1});
 const replay=await reviewRecall(bindings,a.account,card,command,{rating:"got_it"});
 expect(replay.card.repetitions).toBe(1);
 await expect(reviewRecall(bindings,a.account,card,command,{rating:"again"})).rejects.toMatchObject({code:"command_reused"});
 const again=await reviewRecall(bindings,a.account,card,crypto.randomUUID(),{rating:"again"});
 expect(again.card).toMatchObject({repetitions:0,intervalDays:0,lapses:1});
});

it("branches a completed interview moment without changing the source",async()=>{
 const a=await seed(1),source=a.ids[0],turn=crypto.randomUUID(),job=turn,at="2026-01-03T00:00:00Z";
 await env.DB.batch([
  env.DB.prepare("INSERT INTO jobs(id,account_id,challenge_id,kind,status,input,created_at,updated_at) VALUES(?,?,?,'interview','completed','{}',?,?)").bind(job,a.account,source,at,at),
  env.DB.prepare("INSERT INTO interview_turns(id,challenge_id,ordinal,kind,prompt,text,job_id,created_at) VALUES(?,?,0,'answer',?,'An answer',?,?)").bind(turn,source,"How would you make retries safe?",job,at),
 ]);
 const command=crypto.randomUUID();
 const branch=await retryMoment(bindings,a.account,source,turn,command);
 expect(branch).toMatchObject({id:command,lifecycle:"in_progress",prompt:"How would you make retries safe?"});
 expect((await retryMoment(bindings,a.account,source,turn,command)).id).toBe(command);
 expect((await env.DB.prepare("SELECT lifecycle FROM challenges WHERE id=?").bind(source).first<{lifecycle:string}>())?.lifecycle).toBe("completed");
});

it("keeps the canonical learning loop coherent across teaching modes and levels",()=>{
 for (const mode of ["learn_together","coach_me","mock_interview"]) for (const level of ["junior","mid","senior"]) {
  const quote=`At ${level} scope, use a stable idempotency key before retrying the job.`;
  const reflection=groundReflection({...feedback,quote:undefined,evidence:[{...feedback.evidence[0],quote}],nextExercise:"Explain acknowledgement loss using the same retry key."},{
   question:{primaryConceptId:"retry-safety",conceptIds:["queues","retry-safety"]},
   interview:{guidanceMode:mode,turns:[{id:`${mode}-${level}`,kind:"answer",prompt:"How will retries stay safe?",text:quote}]},
  });
  expect(reflection.evidence).toHaveLength(1);
  expect(reflection.evidence?.[0]).toMatchObject({conceptId:"retry-safety",quote,sourceTurnId:`${mode}-${level}`});
  expect(reflection.nextExercise).toContain("retry key");
 }
});
