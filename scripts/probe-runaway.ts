/** Probes one provider for runaway output on a mock-interview turn. Synthetic input only. */
import { z } from "../apps/api/node_modules/zod";
import { messagesFor, interviewModelSchema } from "../apps/api/src/ai";
import { interviewSchemaFor } from "../apps/api/src/interview";
import { managedModel } from "../apps/api/src/domain";
import { pooled } from "./openrouter";

const key = process.env.OPENROUTER_API_KEY;
const provider = process.env.EVAL_PROVIDERS ?? "together";
const context = { question: { title: "API Design for Order Status Updates", prompt: "Design an internal API endpoint that allows a mobile client to poll for order status as it moves through logistics stages.", engineeringLevel: "junior" }, interview: { guidanceMode: "mock_interview", turns: [] }, historicalSnapshot: { attempts: [] }, action: { kind: "answer", text: "I will start with Kafka and six microservices, then choose the API later." } };
const runs = await pooled(Array.from({ length: Number(process.env.EVAL_ROUNDS ?? 20) }, (_, i) => i), Number(process.env.EVAL_CONCURRENCY ?? 2), async () => {
  const started = performance.now();
  const messages = messagesFor("interview", context);
  if (process.env.EVAL_COMPACT) messages[0].content += "\n" + process.env.EVAL_COMPACT;
  const response = await fetch("https://openrouter.ai/api/v1/chat/completions", {
    method: "POST", headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
    body: JSON.stringify({ model: managedModel("interview"), messages, provider: { only: provider.split(","), allow_fallbacks: false, require_parameters: true }, reasoning: { enabled: false }, max_tokens: 900,
      response_format: { type: "json_schema", json_schema: { name: "drillbit_output", strict: true, schema: z.toJSONSchema(interviewModelSchema(context, interviewSchemaFor("answer"))) } } }),
  });
  if (!response.ok) return { error: response.status };
  const body = await response.json() as any;
  const raw: string = body.choices?.[0]?.message?.content ?? "";
  let valid = true; try { JSON.parse(raw); } catch { valid = false; }
  return { valid, pretty: /^\{\s*\n/.test(raw), ms: performance.now() - started, finish: body.choices?.[0]?.finish_reason, length: raw.length, head: raw.trimEnd().slice(-120) };
});
const answered = runs.filter(r => !("error" in r)) as { valid: boolean; pretty: boolean; ms: number; finish: string; length: number; head: string }[];
const bad = answered.filter(r => !r.valid);
const times = answered.map(r => r.ms).sort((a, b) => a - b);
console.log(`${provider}: invalid ${bad.length}/${answered.length} · pretty-printed ${answered.filter(r => r.pretty).length} · errors ${runs.length - answered.length} · full reply p50 ${Math.round(times[Math.floor(times.length / 2)] ?? 0)} ms`);
for (const r of bad) console.log(`  ${r.finish} len ${r.length} · …${JSON.stringify(r.head)}`);
