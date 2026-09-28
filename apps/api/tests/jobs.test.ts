import { env, fetchMock } from "cloudflare:test";
import { afterAll, beforeAll, expect, it } from "vitest";
import { partialJSONString, textDeltas } from "../src/ai";
import { boundedContext } from "../src/context";
import { roundTiming } from "../src/domain";
import { runJob } from "../src/jobs";
import { learningEvidence, todayPlan } from "../src/learning";
import type { Env } from "../src/platform";
import { accountFor, complete, createJob, detail, settingsFor } from "../src/store";
import { initializeDatabase } from "./migrations";
const bindings = {
  ...env,
  JOBS: { create: async () => ({ id: "test" }) },
  MANAGED_AI_ENABLED: "true",
  OPENROUTER_API_KEY: "test-provider-key",
  MODEL_ID: "test-model",
} as unknown as Env;
beforeAll(async () => {
  await initializeDatabase(bindings.DB);
  fetchMock.activate();
  fetchMock.disableNetConnect();
});
afterAll(() => fetchMock.deactivate());
// Generation streams; OpenRouter frames structured output as SSE content deltas.
const sse = (content: string) => (content.match(/[\s\S]{1,24}/g) ?? [])
  .map(part => `data: ${JSON.stringify({ choices: [{ delta: { content: part } }] })}\n\n`).join("") + "data: [DONE]\n\n";
const streamHeaders = { headers: { "content-type": "text/event-stream" } };
async function generatedPractice(account: string, warmUp: boolean, mode = "learn_together") {
  const settings = await settingsFor(bindings, account);
  const requests: any[] = [];
  const provider = (content: object, stream = false) => fetchMock.get("https://openrouter.ai")
    .intercept({ path: "/api/v1/chat/completions", method: "POST", body: (raw: string) => { requests.push(JSON.parse(raw)); return true; } })
    .reply(200, stream ? sse(JSON.stringify(content)) : { choices: [{ message: { content: JSON.stringify(content) } }] }, stream ? streamHeaders : undefined);
  provider({
    kind: "design", scenario: "Link saver", primaryConceptId: "api-design", secondaryConceptIds: [],
    tagEvidence: [{ conceptId: "api-design", requirementIndex: 0 }], targetSkill: "APIs", constraints: [],
    evaluationCriteria: ["lookup"], ambiguityPolicy: "State assumptions.", title: "Save a link", minutes: 20, path: ["Pin down lookups", "Sketch the API", "Choose the storage"],
    prompt: `Design a link saver that finds saved links fast (${warmUp ? "warm-up" : "counted"}).`, topic: "system design",
  }, true);
  const id = crypto.randomUUID();
  await createJob(bindings, account, id, "generate", null, { settings, guidanceMode: mode, primaryConceptId: "api-design", ...(warmUp ? { warmUp: true } : {}) });
  await runJob(bindings, id);
  await complete(bindings, account, id, crypto.randomUUID(), "Use a stable request ID for each saved link.", 0, settings);
  const summarize = await bindings.DB.prepare("SELECT id FROM jobs WHERE challenge_id=? AND kind='summarize'").bind(id).first<{ id: string }>();
  provider({
    summary: "Clear keys.", worked: ["Stable IDs."], improve: "", takeaway: "Tie the key to the link.", strengths: [], gaps: [],
    nextExercise: "Explain a lost acknowledgement.",
    evidence: [{ conceptId: "api-design", observation: "Used stable IDs.", quote: "Use a stable request ID", signal: "needs_practice", assistance: "unknown" }],
    ...(mode === "learn_together" ? { lesson: { learned: ["A stable ID lets a retry find the original save"], tryAlone: "Apply stable IDs to a payment retry." } } : {}),
    ...(mode === "mock_interview" ? { debrief: { verdict: "borderline", reason: "Stable IDs are right; lookup speed was never addressed.", toPass: "Explain the index behind fast lookup.",
      signals: ["requirements", "design", "trade_offs", "communication"].map(area => ({ area, rating: "mixed", note: "Partly covered." })) } } : {}),
  });
  await runJob(bindings, summarize!.id);
  return { id, summarizeRequest: requests.at(-1) };
}
it("a warm-up is a real generated interview with feedback that never counts, joins the pool or creates Recall", async () => {
  const account = (await accountFor(bindings, crypto.randomUUID())).id;
  await bindings.DB.prepare("UPDATE accounts SET status='active' WHERE id=?").bind(account).run();
  const counted = (await generatedPractice(account, false)).id;
  // An eligible pooled question is reused by normal generation, never by a warm-up.
  await bindings.DB.prepare("INSERT INTO questions(id,account_id,data,created_at,eligible,eligibility_updated_at) VALUES(?,?,?,'2026-01-01',1,'2026-01-01')")
    .bind(crypto.randomUUID(), account, JSON.stringify({ title: "Pooled", prompt: "Pooled prompt", primaryConceptId: "api-design", engineeringLevel: (await settingsFor(bindings, account)).engineeringLevel })).run();
  const warm = (await generatedPractice(account, true)).id;
  fetchMock.assertNoPendingInterceptors();
  const warmDetail = await detail(bindings, account, warm);
  expect(warmDetail).toMatchObject({ warmUp: true, lifecycle: "completed", title: "Save a link", minutes: 20 });
  expect(warmDetail.reflection).toMatchObject({ summary: "Clear keys.", guidanceMode: "learn_together", lesson: { learned: ["A stable ID lets a retry find the original save"] } });
  expect((await detail(bindings, account, counted) as { warmUp?: boolean }).warmUp).toBeUndefined();
  const rows = (sql: string, id: string) => bindings.DB.prepare(sql).bind(id).all().then(r => r.results.length);
  expect(await rows("SELECT 1 FROM question_attempts WHERE challenge_id=?", warm)).toBe(0);
  expect(await rows("SELECT 1 FROM question_attempts WHERE challenge_id=?", counted)).toBe(1);
  expect(await rows("SELECT 1 FROM recall_cards WHERE source_challenge_id=?", warm)).toBe(0);
  expect(await rows("SELECT 1 FROM recall_cards WHERE source_challenge_id=?", counted)).toBe(1);
  expect((await todayPlan(bindings, account, null, await settingsFor(bindings, account))).completedTotal).toBe(1);
  expect((await learningEvidence(bindings, account)).map(e => e.sessionId)).toEqual([counted]);
});
it("a mock interview ends with a timed debrief and a verdict, not the coaching summary", async () => {
  const account = (await accountFor(bindings, crypto.randomUUID())).id;
  await bindings.DB.prepare("UPDATE accounts SET status='active' WHERE id=?").bind(account).run();
  const { id, summarizeRequest } = await generatedPractice(account, false, "mock_interview");
  fetchMock.assertNoPendingInterceptors();
  expect(summarizeRequest.messages[0].content).toContain('<ending mode="mock_interview">');
  expect(summarizeRequest.messages[1].content).toContain("limitMinutes");
  expect(summarizeRequest.response_format.json_schema.schema.required).toContain("debrief");
  const reflection = (await detail(bindings, account, id)).reflection as any;
  expect(reflection).toMatchObject({ guidanceMode: "mock_interview", debrief: { verdict: "borderline", toPass: "Explain the index behind fast lookup." } });
  expect(reflection.debrief.signals).toHaveLength(4);
  expect(reflection.lesson).toBeUndefined();
});
it("a round lasts the generator's minutes, falling back by level, and counts from the start", () => {
  const start = "2026-09-28T10:00:00.000Z";
  expect(roundTiming({ minutes: 25, startedAt: start }, "2026-09-28T09:00:00.000Z", Date.parse(start) + 10.5 * 60000)).toEqual({ limitMinutes: 25, elapsedMinutes: 10 });
  expect(roundTiming({ engineeringLevel: "staff" }, start, Date.parse(start))).toEqual({ limitMinutes: 45, elapsedMinutes: 0 });
});
it("durably generates a valid challenge and replay does not call the provider again", async () => {
  const account = await accountFor(bindings, crypto.randomUUID());
  await bindings.DB.prepare("UPDATE accounts SET status='active' WHERE id=?")
    .bind(account.id)
    .run();
  fetchMock
    .get("https://openrouter.ai")
    .intercept({
      path: "/api/v1/chat/completions",
      method: "POST",
      body: (raw: string) => {
        const request = JSON.parse(raw);
        expect(request.provider.require_parameters).toBe(true);
        expect(request.provider.sort).toBe("latency");
        expect(request.reasoning.enabled).toBe(false);
        expect(request.model).toBe("openai/gpt-6-luna");
        expect(request.messages[0].content).not.toContain("Required JSON schema:");
        expect(request.response_format.type).toBe("json_schema");
        expect(request.response_format.json_schema.schema.properties).toHaveProperty("ambiguityPolicy");
        expect(request.stream).toBe(true);
        return true;
      },
    })
    .reply(200, sse(JSON.stringify({
              kind: "design",
              scenario:"Feature flags", primaryConceptId:"api-design", secondaryConceptIds:[], tagEvidence:[{conceptId:"api-design",requirementIndex:0}],
              targetSkill: "Availability",
              constraints: [],
              evaluationCriteria: ["local evaluation"],
              ambiguityPolicy: "State reasonable assumptions.",
              title: "Safe flag rollout",
              minutes: 25, path: ["Pin down the outage", "Sketch evaluation", "Plan rollout"],
              prompt:
                "Design a feature flag control plane that keeps local evaluation available during a regional outage.",
              topic: "system design",
            })), streamHeaders);
  const id = crypto.randomUUID();
  await createJob(bindings, account.id, id, "generate", null, {
    settings: await settingsFor(bindings, account.id),
    guidanceMode: "learn_together",
  });
  await runJob(bindings, id);
  await runJob(bindings, id);
  const result = await detail(bindings, account.id, id);
  expect(result.lifecycle).toBe("ready");
  expect(result.guidanceMode).toBe("learn_together");
  expect(result.session?.revision).toBe(0);
  expect(
    await bindings.DB.prepare("SELECT status FROM jobs WHERE id=?")
      .bind(id)
      .first(),
  ).toEqual({ status: "completed" });
  // The preview's streamed draft ends as exactly the question's title and prompt.
  const draft = await bindings.DB.prepare("SELECT text FROM interview_streams WHERE job_id=?").bind(id).first<{ text: string }>();
  expect(JSON.parse(draft!.text)).toEqual({
    title: "Safe flag rollout",
    prompt: "Design a feature flag control plane that keeps local evaluation available during a regional outage.",
  });
  fetchMock.assertNoPendingInterceptors();
});
it("does not replace a valid ready challenge when the provider returns malformed output", async () => {
  const account = await accountFor(bindings, crypto.randomUUID());
  await bindings.DB.prepare("UPDATE accounts SET status='active' WHERE id=?")
    .bind(account.id)
    .run();
  const ready = crypto.randomUUID();
  await bindings.DB.prepare(
    "INSERT INTO challenges(id,account_id,lifecycle,data,created_at,available_at) VALUES(?,?,'ready','{}','now','now')",
  )
    .bind(ready, account.id)
    .run();
  fetchMock
    .get("https://openrouter.ai")
    .intercept({ path: "/api/v1/chat/completions", method: "POST" })
    .reply(200, sse("not json"), streamHeaders);
  const id = crypto.randomUUID();
  await createJob(bindings, account.id, id, "generate", null, {
    settings: await settingsFor(bindings, account.id),
    replaceId: ready,
  });
  await expect(runJob(bindings, id)).rejects.toMatchObject({
    code: "invalid_output",
  });
  expect(
    await bindings.DB.prepare("SELECT lifecycle FROM challenges WHERE id=?")
      .bind(ready)
      .first(),
  ).toEqual({ lifecycle: "ready" });
});
it("trims older evidence without trimming the current answer or follow-up", () => {
  const answer = "current answer";
  const context = boundedContext(
    {
      session: { answer },
      latestQuestion: "question",
      turns: Array.from({ length: 12 }, () => ({ text: "old".repeat(100) })),
      example: { overview: "not user evidence" },
      recent: Array.from({ length: 20 }, () => "old memory".repeat(100)),
    },
    1000,
  ) as any;
  expect(context.session.answer).toBe(answer);
  expect(context.latestQuestion).toBe("question");
  expect(context.exampleViewed).toBe(true);
  expect(context.example).toBeUndefined();
  expect(JSON.stringify(context).length).toBeLessThanOrEqual(1000);
});
it("reads a partial question field without exposing a split escape", () => {
  const raw = '{"kind":"design","title":"Queue \\"retries\\"","prompt":"Design a queue\\u00';
  expect(partialJSONString(raw, "title")).toBe('Queue "retries"');
  expect(partialJSONString(raw, "prompt")).toBe("Design a queue");
  expect(partialJSONString('{"kind":"de', "title")).toBe("");
});
it("parses streamed events split across chunks, including CRLF framing", async () => {
  const encoder = new TextEncoder();
  const raw =
    'data: {"choices":[{"delta":{"content":"hello"}}]}\r\n\r\ndata: [DONE]\r\n\r\n';
  const stream = new ReadableStream<Uint8Array>({
    start(controller) {
      for (const chunk of [raw.slice(0, 12), raw.slice(12, 49), raw.slice(49)])
        controller.enqueue(encoder.encode(chunk));
      controller.close();
    },
  });
  const output = [];
  for await (const delta of textDeltas(stream)) output.push(delta);
  expect(output).toEqual(["hello"]);
});

it("never accepts truncated streamed output as completed", async () => {
  const stream = new ReadableStream<Uint8Array>({
    start(controller) {
      controller.enqueue(
        new TextEncoder().encode(
          'data: {"choices":[{"delta":{"content":"partial"}}]}\n\n',
        ),
      );
      controller.close();
    },
  });
  const consume = async () => {
    for await (const _ of textDeltas(stream)) {
    }
  };
  await expect(consume()).rejects.toThrow("incomplete_stream");
});

it("deletes a redeemed invitation and all account data after Clerk deletion", async () => {
  const account = await accountFor(bindings, "delete-test-person");
  await bindings.DB.prepare("UPDATE accounts SET status='deleting' WHERE id=?")
    .bind(account.id)
    .run();
  await bindings.DB.prepare(
    "INSERT INTO invites(hash,redeemed_by,created_at) VALUES('used-invite',?,'now')",
  )
    .bind(account.id)
    .run();
  const id = crypto.randomUUID();
  await createJob(bindings, account.id, id, "delete_account", null, {});
  fetchMock
    .get("https://api.clerk.com")
    .intercept({ path: "/v1/users/delete-test-person", method: "DELETE" })
    .reply(200, {});
  await runJob({ ...bindings, CLERK_SECRET_KEY: "test-only" }, id);
  expect(
    await bindings.DB.prepare("SELECT id FROM accounts WHERE id=?")
      .bind(account.id)
      .first(),
  ).toBeNull();
  expect(
    await bindings.DB.prepare(
      "SELECT hash FROM invites WHERE hash='used-invite'",
    ).first(),
  ).toBeNull();
  expect(
    await bindings.DB.prepare("SELECT id FROM jobs WHERE id=?")
      .bind(id)
      .first(),
  ).toBeNull();
});
it("returns durable job intent before slow workflow dispatch completes", async () => {
  const account = await accountFor(bindings, crypto.randomUUID());
  await bindings.DB.prepare("UPDATE accounts SET status='active' WHERE id=?").bind(account.id).run();
  let release!: () => void;
  const gate = new Promise<void>(resolve => { release = resolve; });
  const deferred: Promise<unknown>[] = [];
  const fast = {...bindings, JOBS:{create: async () => { await gate; return {id:"slow"}; }}, defer:(work:Promise<unknown>) => deferred.push(work)} as unknown as Env;
  const id = crypto.randomUUID();
  const result = await createJob(fast,account.id,id,"generate",null,{settings:await settingsFor(bindings,account.id)});
  expect(result?.id).toBe(id);
  expect(deferred).toHaveLength(1);
  expect(await bindings.DB.prepare("SELECT status FROM jobs WHERE id=?").bind(id).first()).toMatchObject({status:"pending"});
  release(); await Promise.all(deferred);
});
