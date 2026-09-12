import { wire } from "../../../packages/contracts/wire";
import contractFixture from "../../../packages/contracts/fixtures/practice-help.json";
import { env } from "cloudflare:test";
import { beforeAll, it, expect, vi } from "vitest";
import { initializeDatabase } from "./migrations";
import {
  accountFor,
  createJob,
  complete,
  detail,
  settingsFor,
} from "../src/store";
import { requestHelp, adopt } from "../src/practice";
import { runJob } from "../src/jobs";
import { MODEL_ID, normalizeSettings, settingsSchema } from "../src/domain";
import type { Env } from "../src/platform";
const bindings = {
  ...env,
  MANAGED_AI_ENABLED: "true",
  OPENROUTER_API_KEY: "test",
  MODEL_ID: "obsolete",
  JOBS: { create: async () => ({ id: "test" }) },
} as unknown as Env;
beforeAll(() => initializeDatabase(bindings.DB));
async function fixture() {
  const a = await accountFor(bindings, crypto.randomUUID()),
    id = crypto.randomUUID();
  await bindings.DB.prepare("UPDATE accounts SET status='active' WHERE id=?")
    .bind(a.id)
    .run();
  await bindings.DB.prepare(
    "INSERT INTO challenges(id,account_id,lifecycle,data,created_at,available_at) VALUES(?,?,'in_progress',?,'now','now')",
  )
    .bind(
      id,
      a.id,
      JSON.stringify({
        title: "Cache",
        prompt: "Design a reliable configuration cache.",
        topic: "Design",
      }),
    )
    .run();
  await bindings.DB.prepare(
    "INSERT INTO sessions(challenge_id,answer,revision,updated_at) VALUES(?,'My original reasoning',2,'now')",
  )
    .bind(id)
    .run();
  return { a: a.id, id };
}
async function source(a: string, id: string) {
  const job = await requestHelp(bindings, a, id, crypto.randomUUID(), {
    kind: "draft",
    mode: "guided",
    revision: 2,
  });
  await bindings.DB.prepare("UPDATE jobs SET status='completed' WHERE id=?")
    .bind(job.id)
    .run();
  await bindings.DB.prepare("INSERT INTO help_results(id,data) VALUES(?,?)")
    .bind(
      job.id,
      JSON.stringify({
        body: "A suggestion",
        suggestedAnswer: "An assisted draft",
      }),
    )
    .run();
  return job.id;
}
it("allows one help request, replays it, and rejects command reuse", async () => {
  const { a, id } = await fixture(),
    command = crypto.randomUUID(),
    input = { kind: "hint", mode: "coach", revision: 2 };
  const first = await requestHelp(bindings, a, id, command, input);
  expect((await requestHelp(bindings, a, id, command, input)).id).toBe(
    first.id,
  );
  await expect(
    requestHelp(bindings, a, id, command, { ...input, kind: "check" }),
  ).rejects.toMatchObject({ code: "command_conflict" });
  await expect(
    requestHelp(bindings, a, id, crypto.randomUUID(), input),
  ).rejects.toMatchObject({ code: "help_conflict" });
});
it("adopts exactly once, rejects stale insertion, and restores the previous answer with undo", async () => {
  const { a, id } = await fixture(),
    sourceId = await source(a, id),
    command = crypto.randomUUID();
  const input = { sourceId, operation: "replace", revision: 2 };
  const first = await adopt(bindings, a, id, command, input);
  expect(first.session?.answer).toBe("An assisted draft");
  expect((await adopt(bindings, a, id, command, input)).session?.revision).toBe(
    3,
  );
  await expect(
    adopt(bindings, a, id, crypto.randomUUID(), input),
  ).rejects.toMatchObject({ code: "revision_conflict" });
  const restored = await adopt(bindings, a, id, crypto.randomUUID(), {
    sourceId: command,
    operation: "undo",
    revision: 3,
  });
  expect(restored.session?.answer).toBe("My original reasoning");
  expect(restored.adoptions).toHaveLength(2);
});
it("rejects foreign sources and cannot undo after another edit", async () => {
  const one = await fixture(),
    two = await fixture(),
    sourceId = await source(one.a, one.id);
  await expect(
    adopt(bindings, two.a, two.id, crypto.randomUUID(), {
      sourceId,
      operation: "replace",
      revision: 2,
    }),
  ).rejects.toMatchObject({ code: "invalid_source" });
  const command = crypto.randomUUID();
  await adopt(bindings, one.a, one.id, command, {
    sourceId,
    operation: "append",
    revision: 2,
  });
  await bindings.DB.prepare(
    "UPDATE sessions SET answer='Later edit',revision=4 WHERE challenge_id=?",
  )
    .bind(one.id)
    .run();
  await expect(
    adopt(bindings, one.a, one.id, crypto.randomUUID(), {
      sourceId: command,
      operation: "undo",
      revision: 3,
    }),
  ).rejects.toMatchObject({ code: "revision_conflict" });
  expect((await detail(bindings, one.a, one.id)).session?.answer).toBe(
    "Later edit",
  );
});
it("completion wins over a late provider result and freezes assistance", async () => {
  const { a, id } = await fixture(),
    job = await requestHelp(bindings, a, id, crypto.randomUUID(), {
      kind: "hint",
      mode: "coach",
      revision: 2,
    });
  let release!: () => void;
  const gate = new Promise<void>((resolve) => {
    release = resolve;
  });
  let called!: () => void;
  const started = new Promise<void>((resolve) => {
    called = resolve;
  });
  const mock = vi
    .spyOn(globalThis, "fetch")
    .mockImplementation(async (_url, init) => {
      expect(JSON.parse(String(init?.body)).model).toBe(MODEL_ID);
      called();
      await gate;
      return Response.json({
        choices: [
          {
            message: {
              content: JSON.stringify({
                body: "Late hint",
                suggestedAnswer: null,
              }),
            },
          },
        ],
      });
    });
  try {
    const run = runJob(bindings, job.id);
    await started;
    await complete(
      bindings,
      a,
      id,
      crypto.randomUUID(),
      "Final answer",
      2,
      await settingsFor(bindings, a),
    );
    release();
    await run;
    const current = await detail(bindings, a, id);
    expect(current.help[0].status).toBe("cancelled");
    expect(current.help[0].body).toBeUndefined();
    expect(current.session?.answer).toBe("Final answer");
  } finally {
    release();
    mock.mockRestore();
  }
});
it("normalizes old persisted models but rejects selecting another model", () => {
  expect(normalizeSettings({ model: "old" }).model).toBe(MODEL_ID);
  expect(settingsSchema.safeParse({ model: "google/gemini-3.1-flash-lite" }).success).toBe(true);
  expect(normalizeSettings({ model: "google/gemini-3.1-flash-lite" }).model).toBe(MODEL_ID);
  expect(settingsSchema.safeParse({ model: "old" }).success).toBe(false);
});

it("validates the shared help/adoption wire fixture", async () => {
  expect(wire.Challenge.parse(contractFixture).adoptions?.[0].revision).toBe(3);
});
it("preserves completion context if a reference answer is viewed later", async () => {
  const { a, id } = await fixture();
  await source(a, id);
  await complete(
    bindings,
    a,
    id,
    crypto.randomUUID(),
    "My final reasoning",
    2,
    await settingsFor(bindings, a),
  );
  const frozen = await bindings.DB.prepare(
    "SELECT data FROM completion_context WHERE challenge_id=?",
  )
    .bind(id)
    .first<{ data: string }>();
  expect(JSON.parse(frozen!.data).help[0].suggestedAnswer).toBe(
    "An assisted draft",
  );
  await bindings.DB.prepare(
    "INSERT INTO examples(challenge_id,data,created_at) VALUES(?,'{}','later')",
  )
    .bind(id)
    .run();
  expect(
    await bindings.DB.prepare(
      "SELECT data FROM completion_context WHERE challenge_id=?",
    )
      .bind(id)
      .first(),
  ).toEqual(frozen);
});
it("a cancelled help request produces no late result", async () => {
  const { a, id } = await fixture(),
    job = await requestHelp(bindings, a, id, crypto.randomUUID(), {
      kind: "hint",
      mode: "coach",
      revision: 2,
    });
  await bindings.DB.prepare("UPDATE jobs SET status='cancelled' WHERE id=?")
    .bind(job.id)
    .run();
  await runJob(bindings, job.id);
  expect((await detail(bindings, a, id)).help[0].body).toBeUndefined();
});

it("two concurrent adoptions cannot both overwrite the same revision", async () => {
  const { a, id } = await fixture(),
    sourceId = await source(a, id);
  const results = await Promise.allSettled(
    ["append", "replace"].map((operation) =>
      adopt(bindings, a, id, crypto.randomUUID(), {
        sourceId,
        operation,
        revision: 2,
      }),
    ),
  );
  expect(
    results.filter((result) => result.status === "fulfilled"),
  ).toHaveLength(1);
  const current = await detail(bindings, a, id);
  expect(current.session?.revision).toBe(3);
  expect(current.adoptions).toHaveLength(1);
});
it("starting a question wins against an in-flight replacement", async () => {
  const { a, id } = await fixture();
  await bindings.DB.prepare(
    "UPDATE challenges SET lifecycle='ready' WHERE id=?",
  )
    .bind(id)
    .run();
  await bindings.DB.prepare(
    "UPDATE sessions SET answer='' WHERE challenge_id=?",
  )
    .bind(id)
    .run();
  const replacement = crypto.randomUUID();
  await createJob(bindings, a, replacement, "generate", null, {
    settings: await settingsFor(bindings, a),
    replaceId: id,
  });
  let release!: () => void, began!: () => void;
  const gate = new Promise<void>((r) => (release = r)),
    started = new Promise<void>((r) => (began = r));
  const mock = vi.spyOn(globalThis, "fetch").mockImplementation(async () => {
    began();
    await gate;
    return Response.json({
      choices: [
        {
          message: {
            content: JSON.stringify({
              scenario:"Outage recovery", primaryConceptId:"api-design", secondaryConceptIds:[], tagEvidence:[{conceptId:"api-design",requirementIndex:0}],
              title: "New question",
              prompt: "Explain how to handle an outage.",
              topic: "Systems",
              kind: "explain",
              targetSkill: "Reliability",
              constraints: [],
              ambiguityPolicy: "State assumptions",
            }),
          },
        },
      ],
    });
  });
  try {
    const running = runJob(bindings, replacement);
    await started;
    await bindings.DB.prepare(
      "UPDATE challenges SET lifecycle='in_progress' WHERE id=?",
    )
      .bind(id)
      .run();
    release();
    await running;
    expect((await detail(bindings, a, id)).lifecycle).toBe("in_progress");
    expect(
      await bindings.DB.prepare(
        "SELECT id FROM challenges WHERE account_id=? AND lifecycle IN ('ready','in_progress')",
      )
        .bind(a)
        .all()
        .then((r) => r.results),
    ).toHaveLength(1);
  } finally {
    release();
    mock.mockRestore();
  }
});
