/** Compares candidate models on Drillbit's real requests: streamed interview turns and a question. Synthetic inputs only; full replies go to .local/. */
import { mkdirSync, writeFileSync } from "node:fs";
import { z } from "../apps/api/node_modules/zod";
import { messagesFor, textDeltas, partialInterviewText, interviewModelSchema, parseInterviewModelResult, interviewReasoning } from "../apps/api/src/ai";
import { interviewSchemaFor } from "../apps/api/src/interview";
import { MODEL_ID, normalizeSettings } from "../apps/api/src/domain";
import { generationRequest } from "../apps/api/src/generation";
import { pooled } from "./openrouter";

const key = process.env.OPENROUTER_API_KEY;
if (!key) throw Error("OPENROUTER_API_KEY required");
const models = process.argv.slice(2).length ? process.argv.slice(2) : [MODEL_ID];
const routing = { sort: "latency", require_parameters: true, ...(process.env.EVAL_PROVIDERS ? { only: process.env.EVAL_PROVIDERS.split(","), allow_fallbacks: false } : {}) };
const rounds = Number(process.env.EVAL_ROUNDS ?? 2);
const queue = { title: "Job queue", prompt: "Design a durable job queue. Explain how workers claim jobs, how retries avoid duplicate side effects and how accepted work survives a crash." };
const payments = { title: "Reliable payment retries", prompt: "Design retries for a payment API when acknowledgements can be lost. Avoid duplicate charges.", constraints: ["An external payment provider accepts idempotency keys."], engineeringLevel: "mid" };
const cases = [
  { name: "practice", context: { question: queue, interview: { guidanceMode: "coach_me", turns: [] }, historicalSnapshot: { attempts: [] }, action: { kind: "answer", text: "Workers lease jobs from a durable queue and retry failures with an idempotency key." } } },
  { name: "guided", context: { question: { ...queue, path: ["Pin down what the queue promises", "Sketch the job lifecycle", "Handle worker failures", "Make retries safe"] }, interview: { guidanceMode: "learn_together", turns: [], guidedPath: { steps: ["Pin down what the queue promises", "Sketch the job lifecycle", "Handle worker failures", "Make retries safe"], current: 0 } }, historicalSnapshot: { attempts: [] }, action: { kind: "answer", text: "I'd start by storing jobs in a table so nothing gets lost." } } },
  { name: "wrong-claim", context: { question: payments, interview: { guidanceMode: "coach_me", turns: [] }, historicalSnapshot: { attempts: [] }, action: { kind: "answer", text: "Retries guarantee exactly once because eventually they succeed." } } },
];

async function turn(model: string, context: any) {
  const schema = interviewSchemaFor("answer");
  const started = performance.now();
  const response = await fetch("https://openrouter.ai/api/v1/chat/completions", {
    method: "POST", headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json" }, signal: AbortSignal.timeout(60000),
    body: JSON.stringify({ model, messages: messagesFor("interview", context), provider: routing, reasoning: process.env.EVAL_REASONING ? { effort: process.env.EVAL_REASONING } : interviewReasoning(context), stream: true, max_tokens: 2400,
      response_format: { type: "json_schema", json_schema: { name: "drillbit_output", strict: true, schema: z.toJSONSchema(interviewModelSchema(context, schema)) } } }),
  });
  if (!response.ok || !response.body) return { error: `status ${response.status}: ${(await response.text()).slice(0, 160)}` };
  let raw = "", firstMs: number | null = null;
  for await (const delta of textDeltas(response.body)) { raw += delta; if (firstMs === null && partialInterviewText(raw)) firstMs = performance.now() - started; }
  const totalMs = performance.now() - started;
  try { return { firstMs, totalMs, reply: parseInterviewModelResult(context, schema, JSON.parse(raw)) }; }
  catch (error) { return { firstMs, totalMs, error: `invalid: ${String(error).slice(0, 160)}` }; }
}

async function question(model: string) {
  const { context, schema } = generationRequest({ settings: normalizeSettings({ engineeringLevel: "senior" }), guidanceMode: "coach_me" }, { primaryConceptId: "queues", reason: "Evaluation." });
  const started = performance.now();
  const response = await fetch("https://openrouter.ai/api/v1/chat/completions", {
    method: "POST", headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json" }, signal: AbortSignal.timeout(120000),
    body: JSON.stringify({ model, messages: messagesFor("generate", context), provider: routing, reasoning: process.env.EVAL_REASONING ? { effort: process.env.EVAL_REASONING } : { enabled: false }, stream: false, max_tokens: 2400,
      response_format: { type: "json_schema", json_schema: { name: "drillbit_output", strict: true, schema: z.toJSONSchema(schema) } } }),
  });
  const ms = performance.now() - started;
  if (!response.ok) return { ms, error: `status ${response.status}` };
  const body = await response.json() as any;
  try { const value = schema.parse(JSON.parse(body.choices[0].message.content)) as any; return { ms, title: value.title, prompt: value.prompt }; }
  catch (error) { return { ms, error: `invalid: ${String(error).slice(0, 160)}` }; }
}

const median = (values: number[]) => values.length ? Math.round([...values].sort((a, b) => a - b)[Math.floor(values.length / 2)]) : null;
const guarded = async <T,>(work: () => Promise<T>) => { try { return await work(); } catch (error) { return { error: String(error).slice(0, 120) } as any; } };
const results = await pooled(models, 4, async model => {
  const turns: any[] = [];
  for (let round = 0; round < rounds; round++) for (const sample of cases) turns.push({ case: sample.name, round, ...(await guarded(() => turn(model, sample.context))) });
  return { model, turns, question: { ms: 0, ...(await guarded(() => question(model))) } };
});

for (const { model, turns, question: q } of results) {
  const ok = turns.filter(t => !t.error);
  console.log(`\n■ ${model}\n  turns valid ${ok.length}/${turns.length} · first text p50 ${median(ok.map(t => t.firstMs ?? t.totalMs))} ms · total p50 ${median(ok.map(t => t.totalMs))} ms · reply ${median(ok.map(t => t.reply.text.length))} chars · question ${Math.round(q.ms)} ms${q.error ? " ✗ " + q.error : ""}`);
  for (const t of turns.filter(t => t.round === 0)) console.log(`  [${t.case}] ${t.error ?? t.reply.text}${t.reply?.choices?.length ? `  ⟨${t.reply.choices.join(" | ")}⟩` : ""}`);
  if (!q.error) console.log(`  [question] ${q.title}`);
  for (const t of turns.filter(t => t.error)) console.log(`  ✗ ${t.case}: ${t.error}`);
}
mkdirSync(".local", { recursive: true });
writeFileSync(`.local/model-comparison-${Date.now()}.json`, JSON.stringify(results, null, 1));
