/** Synthetic inputs only. Product acceptance requires reading these responses. */
import {mkdirSync,writeFileSync} from 'node:fs';
import {z} from '../apps/api/node_modules/zod';
import {messagesFor,interviewModelSchema,interviewReasoning,parseInterviewModelResult} from '../apps/api/src/ai';
import {interviewSchemaFor} from '../apps/api/src/interview';
import {voiceDelegationMessages} from '../apps/api/src/prompts/voice-context';
import {INTERVIEW_PROMPT_VERSION} from '../apps/api/src/prompts/interviewer';
import {MODEL_ID} from '../apps/api/src/domain';
const key=process.env.OPENROUTER_API_KEY;
if(!key) throw new Error('OpenRouter key missing');
const baseQuestion={title:'API Design for Order Status Updates',prompt:'Design an internal API endpoint that allows a mobile client to poll for order status as it moves through logistics stages. Define the request path, response structure, and how to minimize unnecessary data transfer and server load.',constraints:['Support checks as often as every 5 seconds.'],engineeringLevel:'junior'};
const cases=[
 {name:'approach',texts:["I'm not sure how to approach questions like this. Can you show me how to start?",'Okay, the client needs status and when it changed. Should I start picking databases now?']},
 {name:'scale',texts:['Maybe ten thousand concurrent users, polling every five seconds. So ten thousand requests per second.']},
 {name:'premature-complexity',texts:['I will start with Kafka and six microservices, then choose the API later.']},
 {name:'direct-help',texts:['What request path and response would you suggest? I want to understand the reasoning.']},
 {name:'valid-alternative',texts:['I will use GET /orders/{id}/status with a small JSON body. The entire response is 80 bytes. At our low scale I would keep it simple instead of implementing ETags yet.']},
 {name:'banter',texts:['My API runs on vibes and one overworked hamster','haha okay, no hamster slander','I am a bit nervous. Can we make this easier?']},
 {name:'holdout-response',texts:['GET /orders/{id}/status returns an 80-byte JSON RESPONSE containing status and updatedAt. There is no request body. At low scale I would skip ETags for now.']},
 {name:'holdout-retries',question:{title:'Reliable payment retries',prompt:'Design retries for a payment API when acknowledgements can be lost. Avoid duplicate charges.',constraints:['An external payment provider accepts idempotency keys.'],engineeringLevel:'mid'},texts:['Retries guarantee exactly once because eventually they succeed.','Can you show a concrete way to make this safe?']},
 {name:'holdout-cache',question:{title:'Configuration during outages',prompt:'Design local configuration reads when a configuration server is temporarily unavailable.',constraints:['Prefer the last known configuration during an outage.'],engineeringLevel:'junior'},texts:['A local cache guarantees the service will always work, even on its first startup.']},
 {name:'waiting',texts:['Are you still checking? You said a few more seconds, but I have been waiting a while.']},
];
const results:any[]=[];
await Promise.all(['learn_together','coach_me','mock_interview'].map(async guidanceMode=>{
 for(const sample of cases){
  if(process.env.EVAL_CASE && !sample.name.includes(process.env.EVAL_CASE))continue;
  const question=sample.question ?? baseQuestion;
  const turns:any[]=[];
  for(const text of sample.texts){
   let textReply = "";
   for(const transport of ['text','voice']) {
    const interview={guidanceMode,turns};
    const context={question,interview,historicalSnapshot:{scope:'synthetic empty history',attempts:[]},action:{kind:'answer',text}};
    const messages=transport==='voice'?voiceDelegationMessages(question,context.historicalSnapshot,{...interview,turns:[...turns,{kind:'voice',voice:[{speaker:'user',text}]}]}):messagesFor('interview',context);
    const start=performance.now();
    const response=await fetch('https://openrouter.ai/api/v1/chat/completions',{method:'POST',headers:{Authorization:`Bearer ${key}`,'Content-Type':'application/json'},signal:AbortSignal.timeout(60000),body:JSON.stringify({model:MODEL_ID,provider:{sort:'latency',require_parameters:true},messages,reasoning:process.env.EVAL_REASONING ? {effort:process.env.EVAL_REASONING} : interviewReasoning(context),max_tokens:process.env.EVAL_REASONING ? 4096 : 2400,...({response_format:{type:'json_schema',json_schema:{name:'reply',strict:true,schema:z.toJSONSchema(interviewModelSchema(context,interviewSchemaFor('answer')))}}})})});
    if(!response.ok)throw new Error(`Provider status ${response.status}`);
    const body=await response.json() as any;
    const raw=body.choices[0].message.content;
    const reply=parseInterviewModelResult(context,interviewSchemaFor('answer'),JSON.parse(raw)).text;
    const row={version:INTERVIEW_PROMPT_VERSION,model:MODEL_ID,guidanceMode,transport,case:sample.name,user:text,reply,ms:Math.round(performance.now()-start),inputTokens:body.usage?.prompt_tokens,cost:body.usage?.cost,reasoningTokens:body.usage?.completion_tokens_details?.reasoning_tokens,finishReason:body.choices[0].finish_reason};
    results.push(row);console.log(JSON.stringify(row));
    // Advance the common scenario with the text response; paired voice tests see
    // the same prior reasoning. This is not a live audio transport test.
    if(transport==='text') textReply = reply;
    else turns.push({kind:'answer',text,result:{text:textReply,outcome:'follow_up'}});
   }
  }
 }
}));
mkdirSync('.local',{recursive:true});writeFileSync('.local/teaching-evaluation.json',JSON.stringify(results,null,2));
