/** Synthetic provider timing only. Never logs credentials or practice content. */
import { z } from "../apps/api/node_modules/zod";
import { messagesFor, textDeltas, partialInterviewText } from "../apps/api/src/ai";
import { interviewSchemaFor } from "../apps/api/src/interview";
import { MODEL_ID } from "../apps/api/src/domain";
const key = process.env.OPENROUTER_API_KEY;
if (!key) throw new Error("Provider key missing");
const schema = z.toJSONSchema(interviewSchemaFor("answer"));
const context = {question:{title:"Job queue",prompt:"Design a durable job queue. Explain retries and duplicate processing."},interview:{style:"standard",turns:[]},action:{kind:"answer",text:"Workers lease jobs from a durable queue and retry failures with an idempotency key."}};
for (const duplicateSchema of [true, false, false, true]) {
  const messages = messagesFor("interview", context);
  if (duplicateSchema) messages[0].content += "\nRequired JSON schema: " + JSON.stringify(schema);
  const started = performance.now();
  const response = await fetch("https://openrouter.ai/api/v1/chat/completions", {method:"POST",headers:{Authorization:`Bearer ${key}`,"Content-Type":"application/json"},body:JSON.stringify({model:MODEL_ID,messages,provider:{sort:"latency",require_parameters:true},reasoning:{enabled:false},stream:true,max_tokens:2400,response_format:{type:"json_schema",json_schema:{name:"drillbit_output",strict:true,schema}}}),signal:AbortSignal.timeout(60000)});
  if (!response.ok || !response.body) throw new Error(`Provider status ${response.status}`);
  const headersMs = performance.now()-started;
  let raw="", firstTextMs: number | null=null;
  for await (const delta of textDeltas(response.body)) { raw+=delta; if(firstTextMs===null && partialInterviewText(raw)) firstTextMs=performance.now()-started; }
  interviewSchemaFor("answer").parse(JSON.parse(raw));
  console.log(JSON.stringify({variant:duplicateSchema?"previous-prompt":"compact-prompt",headersMs:Math.round(headersMs),firstTextMs:firstTextMs===null?null:Math.round(firstTextMs),totalMs:Math.round(performance.now()-started),valid:true}));
}
