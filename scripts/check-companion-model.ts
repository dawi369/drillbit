/** Synthetic live product evaluation. Private outputs are saved locally for human review. */
import { messagesFor } from "../apps/api/src/ai";
import { interventionFor } from "../apps/api/src/companion-contract";
import { helpSchemaFor, MODEL_ID } from "../apps/api/src/domain";
import { z } from "../apps/api/node_modules/zod";
import { writeFileSync, mkdirSync } from "node:fs";
const question = {
  title: "Reliable configuration",
  prompt:
    "Design local feature-flag evaluation for 10,000 clients. Handle control-plane outages and rollback. Explain freshness versus availability.",
};
const cases = [
  { name: "blank pause", kind: "nudge", answer: "", help: [] },
  {
    name: "incremental correction",
    kind: "nudge",
    answer:
      "Every evaluation calls the control plane. If it is down, clients wait for it to recover.",
    help: [],
  },
  {
    name: "already addressed; silence",
    kind: "nudge",
    answer:
      "Evaluate from a versioned local cache. During an outage use the last known good version and expose its age. Publish a new monotonic generation containing the previous payload to roll back. Explicitly choose availability over strict freshness.",
    help: [
      {
        kind: "nudge",
        body: "Consider how evaluation continues during a control-plane outage.",
        deliveries: ["shown"],
      },
    ],
  },
  {
    name: "nonrepetition",
    kind: "nudge",
    answer: "Cache locally. Keep the last known good version during outages.",
    help: [
      {
        kind: "nudge",
        body: "Consider what happens during a control-plane outage.",
        deliveries: ["shown"],
      },
    ],
  },
  { name: "guided entry", kind: "guide", answer: "", help: [] },
  {
    name: "guided context",
    kind: "guide",
    answer: "Use a versioned local cache.",
    help: [],
    companion: {
      selectedFocus: "Rollback without accepting stale updates",
      decisions: [
        {
          id: "1",
          text: "Use monotonic generations rather than wall clock timestamps.",
        },
      ],
    },
  },
  {
    name: "guided example",
    kind: "example",
    answer: "Use a versioned cache and push updates.",
    help: [],
  },
];
const outputs = [];
for (const item of cases.filter(
  (item) => !process.argv.includes("--guided") || item.kind !== "nudge",
)) {
  const schema = ["nudge", "guide"].includes(item.kind)
    ? interventionFor(item.kind)
    : helpSchemaFor(item.kind);
  const jsonSchema = z.toJSONSchema(schema);
  const messages = messagesFor(item.kind, {
    question,
    session: { answer: item.answer, revision: 1 },
    help: item.help,
    companion: item.companion ?? {},
    action: {
      kind: item.kind,
      mode: item.kind === "nudge" ? "coach" : "guided",
      capture: { trigger: "pause" },
    },
  });
  messages[0].content +=
    "\nRequired JSON schema: " + JSON.stringify(jsonSchema);
  const response = await fetch(
    "https://openrouter.ai/api/v1/chat/completions",
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${process.env.OPENROUTER_API_KEY}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: MODEL_ID,
        messages,
        max_tokens: 2200,
        provider: { require_parameters: true },
        response_format: {
          type: "json_schema",
          json_schema: { name: "companion", strict: true, schema: jsonSchema },
        },
      }),
      signal: AbortSignal.timeout(60000),
    },
  );
  if (!response.ok) throw new Error(`HTTP ${response.status}`);
  const result: any = await response.json();
  outputs.push({
    name: item.name,
    output: schema.parse(JSON.parse(result.choices[0].message.content)),
  });
  console.log(item.name + ": schema passed");
}
mkdirSync(".local", { recursive: true });
writeFileSync(
  process.argv.includes("--guided")
    ? ".local/companion-guided-evaluation.json"
    : ".local/companion-model-evaluation.json",
  JSON.stringify(
    { model: MODEL_ID, checkedAt: new Date().toISOString(), outputs },
    null,
    2,
  ),
);
