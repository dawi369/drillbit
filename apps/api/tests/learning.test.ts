import { env } from "cloudflare:test";
import { beforeAll, expect, it } from "vitest";
import { initializeDatabase } from "./migrations";
import { accountFor } from "../src/store";
import { groundReflection, learningEvidence } from "../src/learning";
import { exportPage } from "../src/export";
import { selectConcept } from "../src/library";
import type { Env } from "../src/platform";
const bindings = {...env,JOBS:{create:async()=>({id:"test"})}} as unknown as Env;
beforeAll(()=>initializeDatabase(bindings.DB));
const feedback = {summary:"A concrete retry design.",worked:["Stable keys"],improve:"Bound retention.",takeaway:"State a retention window.",strengths:[],gaps:[],nextExercise:"Choose and justify a retention window for retry keys.",evidence:[{conceptId:"retry-safety",quote:"Use a stable idempotency key",observation:"Identifies duplicate requests.",signal:"demonstrated",assistance:"unknown"}]};
it("grounds quotes in candidate work and never upgrades unknown exposure to independent",()=>{
  const context={question:{conceptIds:["retry-safety"]},session:{answer:"Use a stable idempotency key for each payment."},help:[{body:"Choose a stable key."}]};
  expect(groundReflection(feedback,context).evidence?.[0].assistance).toBe("assisted");
  expect(groundReflection({...feedback,improve:"",gaps:[]},{...context,help:[]}).improve).toBe("");
  expect(groundReflection(feedback,{...context,help:[]}).evidence?.[0].assistance).toBe("unknown");
  const social=groundReflection(feedback,{...context,session:{answer:"Hi!"}});
  expect(social.evidence).toEqual([]);expect(social.gaps).toEqual([]);expect(social.worked).toEqual([]);
  expect(groundReflection(feedback,{...context,question:{conceptIds:["queues"]}}).evidence).toEqual([]);
  expect(groundReflection(feedback,{...context,session:{answer:""},interview:[{kind:"hint",answer:"Use a stable idempotency key"}]}).evidence).toEqual([]);
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
