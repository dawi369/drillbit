/** Probes one provider for runaway output on a mock-interview turn. Synthetic input only. */
import { z } from "../apps/api/node_modules/zod";
import { messagesFor, interviewModelSchema } from "../apps/api/src/ai";
import { interviewSchemaFor } from "../apps/api/src/interview";
import { managedModel } from "../apps/api/src/domain";
import { pooled } from "./openrouter";

const key = process.env.OPENROUTER_API_KEY;
const provider = process.env.EVAL_PROVIDERS ?? "together";
const context = { question: { title: "API Design for Order Status Updates", prompt: "Design an internal API endpoint that allows a mobile client to poll for order status as it moves through logistics stages.", engineeringLevel: "junior" }, interview: { guidanceMode: "mock_interview", turns: [] }, historicalSnapshot: { attempts: [] }, action: { kind: "answer", text: "I will start with Kafka and six microservices, then choose the API later." } };
const runs = await pooled(Array.from({ length: Number(process.env.EVAL_ROUNDS ?? 20) }, (_, i) => i), 5, async () => {
  const response = await fetch("https://openrouter.ai/api/v1/chat/completions", {
    method: "POST", headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
    body: JSON.stringify({ model: managedModel("interview"), messages: messagesFor("interview", context), provider: { only: provider.split(","), allow_fallbacks: false, require_parameters: true }, reasoning: { enabled: false }, max_tokens: 900,
      response_format: { type: "json_schema", json_schema: { name: "drillbit_output", strict: true, schema: z.toJSONSchema(interviewModelSchema(context, interviewSchemaFor("answer"))) } } }),
  });
  const body = await response.json() as any;
  const raw: string = body.choices?.[0]?.message?.content ?? "";
  let valid = true; try { JSON.parse(raw); } catch { valid = false; }
  return { valid, finish: body.choices?.[0]?.finish_reason, length: raw.length, head: raw.trimEnd().slice(-120) };
});
const bad = runs.filter(r => !r.valid);
console.log(`${provider}: invalid ${bad.length}/${runs.length}`);
for (const r of bad) console.log(`  ${r.finish} len ${r.length} · …${JSON.stringify(r.head)}`);
