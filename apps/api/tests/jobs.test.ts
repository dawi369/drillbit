import { env, fetchMock } from "cloudflare:test";
import { afterAll, beforeAll, expect, it } from "vitest";
import { textDeltas } from "../src/ai";
import { boundedContext } from "../src/context";
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
async function generatedPractice(account: string, warmUp: boolean) {
  const settings = await settingsFor(bindings, account);
  const provider = (content: object) => fetchMock.get("https://openrouter.ai")
    .intercept({ path: "/api/v1/chat/completions", method: "POST" })
    .reply(200, { choices: [{ message: { content: JSON.stringify(content) } }] });
  provider({
    kind: "design", scenario: "Link saver", primaryConceptId: "api-design", secondaryConceptIds: [],
    tagEvidence: [{ conceptId: "api-design", requirementIndex: 0 }], targetSkill: "APIs", constraints: [],
    evaluationCriteria: ["lookup"], ambiguityPolicy: "State assumptions.", title: "Save a link",
    prompt: `Design a link saver that finds saved links fast (${warmUp ? "warm-up" : "counted"}).`, topic: "system design",
  });
  const id = crypto.randomUUID();
  await createJob(bindings, account, id, "generate", null, { settings, guidanceMode: "learn_together", primaryConceptId: "api-design", ...(warmUp ? { warmUp: true } : {}) });
  await runJob(bindings, id);
  await complete(bindings, account, id, crypto.randomUUID(), "Use a stable request ID for each saved link.", 0, settings);
  const summarize = await bindings.DB.prepare("SELECT id FROM jobs WHERE challenge_id=? AND kind='summarize'").bind(id).first<{ id: string }>();
  provider({
    summary: "Clear keys.", worked: ["Stable IDs."], improve: "", takeaway: "Tie the key to the link.", strengths: [], gaps: [],
    nextExercise: "Explain a lost acknowledgement.",
    evidence: [{ conceptId: "api-design", observation: "Used stable IDs.", quote: "Use a stable request ID", signal: "needs_practice", assistance: "unknown" }],
  });
  await runJob(bindings, summarize!.id);
  return id;
}
it("a warm-up is a real generated interview with feedback that never counts, joins the pool or creates Recall", async () => {
  const account = (await accountFor(bindings, crypto.randomUUID())).id;
  await bindings.DB.prepare("UPDATE accounts SET status='active' WHERE id=?").bind(account).run();
  const counted = await generatedPractice(account, false);
  // An eligible pooled question is reused by normal generation, never by a warm-up.
  await bindings.DB.prepare("INSERT INTO questions(id,account_id,data,created_at,eligible,eligibility_updated_at) VALUES(?,?,?,'2026-01-01',1,'2026-01-01')")
    .bind(crypto.randomUUID(), account, JSON.stringify({ title: "Pooled", prompt: "Pooled prompt", primaryConceptId: "api-design", engineeringLevel: (await settingsFor(bindings, account)).engineeringLevel })).run();
  const warm = await generatedPractice(account, true);
  fetchMock.assertNoPendingInterceptors();
  const warmDetail = await detail(bindings, account, warm);
  expect(warmDetail).toMatchObject({ warmUp: true, lifecycle: "completed", title: "Save a link" });
  expect(warmDetail.reflection).toMatchObject({ summary: "Clear keys." });
  expect((await detail(bindings, account, counted) as { warmUp?: boolean }).warmUp).toBeUndefined();
  const rows = (sql: string, id: string) => bindings.DB.prepare(sql).bind(id).all().then(r => r.results.length);
  expect(await rows("SELECT 1 FROM question_attempts WHERE challenge_id=?", warm)).toBe(0);
  expect(await rows("SELECT 1 FROM question_attempts WHERE challenge_id=?", counted)).toBe(1);
  expect(await rows("SELECT 1 FROM recall_cards WHERE source_challenge_id=?", warm)).toBe(0);
  expect(await rows("SELECT 1 FROM recall_cards WHERE source_challenge_id=?", counted)).toBe(1);
  expect((await todayPlan(bindings, account, null, await settingsFor(bindings, account))).completedTotal).toBe(1);
  expect((await learningEvidence(bindings, account)).map(e => e.sessionId)).toEqual([counted]);
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
        return true;
      },
    })
    .reply(200, {
      choices: [
        {
          message: {
            content: JSON.stringify({
              kind: "design",
              scenario:"Feature flags", primaryConceptId:"api-design", secondaryConceptIds:[], tagEvidence:[{conceptId:"api-design",requirementIndex:0}],
              targetSkill: "Availability",
              constraints: [],
              evaluationCriteria: ["local evaluation"],
              ambiguityPolicy: "State reasonable assumptions.",
              title: "Safe flag rollout",
              prompt:
                "Design a feature flag control plane that keeps local evaluation available during a regional outage.",
              topic: "system design",
            }),
          },
        },
      ],
    });
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
    .reply(200, { choices: [{ message: { content: "not json" } }] });
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
