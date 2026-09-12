/** Synthetic evidence evaluation; never reads private practice records. */
import { messagesFor } from "../apps/api/src/ai";
import { reflectionOutputSchema, MODEL_ID } from "../apps/api/src/domain";
import { groundReflection } from "../apps/api/src/learning";
import { z } from "../apps/api/node_modules/zod";
const key=process.env.OPENROUTER_API_KEY;
if(!key) throw Error("OPENROUTER_API_KEY required");
const samples=[
 {name:"grounded",answer:"Use a stable idempotency key for each request. Commit its result with the payment in one database transaction. Keep keys for 24 hours; reject later retries.",help:[]},
 {name:"assisted",answer:"Use a stable idempotency key for each request.",help:[{body:"Store the key and result atomically with the payment."}]},
 {name:"social-only",answer:"Hey! Nice to meet you, this is just practice.",help:[]},
 {name:"false-guarantee",answer:"Retry every failed response immediately forever. That guarantees a single payment without duplicates.",help:[]}
];
for(const sample of samples){
 const context={question:{title:"Payment retries",prompt:"Design payment retries without duplicate charges. State how long retry keys are retained and what happens after that window.",conceptIds:["retry-safety"],constraints:[]},session:{answer:sample.answer},help:sample.help};
 const response=await fetch("https://openrouter.ai/api/v1/chat/completions",{method:"POST",headers:{Authorization:`Bearer ${key}`,"Content-Type":"application/json"},body:JSON.stringify({model:MODEL_ID,provider:{sort:"latency",require_parameters:true},reasoning:{effort:"low"},messages:messagesFor("summarize",context),max_tokens:2400,response_format:{type:"json_schema",json_schema:{name:"feedback",strict:true,schema:z.toJSONSchema(reflectionOutputSchema)}}}),signal:AbortSignal.timeout(60000)});
 if(!response.ok)throw Error(`Provider ${response.status}`);
 const envelope:any=await response.json();
 const result=groundReflection(JSON.parse(envelope.choices[0].message.content),context);
 console.log(JSON.stringify({case:sample.name,result,cost:envelope.usage?.cost}));
 if(sample.name==="social-only" && result.evidence?.length)throw Error("Social content became technical evidence");
}
