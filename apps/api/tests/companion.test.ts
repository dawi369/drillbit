import { env } from "cloudflare:test";
import { beforeAll, it, expect } from "vitest";
import { initializeDatabase } from "./migrations";
import { accountFor, complete, settingsFor } from "../src/store";
import { contextFor, updateContext, receive } from "../src/companion";
import { requestHelp } from "../src/practice";
import type { Env } from "../src/platform";
const bindings = {
  ...env,
  COMPANION_AUTO_ENABLED: "true",
  JOBS: { create: async () => ({ id: "test" }) },
} as unknown as Env;
beforeAll(() => initializeDatabase(bindings.DB));
async function fixture() {
  const a = (await accountFor(bindings, crypto.randomUUID())).id,
    id = crypto.randomUUID();
  await bindings.DB.prepare("UPDATE accounts SET status='active' WHERE id=?")
    .bind(a)
    .run();
  await bindings.DB.prepare(
    "INSERT INTO challenges(id,account_id,lifecycle,data,created_at,available_at) VALUES(?,?,'in_progress',?,'now','now')",
  )
    .bind(
      id,
      a,
      JSON.stringify({
        title: "Cache",
        prompt: "Design a cache",
        topic: "Design",
      }),
    )
    .run();
  await bindings.DB.prepare(
    "INSERT INTO sessions(challenge_id,answer,revision,updated_at) VALUES(?,'',0,'now')",
  )
    .bind(id)
    .run();
  const context = await updateContext(bindings, a, id, crypto.randomUUID(), {
    revision: 0,
    operation: "mode",
    mode: "coach",
  });
  return { a, id, context };
}
function input(c: Awaited<ReturnType<typeof contextFor>>) {
  return {
    kind: "nudge",
    mode: "coach",
    revision: 0,
    capture: {
      contextRevision: c.revision,
      modeEpoch: c.modeEpoch,
      digest: c.digest,
      cycle: c.cycle,
      trigger: "pause",
    },
  };
}
it("rejects duplicate automatic cycles from competing devices and shares the budget", async () => {
  const { a, id, context } = await fixture();
  const results = await Promise.allSettled([
    requestHelp(bindings, a, id, crypto.randomUUID(), input(context)),
    requestHelp(bindings, a, id, crypto.randomUUID(), input(context)),
  ]);
  expect(results.filter((x) => x.status === "fulfilled")).toHaveLength(1);
  expect((await contextFor(bindings, a, id)).automaticCount).toBe(1);
  await bindings.DB.prepare(
    "UPDATE jobs SET status='completed' WHERE challenge_id=?",
  )
    .bind(id)
    .run();
  await bindings.DB.prepare(
    "UPDATE companion_context SET last_automatic_at=NULL WHERE challenge_id=?",
  )
    .bind(id)
    .run();
  await expect(
    requestHelp(bindings, a, id, crypto.randomUUID(), input(context)),
  ).rejects.toMatchObject({ code: "help_conflict" });
});
it("context updates replay and reject competing revisions; Solo invalidates captures", async () => {
  const { a, id, context } = await fixture(),
    command = crypto.randomUUID();
  const change = {
    revision: context.revision,
    operation: "mode",
    mode: "solo",
  };
  const first = await updateContext(bindings, a, id, command, change);
  expect((await updateContext(bindings, a, id, command, change)).revision).toBe(
    first.revision,
  );
  await expect(
    updateContext(bindings, a, id, crypto.randomUUID(), change),
  ).rejects.toMatchObject({ code: "context_conflict" });
  await expect(
    requestHelp(bindings, a, id, crypto.randomUUID(), input(context)),
  ).rejects.toMatchObject({ code: "context_conflict" });
});
it("normalization does not rearm cosmetic edits but actual reversions form a new cycle", async () => {
  const { a, id, context } = await fixture();
  await bindings.DB.prepare(
    "UPDATE sessions SET answer='  ' WHERE challenge_id=?",
  )
    .bind(id)
    .run();
  expect((await contextFor(bindings, a, id)).cycle).toBe(context.cycle);
  await bindings.DB.prepare(
    "UPDATE sessions SET answer='new approach' WHERE challenge_id=?",
  )
    .bind(id)
    .run();
  expect((await contextFor(bindings, a, id)).cycle).not.toBe(context.cycle);
  await bindings.DB.prepare(
    "UPDATE sessions SET answer='' WHERE challenge_id=?",
  )
    .bind(id)
    .run();
  expect((await contextFor(bindings, a, id)).cycle).not.toBe(context.cycle);
});
it("enforces pause, cooldown, budget and rollback capability on the server", async () => {
  const { a, id, context } = await fixture();
  await expect(
    requestHelp(
      { ...bindings, COMPANION_AUTO_ENABLED: "false" },
      a,
      id,
      crypto.randomUUID(),
      input(context),
    ),
  ).rejects.toMatchObject({ code: "automatic_disabled" });
  await bindings.DB.prepare(
    "UPDATE companion_context SET last_automatic_at=? WHERE challenge_id=?",
  )
    .bind(new Date().toISOString(), id)
    .run();
  await expect(
    requestHelp(bindings, a, id, crypto.randomUUID(), input(context)),
  ).rejects.toMatchObject({ code: "automatic_limit" });
  await bindings.DB.prepare(
    "UPDATE companion_context SET automatic_count=6,last_automatic_at=NULL WHERE challenge_id=?",
  )
    .bind(id)
    .run();
  await expect(
    requestHelp(bindings, a, id, crypto.randomUUID(), input(context)),
  ).rejects.toMatchObject({ code: "automatic_limit" });
});
it("receipts are account scoped, idempotent and frozen with completion; stale completion cannot deliver", async () => {
  const { a, id, context } = await fixture(),
    other = await fixture();
  const job = await requestHelp(
    bindings,
    a,
    id,
    crypto.randomUUID(),
    input(context),
  );
  const receipt = {
    id: crypto.randomUUID(),
    helpId: job.id,
    disposition: "shown",
  };
  await expect(
    receive(bindings, other.a, id, { receipts: [receipt] }),
  ).rejects.toMatchObject({ code: "not_found" });
  await expect(
    complete(
      bindings,
      a,
      id,
      crypto.randomUUID(),
      "answer",
      9,
      await settingsFor(bindings, a),
      [receipt],
    ),
  ).rejects.toMatchObject({ code: "revision_conflict" });
  expect(
    await bindings.DB.prepare("SELECT id FROM companion_receipts WHERE id=?")
      .bind(receipt.id)
      .first(),
  ).toBeNull();
  await complete(
    bindings,
    a,
    id,
    crypto.randomUUID(),
    "answer",
    0,
    await settingsFor(bindings, a),
    [receipt],
  );
  await receive(bindings, a, id, { receipts: [receipt] });
  const frozen = await bindings.DB.prepare(
    "SELECT data FROM completion_context WHERE challenge_id=?",
  )
    .bind(id)
    .first<{ data: string }>();
  expect(JSON.parse(frozen!.data).deliveryReceipts).toEqual([
    { helpId: job.id, disposition: "shown" },
  ]);
  await receive(bindings, a, id, {
    receipts: [
      { ...receipt, id: crypto.randomUUID(), disposition: "dismissed" },
    ],
  });
  expect(
    (
      await bindings.DB.prepare(
        "SELECT * FROM companion_receipts WHERE challenge_id=?",
      )
        .bind(id)
        .all()
    ).results,
  ).toHaveLength(1);
});
it("serializes receipt/completion races into a consistent frozen exposure record", async () => {
  const { a, id, context } = await fixture();
  const job = await requestHelp(
    bindings,
    a,
    id,
    crypto.randomUUID(),
    input(context),
  );
  const receipt = {
    id: crypto.randomUUID(),
    helpId: job.id,
    disposition: "uncertain",
  };
  await Promise.all([
    receive(bindings, a, id, { receipts: [receipt] }),
    complete(
      bindings,
      a,
      id,
      crypto.randomUUID(),
      "A final answer",
      0,
      await settingsFor(bindings, a),
      [receipt],
    ),
  ]);
  const frozen = await bindings.DB.prepare(
    "SELECT data FROM completion_context WHERE challenge_id=?",
  )
    .bind(id)
    .first<{ data: string }>();
  const rows = await bindings.DB.prepare(
    "SELECT help_id AS helpId,disposition FROM companion_receipts WHERE challenge_id=?",
  )
    .bind(id)
    .all();
  expect(JSON.parse(frozen!.data).deliveryReceipts).toEqual(rows.results);
  expect(rows.results).toHaveLength(1);
});
it("restores checked cycles across devices, and pausing disables automatic work", async () => {
  const { a, id, context } = await fixture();
  await requestHelp(bindings, a, id, crypto.randomUUID(), input(context));
  expect((await contextFor(bindings, a, id)).cycleConsumed).toBe(true);
  const { a: b, id: other, context: fresh } = await fixture();
  const paused = await updateContext(bindings, b, other, crypto.randomUUID(), {
    revision: fresh.revision,
    operation: "pause",
    paused: true,
  });
  await expect(
    requestHelp(bindings, b, other, crypto.randomUUID(), input(paused)),
  ).rejects.toMatchObject({ code: "automatic_disabled" });
});
