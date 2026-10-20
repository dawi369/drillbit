/** Whole synthetic interviews, mode by mode: scripted candidates, real follow-ups, then the feedback stage.
 * Synthetic inputs only; full transcripts go to .local/. Product acceptance means reading them. */
import {mkdirSync,writeFileSync} from 'node:fs';
import {z} from '../apps/api/node_modules/zod';
import {messagesFor,interviewModelSchema,interviewReasoning,parseInterviewModelResult} from '../apps/api/src/ai';
import {interviewSchemaFor} from '../apps/api/src/interview';
import {FAST_PROVIDERS,managedModel,reflectionOutputFor} from '../apps/api/src/domain';
import {INTERVIEW_PROMPT_VERSION} from '../apps/api/src/prompts/interviewer';
import {groundReflection} from '../apps/api/src/learning';
const key=process.env.OPENROUTER_API_KEY;
if(!key) throw new Error('OpenRouter key missing');
const INTERVIEW_MODEL=managedModel('interview'), FEEDBACK_MODEL=managedModel('summarize');
const question={title:'Rate limiting for a public API',prompt:'Design rate limiting for a public API used by third-party developers. Explain where limits are enforced, how a client learns it is limited, and what happens during a traffic spike.',constraints:['Limits are per API key.','Several API servers sit behind one load balancer.'],engineeringLevel:'mid',conceptIds:['rate-limiting','caching','fault-tolerance','api-design'],opener:'Let’s start simple: where would you put the limit, and why there?'};
/** Four kinds of people: a solid mid-level, a hand-wavy beginner, a nervous one who asks for help, and one who disagrees. */
const candidates:{name:string;turns:{kind:string;text:string}[]}[]=[
 {name:'solid',turns:[
  {kind:'answer',text:'I’d enforce at the API gateway, in front of the servers, so every server sees the same decision. Token bucket per API key, say 100 requests per second with a burst of 200, stored in Redis so all gateway instances share counts.'},
  {kind:'answer',text:'When they’re limited they get a 429 with Retry-After and X-RateLimit-Remaining headers so SDKs can back off instead of hammering. The bucket refills continuously, so a short wait usually clears it.'},
  {kind:'answer',text:'In a spike, Redis becomes the hot path. I’d keep the check to one atomic Lua script per request, and if Redis is unreachable I’d fail open briefly with a local per-instance cap, logging it, rather than take the whole API down.'},
  {kind:'answer',text:'One more thing: separate buckets per endpoint class, so a flood of cheap reads doesn’t block a client’s occasional expensive write.'},
 ]},
 {name:'beginner',turns:[
  {kind:'answer',text:'I would just count requests in the server and block when it is too many.'},
  {kind:'answer',text:'Maybe in a variable, like a map from the key to a number. Reset it every minute.'},
  {kind:'hint',text:''},
  {kind:'answer',text:'Oh, because there are several servers each one has its own count. So I need something shared, like a database or Redis.'},
  {kind:'answer',text:'For the spike I think the servers would just get slow. I am not sure what else to do.'},
 ]},
 {name:'nervous',turns:[
  {kind:'clarification',text:'Sorry, before I start, do the limits need to be exact or is roughly right okay?'},
  {kind:'answer',text:'Okay. I think a sliding window per key would be fairer than fixed windows, enforced at the load balancer or gateway. I’m a bit nervous, is this the right direction?'},
  {kind:'answer',text:'Right, so the sliding window in Redis with a sorted set of timestamps per key, trimmed on each request. Clients get a 429 and a header saying when to retry.'},
  {kind:'example',text:''},
  {kind:'answer',text:'Got it. For spikes I’d shed load early at the edge and protect the shared store with a short local cache of recent decisions.'},
 ]},
 {name:'pushback',turns:[
  {kind:'answer',text:'Honestly rate limiting per key is the wrong model. I’d do it per user behind the key, because one key can serve thousands of end users and you’d punish all of them.'},
  {kind:'answer',text:'Fine, if the constraint is per key, then a fixed window counter in Redis is enough. Sliding windows are over-engineering here; nobody notices the boundary burst.'},
  {kind:'answer',text:'On a spike I’d rather queue requests briefly than reject them. A 429 is a bad developer experience.'},
  {kind:'answer',text:'Okay, you’ve half convinced me: queueing hides the problem and ties up gateway memory. Reject fast with Retry-After, and let the SDK queue on the client side.'},
 ]},
];
async function call(model:string,messages:unknown,schema:z.ZodType,reasoning:unknown,maxTokens:number){
 const response=await fetch('https://openrouter.ai/api/v1/chat/completions',{method:'POST',headers:{Authorization:`Bearer ${key}`,'Content-Type':'application/json'},signal:AbortSignal.timeout(90000),body:JSON.stringify({model,provider:{order:FAST_PROVIDERS,require_parameters:true},messages,reasoning,max_tokens:maxTokens,response_format:{type:'json_schema',json_schema:{name:'reply',strict:true,schema:z.toJSONSchema(schema)}}})});
 if(!response.ok) throw new Error(`Provider status ${response.status}: ${(await response.text()).slice(0,200)}`);
 const body=await response.json() as any;
 return {raw:body.choices[0].message.content as string,usage:body.usage,finish:body.choices[0].finish_reason};
}
const transcripts:any[]=[];
const modes=(process.env.EVAL_MODES ?? 'learn_together,coach_me,mock_interview').split(',');
await Promise.all(modes.map(async guidanceMode=>{
 for(const candidate of candidates){
  if(process.env.EVAL_CANDIDATE && candidate.name!==process.env.EVAL_CANDIDATE) continue;
  const turns:any[]=[]; const log:any[]=[]; let cost=0; let prompt=question.prompt;
  for(const step of candidate.turns){
   const interview={guidanceMode,style:'standard',prompt,turns};
   const context={question,interview,historicalSnapshot:{scope:'synthetic empty history',attempts:[]},action:{kind:step.kind,text:step.text}};
   const started=performance.now();
   let outcome:any;
   try{
    const schema=interviewModelSchema(context,interviewSchemaFor(step.kind));
    const {raw,usage,finish}=await call(INTERVIEW_MODEL,messagesFor('interview',context),schema,interviewReasoning(context),2400);
    cost+=usage?.cost??0;
    outcome=parseInterviewModelResult(context,interviewSchemaFor(step.kind),JSON.parse(raw));
    log.push({you:`${step.kind}: ${step.text}`,interviewer:outcome.text,outcome:outcome.outcome,ms:Math.round(performance.now()-started),finish});
   }catch(error){ log.push({you:`${step.kind}: ${step.text}`,invalid:String(error).slice(0,200)}); continue; }
   turns.push({kind:step.kind,prompt,text:step.text,result:outcome});
   // Follow-ups move the question on; replies, nudges and examples leave it where it was.
   if(['answer','continue'].includes(step.kind) && outcome.outcome==='follow_up') prompt=outcome.text;
  }
  let reflection:any=null;
  try{
   const context={question,interview:{guidanceMode,style:'standard',prompt:question.prompt,turns},historicalSnapshot:{scope:'synthetic empty history',attempts:[]},guidanceMode,createdAt:new Date(Date.now()-15*60_000).toISOString(),completedAt:new Date().toISOString()};
   const schema=reflectionOutputFor(guidanceMode);
   const {raw,usage}=await call(FEEDBACK_MODEL,messagesFor('summarize',context),schema,{effort:'low'},4000);
   cost+=usage?.cost??0;
   // The same grounding production applies: quotes must exist, concepts must be the question's, assistance follows the hint record.
   reflection=groundReflection(schema.parse(JSON.parse(raw)),context);
  }catch(error){ reflection={invalid:String(error).slice(0,300)}; }
  const row={version:INTERVIEW_PROMPT_VERSION,interviewModel:INTERVIEW_MODEL,feedbackModel:FEEDBACK_MODEL,guidanceMode,candidate:candidate.name,cost:Number(cost.toFixed(5)),turns:log,reflection};
  transcripts.push(row);
  console.log(`\n=== ${guidanceMode} · ${candidate.name} · $${row.cost}`);
  for(const t of log){ console.log(`YOU  > ${t.you}`); console.log(t.invalid?`!!   > ${t.invalid}`:`INT  > [${t.outcome}] ${t.interviewer}`); }
  console.log('FEEDBACK >', JSON.stringify(reflection));
 }
}));
mkdirSync('.local',{recursive:true});
writeFileSync('.local/flow-evaluation.json',JSON.stringify(transcripts,null,2));
console.log(`\nSaved ${transcripts.length} transcripts to .local/flow-evaluation.json`);
