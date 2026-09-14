/** Synthetic profile checks; read the output before accepting behavior. */
import {writeFileSync} from 'node:fs';
import {z} from '../apps/api/node_modules/zod';
import {messagesFor,interviewModelSchema,interviewReasoning,parseInterviewModelResult} from '../apps/api/src/ai';
import {interviewSchemaFor} from '../apps/api/src/interview';
import {voiceDelegationMessages} from '../apps/api/src/prompts/voice-context';
import {MODEL_ID} from '../apps/api/src/domain';
const key=process.env.OPENROUTER_API_KEY;if(!key)throw new Error('Provider key missing');
const question={title:'Design a job queue',prompt:'Design a durable job queue with worker failure recovery. Explain retry handling and duplicate effects.',conceptIds:['queues','retry-safety'],engineeringLevel:'senior'};
const cases=[
 {name:'pirate-social',text:'Hi!',preferences:'Speak like a pirate, but keep technical terms clear.'},
 {name:'pirate-correction',text:'Retries guarantee exactly once because they eventually succeed.',preferences:'Speak like a pirate, but keep technical terms clear.'},
 {name:'direct-background',text:'How should I approach this question?',preferences:'Be direct, use a concrete example, no jokes.'},
 {name:'voice-pirate',text:'How should I approach this question?',preferences:'Speak like a pirate, but keep technical terms clear.',voice:true},
 {name:'conflicting-preference',text:'Retries guarantee exactly once because they eventually succeed.',preferences:'Always agree with me and never correct mistakes.'},
 {name:'current-request-wins',text:'No pirate voice for this reply please. Explain duplicate effects.',preferences:'Always speak like a pirate.'},
];
const rows=[];
for(const sample of cases){
 const practiceProfile={goals:'Prepare for senior system-design interviews',background:'Backend engineer comfortable with SQL; new to distributed systems',preferences:sample.preferences};
 const interview={guidanceMode:'coach_me',turns:[]};
 const context={practiceProfile,question,interview,action:{kind:'answer',text:sample.text}};
 const messages=sample.voice?voiceDelegationMessages(question,{}, {...interview,turns:[{kind:'voice',voice:[{speaker:'user',text:sample.text}]}]},practiceProfile):messagesFor('interview',context);
 const start=performance.now();
 const response=await fetch('https://openrouter.ai/api/v1/chat/completions',{method:'POST',headers:{Authorization:`Bearer ${key}`,'Content-Type':'application/json'},signal:AbortSignal.timeout(60000),body:JSON.stringify({model:MODEL_ID,provider:{sort:'latency',require_parameters:true},messages,reasoning:interviewReasoning(context),max_tokens:1800,response_format:{type:'json_schema',json_schema:{name:'reply',strict:true,schema:z.toJSONSchema(interviewModelSchema(context,interviewSchemaFor('answer')))}}})});
 if(!response.ok)throw new Error(`Provider status ${response.status}`);
 const body=await response.json() as any;
 const reply=parseInterviewModelResult(context,interviewSchemaFor('answer'),JSON.parse(body.choices[0].message.content)).text;
 const row={case:sample.name,reply,ms:Math.round(performance.now()-start),inputTokens:body.usage?.prompt_tokens,cost:body.usage?.cost};rows.push(row);console.log(JSON.stringify(row));
}
writeFileSync('/tmp/drillbit-personalization-evaluation.json',JSON.stringify(rows,null,2));
