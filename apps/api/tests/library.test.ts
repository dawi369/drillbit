import { runJob } from "../src/jobs";
import { env } from "cloudflare:test";
import { beforeAll, it, expect } from "vitest";
import { initializeDatabase } from "./migrations";
import { accountFor, detail, createJob, settingsFor } from "../src/store";
import {
  libraryPage,
  questionDetail,
  setEligibility,
  startQuestion,
  selectConcept,
  coverage,
} from "../src/library";
import { questionMetadata, concepts } from "../src/taxonomy";
import type { Env } from "../src/platform";
const bindings = {
  ...env,
  JOBS: { create: async () => ({ id: "test" }) },
} as unknown as Env;
beforeAll(() => initializeDatabase(bindings.DB));
async function fixture(count = 1) {
  const account = (await accountFor(bindings, crypto.randomUUID())).id;
  await env.DB.prepare("UPDATE accounts SET status='active' WHERE id=?")
    .bind(account)
    .run();
  const ids = [] as string[];
  for (let i = 0; i < count; i++) {
    const id = crypto.randomUUID(),
      date = new Date(Date.UTC(2026, 0, 1, 0, i)).toISOString();
    ids.push(id);
    const data = JSON.stringify({
      questionId: id,
      title: `Question ${i}`,
      prompt: "Design notification delivery.",
      scenario: "Notification service",
      topic: "System design",
      engineeringLevel: "senior",
      primaryConceptId: "queues",
      conceptIds: ["queues", "retry-safety"],
      secondaryConceptIds: ["retry-safety"],
      tagEvidence: [
        { conceptId: "queues", requirementIndex: 0 },
        { conceptId: "retry-safety", requirementIndex: 0 },
      ],
      constraints: [],
      targetSkill: "Delivery",
      ambiguityPolicy: "State assumptions",
      evaluationCriteria: ["private"],
      selectionSnapshot: { private: true },
    });
    await env.DB.batch([
      env.DB.prepare(
        "INSERT INTO questions(id,account_id,data,created_at,eligibility_updated_at) VALUES(?,?,?,?,?)",
      ).bind(id, account, data, date, date),
      env.DB.prepare(
        "INSERT INTO challenges(id,account_id,lifecycle,data,created_at,available_at,completed_at) VALUES(?,?,'completed',?,?,?,?)",
      ).bind(id, account, data, date, date, date),
      env.DB.prepare("INSERT INTO question_attempts VALUES(?,?)").bind(id, id),
      env.DB.prepare(
        "INSERT INTO sessions(challenge_id,answer,updated_at) VALUES(?,'Original answer',?)",
      ).bind(id, date),
    ]);
  }
  return { account, ids };
}
it("paginates all questions, combines filters, searches tag labels, and reports true coverage", async () => {
  const { account, ids } = await fixture(103);
  let cursor: string | null = null;
  const seen: string[] = [];
  do {
    const query = new URLSearchParams({
      concepts: "caching,queues",
      level: "senior",
    });
    if (cursor) query.set("cursor", cursor);
    const page = await libraryPage(bindings, account, query);
    seen.push(...page.questions.map((q) => q.id));
    cursor = page.nextCursor;
  } while (cursor);
  expect(new Set(seen).size).toBe(103);
  expect(
    (
      await libraryPage(
        bindings,
        account,
        new URLSearchParams({ q: "idempotency" }),
      )
    ).questions.length,
  ).toBe(25);
  expect(
    (
      await libraryPage(
        bindings,
        account,
        new URLSearchParams({ level: "intern" }),
      )
    ).questions,
  ).toHaveLength(0);
  expect((await coverage(bindings, account))[0]).toMatchObject({
    completedAttempts: 103,
    distinctQuestions: 103,
  });
  const q = await questionDetail(bindings, account, ids[0]!);
  expect(q.question).not.toHaveProperty("evaluationCriteria");
  expect(q.question).not.toHaveProperty("selectionSnapshot");
  await expect(
    questionDetail(bindings, "other", ids[0]!),
  ).rejects.toMatchObject({ code: "not_found" });
});
it("repeat Start is idempotent, preserves original answer, and competing devices cannot start two attempts", async () => {
  const { account, ids } = await fixture();
  const id = ids[0]!,
    command = crypto.randomUUID();
  const results = await Promise.allSettled([
    startQuestion(bindings, account, id, command),
    startQuestion(bindings, account, id, crypto.randomUUID()),
  ]);
  expect(results.filter((r) => r.status === "fulfilled")).toHaveLength(1);
  const active = await env.DB.prepare(
    "SELECT id FROM challenges WHERE account_id=? AND lifecycle='in_progress'",
  )
    .bind(account)
    .first<{ id: string }>();
  expect((await startQuestion(bindings, account, id, active!.id)).id).toBe(
    active!.id,
  );
  expect((await detail(bindings, account, id)).session?.answer).toBe(
    "Original answer",
  );
  expect((await questionDetail(bindings, account, id)).attempts).toHaveLength(
    2,
  );
});
it("add-back replays safely, detects conflicts and leaves skipped history unchanged", async () => {
  const { account, ids } = await fixture();
  const id = ids[0]!;
  await env.DB.prepare(
    "UPDATE challenges SET lifecycle='skipped',completed_at=NULL WHERE id=?",
  )
    .bind(id)
    .run();
  expect(
    (
      await libraryPage(
        bindings,
        account,
        new URLSearchParams({ skipped: "true" }),
      )
    ).questions,
  ).toHaveLength(1);
  const command = crypto.randomUUID();
  await setEligibility(bindings, account, id, command, {
    revision: 0,
    eligible: true,
  });
  await setEligibility(bindings, account, id, command, {
    revision: 0,
    eligible: true,
  });
  expect(
    (
      await libraryPage(
        bindings,
        account,
        new URLSearchParams({ skipped: "true" }),
      )
    ).questions,
  ).toHaveLength(0);
  expect((await detail(bindings, account, id)).lifecycle).toBe("skipped");
  await expect(
    setEligibility(bindings, account, id, crypto.randomUUID(), {
      revision: 0,
      eligible: false,
    }),
  ).rejects.toMatchObject({ code: "revision_conflict" });
  await expect(
    setEligibility(bindings, "other", id, crypto.randomUUID(), {
      revision: 1,
      eligible: false,
    }),
  ).rejects.toMatchObject({ code: "not_found" });
  await expect(
    setEligibility(bindings, account, id, command, {
      revision: 0,
      eligible: false,
    }),
  ).rejects.toMatchObject({ code: "command_conflict" });
});
it("selection honors an explicit concept and never treats skips as completed practice", async () => {
  const { account, ids } = await fixture();
  await env.DB.prepare("UPDATE challenges SET lifecycle='skipped' WHERE id=?")
    .bind(ids[0]!)
    .run();
  expect(await coverage(bindings, account)).toHaveLength(0);
  expect(
    (await selectConcept(bindings, account, "senior", "queues"))
      .primaryConceptId,
  ).toBe("queues");
  expect(
    (await selectConcept(bindings, account, "senior")).primaryConceptId,
  ).not.toBe("queues");
});
it("validates all canonical tags, scenario word limits and distinct evidence", () => {
  for (const concept of concepts)
    expect(
      questionMetadata.safeParse({
        scenario: "Notification service",
        primaryConceptId: concept.id,
        secondaryConceptIds: [],
        tagEvidence: [{ conceptId: concept.id, requirementIndex: 0 }],
      }).success,
    ).toBe(true);
  const value = {
    scenario: "Notification service",
    primaryConceptId: "queues",
    secondaryConceptIds: [],
    tagEvidence: [{ conceptId: "queues", requirementIndex: 0 }],
  };
  for (const bad of [
    { scenario: "A very long scenario name" },
    { primaryConceptId: "kafka" },
    { secondaryConceptIds: ["queues"] },
    { tagEvidence: [] },
  ])
    expect(questionMetadata.safeParse({ ...value, ...bad }).success).toBe(
      false,
    );
});
it("validates the shared library fixture and evidence contract", async () => {
  const { wire } = await import("../../../packages/contracts/wire");
  const fixture =
    await import("../../../packages/contracts/fixtures/library.json");
  expect(wire.LibraryPage.safeParse(fixture.default).success).toBe(true);
});

it("restored questions are reused without a provider call and retain original attempts", async () => {
  const { account, ids } = await fixture();
  const id = ids[0]!;
  await env.DB.prepare(
    "UPDATE challenges SET lifecycle='skipped',completed_at=NULL WHERE id=?",
  )
    .bind(id)
    .run();
  await setEligibility(bindings, account, id, crypto.randomUUID(), {
    revision: 0,
    eligible: true,
  });
  const command = crypto.randomUUID();
  await createJob(bindings, account, command, "generate", null, {
    settings: {
      ...(await settingsFor(bindings, account)),
      engineeringLevel: "senior",
    },
  });
  await runJob(bindings, command);
  const next = await detail(bindings, account, command);
  expect(next.questionId).toBe(id);
  expect(next.lifecycle).toBe("ready");
  expect((await detail(bindings, account, id)).session?.answer).toBe(
    "Original answer",
  );
  expect((await questionDetail(bindings, account, id)).question.eligible).toBe(
    false,
  );
});

it("competing payloads cannot reuse an eligibility command to update two questions",async()=>{
 const {account,ids}=await fixture(2),command=crypto.randomUUID();
 const results=await Promise.allSettled(ids.map(id=>setEligibility(bindings,account,id,command,{revision:0,eligible:true})));
 expect(results.filter(r=>r.status==="fulfilled")).toHaveLength(1);
 const count=await env.DB.prepare("SELECT COUNT(*) n FROM questions WHERE account_id=? AND eligible=1").bind(account).first<{n:number}>();expect(count!.n).toBe(1);
});

it("rotates feedback and overdue revisits at the requested level without treating skips as weakness", async () => {
  const {account,ids}=await fixture(4);
  for(let i=0;i<ids.length;i++) {
    const concept=["retry-safety","queues","indexing","queues"][i];
    for(const table of ["questions","challenges"]) await env.DB.prepare(`UPDATE ${table} SET data=json_set(data,'$.primaryConceptId',?,'$.conceptIds',json(?)) WHERE id=?`).bind(concept,JSON.stringify([concept]),ids[i]).run();
  }
  const feedback={summary:"Retry identity needs attention.",worked:[],improve:"Use stable keys.",takeaway:"Identify the operation.",strengths:[],gaps:[],evidence:[{conceptId:"retry-safety",quote:"Retry",observation:"No operation identity",signal:"needs_practice",assistance:"unknown"}]};
  await env.DB.prepare("INSERT INTO reflections(challenge_id,data,created_at) VALUES(?,?,?)").bind(ids[0],JSON.stringify(feedback),"2026-01-01T00:00:00Z").run();
  const selection=await selectConcept(bindings,account,"senior");
  expect(selection.primaryConceptId).toBe("retry-safety");expect(selection.reason).toContain("feedback");
  expect((await selectConcept(bindings,account,"junior")).reason).not.toContain("feedback");
  expect((await selectConcept(bindings,account,"senior","queues")).primaryConceptId).toBe("queues");
  await env.DB.prepare("UPDATE challenges SET lifecycle='skipped' WHERE id=?").bind(ids[0]).run();
  expect((await selectConcept(bindings,account,"senior")).reason).not.toContain("feedback");
});
