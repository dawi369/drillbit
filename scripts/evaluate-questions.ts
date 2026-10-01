/** Synthetic question-writing evaluation for the Key facts block; never reads private practice records. The full run goes to .local/. */
import { mkdirSync, writeFileSync } from "node:fs";
import { messagesFor } from "../apps/api/src/ai";
import { managedModel, normalizeSettings } from "../apps/api/src/domain";
import { generationRequest } from "../apps/api/src/generation";
import { pooled, structuredCall } from "./openrouter";

const combos = [
  { level: "junior", mode: "coach_me", concept: "caching" },
  { level: "mid", mode: "coach_me", concept: "retry-safety" },
  { level: "mid", mode: "learn_together", concept: "rate-limiting" },
  { level: "senior", mode: "learn_together", concept: "queues" },
  { level: "senior", mode: "coach_me", concept: "partitioning" },
  { level: "senior", mode: "mock_interview", concept: "fault-tolerance" },
  { level: "staff", mode: "coach_me", concept: "migration" },
  { level: "mid", mode: "mock_interview", concept: "indexing" },
];

/** The same split the app uses: blank lines separate paragraphs, a paragraph of "• " lines is the Key facts block. */
function shape(prompt: string) {
  const paragraphs = prompt.split(/\n\s*\n/).map(p => p.trim()).filter(Boolean);
  const facts = paragraphs.filter(p => p.split("\n").every(line => /^(•|-) /.test(line))).flatMap(p => p.split("\n").map(line => line.slice(2)));
  return { paragraphs: paragraphs.length, facts, ask: paragraphs.at(-1) ?? "" };
}

const runs = await pooled(combos, 4, async combo => {
  const settings = normalizeSettings({ engineeringLevel: combo.level });
  const { context, schema } = generationRequest({ settings, guidanceMode: combo.mode }, { primaryConceptId: combo.concept, reason: "Evaluation." });
  const { value, cost, ms } = await structuredCall(messagesFor("generate", context), schema, { enabled: false }, process.env.EVAL_MODEL ?? managedModel("generate"));
  const question = value as { title: string; prompt: string; constraints: string[]; minutes: number; path: string[] };
  const { paragraphs, facts, ask } = shape(question.prompt);
  const exploratory = combo.mode === "mock_interview" || (["senior", "staff"].includes(combo.level) && combo.mode !== "learn_together");
  const flags = [
    combo.mode === "mock_interview" && facts.length > 0 && "mock-has-facts",
    facts.length > 4 && "too-many-facts",
    facts.length === 1 && "single-fact",
    facts.some(f => f.length > 80) && "fact>80",
    facts.some(f => /\b(must|should|needs? to|ensure)\b/i.test(f)) && "fact-is-requirement",
    exploratory && combo.mode !== "mock_interview" && facts.some(f => /\d/.test(f)) && "exploratory-numbers",
    !/\?$/.test(ask) && "ask-not-a-question",
  ].filter(Boolean);
  return { ...combo, title: question.title, prompt: question.prompt, constraints: question.constraints, minutes: question.minutes, path: question.path, paragraphs, facts, flags, cost, ms };
});

let total = 0;
for (const run of runs) {
  total += run.cost;
  console.log(`\n■ ${run.level} · ${run.mode} · ${run.concept} · ${run.minutes} min · ${run.ms} ms${run.flags.length ? `\n  ⚑ ${run.flags.join(", ")}` : ""}`);
  console.log(`  ${run.title}\n${run.prompt.split("\n").map(line => "  │ " + line).join("\n")}`);
  if (run.constraints.length) console.log(`  constraints: ${run.constraints.join(" · ")}`);
}
console.log(`\nWith key facts: ${runs.filter(r => r.facts.length).length}/${runs.length} · flagged ${runs.filter(r => r.flags.length).length} · cost $${total.toFixed(4)}`);
mkdirSync(".local", { recursive: true });
writeFileSync(`.local/questions-eval-${Date.now()}.json`, JSON.stringify(runs, null, 1));
