/** Shared OpenRouter call for prompt evaluations: the same model, provider routing and strict schema production uses. */
import { z } from "../apps/api/node_modules/zod";
import { MODEL_ID } from "../apps/api/src/domain";

const key = process.env.OPENROUTER_API_KEY;
if (!key) throw Error("OPENROUTER_API_KEY required");

export async function structuredCall(messages: unknown[], schema: z.ZodType, reasoning: { enabled: false } | { effort: "low" }, model = process.env.EVAL_MODEL ?? MODEL_ID) {
  const started = Date.now();
  const response = await fetch("https://openrouter.ai/api/v1/chat/completions", {
    method: "POST",
    headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
    signal: AbortSignal.timeout(120000),
    body: JSON.stringify({
      model, messages, reasoning, stream: false, max_tokens: 2400,
      provider: { sort: "latency", require_parameters: true },
      response_format: { type: "json_schema", json_schema: { name: "drillbit_output", strict: true, schema: z.toJSONSchema(schema) } },
    }),
  });
  if (!response.ok) throw Error(`Provider ${response.status}: ${(await response.text()).slice(0, 300)}`);
  const envelope = await response.json() as { choices: { message: { content: string } }[]; usage?: { cost?: number } };
  return { value: schema.parse(JSON.parse(envelope.choices[0].message.content)), cost: envelope.usage?.cost ?? 0, ms: Date.now() - started };
}

/** Runs tasks with bounded concurrency so a batch stays polite to the provider. */
export async function pooled<T, R>(items: T[], limit: number, task: (item: T) => Promise<R>) {
  const results: R[] = new Array(items.length);
  let next = 0;
  await Promise.all(Array.from({ length: Math.min(limit, items.length) }, async () => {
    while (next < items.length) { const index = next++; results[index] = await task(items[index]); }
  }));
  return results;
}
