import { env } from "cloudflare:test";
import { beforeAll, describe, it, expect } from "vitest";
import { complete, accountFor, settingsFor } from "../src/store";
import { settingsSchema, nextDaily } from "../src/domain";
import { initializeDatabase } from "./migrations";
import { encrypt, decrypt } from "../src/platform";

const bindings = {
  ...env,
  JOBS: { create: async () => ({ id: "test" }) },
} as unknown as import("../src/platform").Env;
beforeAll(async () => {
  await initializeDatabase(bindings.DB);
});
async function fixture() {
  const account = await accountFor(bindings, crypto.randomUUID());
  const id = crypto.randomUUID();
  await bindings.DB.prepare("UPDATE accounts SET status='active' WHERE id=?")
    .bind(account.id)
    .run();
  await bindings.DB.prepare(
    "INSERT INTO challenges(id,account_id,lifecycle,data,created_at,available_at) VALUES(?,?,'in_progress','{}','2026-09-08','2026-09-08')",
  )
    .bind(id, account.id)
    .run();
  await bindings.DB.prepare(
    "INSERT INTO sessions(challenge_id,answer,revision,updated_at) VALUES(?,'original',2,'2026-09-08')",
  )
    .bind(id)
    .run();
  return { account, id };
}
describe("D1 lifecycle", () => {
  it("rejects stale completion without partially mutating the answer or creating a job", async () => {
    const { account, id } = await fixture();
    await expect(
      complete(
        bindings,
        account.id,
        id,
        crypto.randomUUID(),
        "stale answer",
        1,
        await settingsFor(bindings, account.id),
      ),
    ).rejects.toMatchObject({ code: "revision_conflict" });
    expect(
      await bindings.DB.prepare(
        "SELECT answer,revision FROM sessions WHERE challenge_id=?",
      )
        .bind(id)
        .first(),
    ).toEqual({ answer: "original", revision: 2 });
    expect(
      await bindings.DB.prepare("SELECT id FROM jobs WHERE challenge_id=?")
        .bind(id)
        .first(),
    ).toBeNull();
  });
  it("completion retries persist exactly one job and one revision", async () => {
    const { account, id } = await fixture(),
      command = crypto.randomUUID(),
      settings = await settingsFor(bindings, account.id);
    await complete(bindings, account.id, id, command, "final", 2, settings);
    await complete(bindings, account.id, id, command, "final", 2, settings);
    expect(
      await bindings.DB.prepare(
        "SELECT revision FROM sessions WHERE challenge_id=?",
      )
        .bind(id)
        .first(),
    ).toEqual({ revision: 3 });
    expect(
      (
        await bindings.DB.prepare("SELECT id FROM jobs WHERE challenge_id=?")
          .bind(id)
          .all()
      ).results,
    ).toHaveLength(1);
  });
  it("does not allow another account to complete a session", async () => {
    const { id } = await fixture();
    await expect(
      complete(
        bindings,
        "different",
        id,
        crypto.randomUUID(),
        "answer",
        2,
        settingsSchema.parse({}),
      ),
    ).rejects.toMatchObject({ code: "not_found" });
  });
  it("enforces one active challenge in SQL", async () => {
    const { account } = await fixture();
    await expect(
      bindings.DB.prepare(
        "INSERT INTO challenges(id,account_id,lifecycle,data,created_at,available_at) VALUES(?,?,'ready','{}','now','now')",
      )
        .bind(crypto.randomUUID(), account.id)
        .run(),
    ).rejects.toThrow();
  });
});
describe("scheduling", () => {
  it("keeps the local morning after daylight saving changes", () => {
    expect(
      nextDaily(
        settingsSchema.parse({ timezone: "Europe/Prague", dailyMinutes: 540 }),
        new Date("2026-03-28T09:00:00Z"),
      ),
    ).toBe("2026-03-29T07:00:00.000Z");
  });
  it("rolls through autumn without adding exactly 24 hours", () => {
    expect(
      nextDaily(
        settingsSchema.parse({ timezone: "Europe/Prague", dailyMinutes: 540 }),
        new Date("2026-10-24T09:00:00Z"),
      ),
    ).toBe("2026-10-25T08:00:00.000Z");
  });
});

describe("credentials and quotas", () => {
  it("binds encrypted credentials to their owning account and detects tampering", async () => {
    const secure = {
      ...bindings,
      CREDENTIAL_KEY: btoa(
        String.fromCharCode(...crypto.getRandomValues(new Uint8Array(32))),
      ),
    };
    const encrypted = await encrypt(
      secure,
      "a-provider-key",
      "account:credential",
    );
    expect(await decrypt(secure, encrypted, "account:credential")).toBe(
      "a-provider-key",
    );
    await expect(
      decrypt(secure, encrypted, "other:credential"),
    ).rejects.toThrow();
    expect(encrypted).not.toContain("a-provider-key");
  });
});
describe("open signup", () => {
  const open = { ...bindings, OPEN_SIGNUP: "true" } as typeof bindings;
  const status = (id: string) =>
    bindings.DB.prepare("SELECT status FROM accounts WHERE id=?").bind(id).first<{ status: string }>().then(r => r?.status);
  it("keeps new accounts behind the invite while closed", async () => {
    const account = await accountFor(bindings, crypto.randomUUID());
    expect(account.status).toBe("invited");
  });
  it("activates new accounts and lifts ones still waiting on an invite", async () => {
    expect((await accountFor(open, crypto.randomUUID())).status).toBe("active");
    const subject = crypto.randomUUID();
    const waiting = await accountFor(bindings, subject);
    expect(waiting.status).toBe("invited");
    expect((await accountFor(open, subject)).status).toBe("active");
    expect(await status(waiting.id)).toBe("active");
  });
  it("never revives an account being deleted, even under concurrent sign-ins", async () => {
    const subject = crypto.randomUUID();
    const account = await accountFor(open, subject);
    await bindings.DB.prepare("UPDATE accounts SET status='deleting' WHERE id=?").bind(account.id).run();
    const results = await Promise.allSettled([accountFor(open, subject), accountFor(open, subject), accountFor(bindings, subject)]);
    expect(results.every(r => r.status === "rejected" && (r.reason as { code?: string }).code === "account_unavailable")).toBe(true);
    expect(await status(account.id)).toBe("deleting");
  });
  it("creates exactly one account when the first sign-ins race", async () => {
    const subject = crypto.randomUUID();
    const accounts = await Promise.all(Array.from({ length: 5 }, () => accountFor(open, subject)));
    expect(new Set(accounts.map(a => a.id)).size).toBe(1);
    const { n } = (await bindings.DB.prepare("SELECT COUNT(*) n FROM accounts WHERE subject=?").bind(subject).first<{ n: number }>())!;
    expect(n).toBe(1);
  });
});
