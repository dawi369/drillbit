/** Synthetic live acceptance; credentials are read from the environment, never printed. */
import { mkdirSync, writeFileSync } from "node:fs";
import { z } from "../apps/api/node_modules/zod";
import { messagesFor, interviewModelSchema, parseInterviewModelResult } from "../apps/api/src/ai";
import { interviewResultSchema, interviewSchemaFor, normalizeInterviewResult, interviewWrapUp } from "../apps/api/src/interview";
import { MODEL_ID } from "../apps/api/src/domain";
if (!process.env.OPENROUTER_API_KEY) throw new Error("Provider key missing");
const question = {title:"Notification delivery",prompt:"Design a notification service. Explain retries and duplicate delivery, with an external email provider that supports idempotency keys.",engineeringLevel:"senior"};
const first = "Accept notifications through an API, enqueue them durably, and use workers to send emails. Retry failures with exponential backoff.";
const follow = "What if a worker crashes after the provider accepts the email but before it acknowledges the queue message?";
const turns = [{kind:"answer",prompt:question.prompt,text:first,result:{outcome:"follow_up",text:follow}},{kind:"answer",prompt:follow,text:"Use the notification ID as the provider idempotency key. Redelivery uses the same key. Track attempts and send exhausted retries to a dead-letter queue. Idempotency retention must cover our retry window.",result:{outcome:"follow_up",text:"What happens when retries outlive the provider's deduplication window?"}}];
const cases = [
 ...["quick","standard","in_depth"].map(style=>({name:style,context:{question,interview:{style,prompt:question.prompt,turns:[]},action:{kind:"answer",text:first}}})),
 {name:"clarification",context:{question,interview:{style:"standard",prompt:question.prompt,turns:[]},action:{kind:"clarification",text:"May I assume the provider accepts idempotency keys?"}}},
 {name:"nudge",context:{question,interview:{style:"standard",prompt:follow,turns:turns.slice(0,1)},action:{kind:"hint",text:""}}},
 {name:"wrap_up",context:{question,interview:{style:"quick",prompt:turns[1].result.text,turns},action:{kind:"answer",text:"Bound automatic retries to the provider retention window. Beyond it, mark delivery uncertain for explicit investigation rather than blindly resending and risking a duplicate."}}},
];
const results=[];
for (const sample of cases) {
 const wrap = interviewWrapUp(sample.context, sample.context.action.kind);
 if (wrap) { results.push({name:sample.name,output:wrap}); console.log(sample.name+": "+JSON.stringify(wrap)); continue; }
 const response=await fetch("https://openrouter.ai/api/v1/chat/completions",{method:"POST",headers:{Authorization:`Bearer ${process.env.OPENROUTER_API_KEY}`,"Content-Type":"application/json"},body:JSON.stringify({model:MODEL_ID,messages:messagesFor("interview",sample.context),response_format:{type:"json_schema",json_schema:{name:"interview",strict:true,schema:z.toJSONSchema(interviewModelSchema(sample.context, interviewSchemaFor(sample.context.action.kind)))}}}),signal:AbortSignal.timeout(60000)});
 if(!response.ok) throw new Error(`Provider status ${response.status}`);
 const envelope=await response.json() as any;
 const output=parseInterviewModelResult(sample.context, interviewSchemaFor(sample.context.action.kind), JSON.parse(envelope.choices[0].message.content));
 results.push({name:sample.name,output});
 console.log(sample.name+": "+JSON.stringify(output));
}
mkdirSync(".local",{recursive:true});writeFileSync(".local/interview-model.json",JSON.stringify(results,null,2));
