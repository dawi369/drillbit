import { createExecutionContext, env, fetchMock, waitOnExecutionContext } from "cloudflare:test";
import { SignJWT, exportJWK, generateKeyPair } from "jose";
import { afterAll, beforeAll, expect, it } from "vitest";
import { wire } from "../../../packages/contracts/wire";
import { dailyQuestion } from "../src/daily";
import { app } from "../src/index";
import type { Env } from "../src/platform";
import { freeRepLimit } from "../src/practice-gate";
import { accountFor } from "../src/store";
import { initializeDatabase } from "./migrations";

const bindings = {
  ...env,
  JOBS: { create: async () => ({ id: "test" }) },
  CLERK_ISSUER: "https://auth.drillbit.test",
  CLERK_AUDIENCE: "drillbit",
  // Preparations stay pending so each test controls how they end.
  INTERACTIVE_INLINE_ENABLED: "false",
  PRACTICE_GATE: "true",
} as unknown as Env;
let key: CryptoKey;
beforeAll(async () => {
  await initializeDatabase(bindings.DB);
  const pair = await generateKeyPair("RS256");
  key = pair.privateKey;
  fetchMock.activate();
  fetchMock.disableNetConnect();
  fetchMock.get("https://auth.drillbit.test").intercept({ path: "/.well-known/jwks.json" })
    .reply(200, { keys: [{ ...(await exportJWK(pair.publicKey)), kid: "test", alg: "RS256" }] }).persist();
});
afterAll(() => fetchMock.deactivate());

async function request(path: string, subject: string, method = "GET", body?: unknown, command?: string) {
  const token = await new SignJWT({}).setProtectedHeader({ alg: "RS256", kid: "test" }).setSubject(subject)
    .setIssuer(bindings.CLERK_ISSUER).setAudience("drillbit").setIssuedAt().setExpirationTime("5m").sign(key);
  const headers: Record<string, string> = { "Content-Type": "application/json", Authorization: "Bearer " + token };
  if (command) headers["Idempotency-Key"] = command;
  const ctx = createExecutionContext();
  const response = await app.fetch(new Request("https://api.test/v1/" + path, { method, headers, body: body ? JSON.stringify(body) : undefined }), bindings, ctx);
  await waitOnExecutionContext(ctx);
  return response;
}
async function person() {
  const subject = crypto.randomUUID();
  const account = await accountFor(bindings, subject);
  await bindings.DB.prepare("UPDATE accounts SET status='active' WHERE id=?").bind(account.id).run();
  return { subject, id: account.id };
}
const prepare = (subject: string, body: object = {}) => request("challenges", subject, "POST", body, crypto.randomUUID());
const access = async (subject: string) => ((await (await request("bootstrap", subject)).json()) as { practice: { freeReps: boolean; available: boolean; nextFreeRepAt: string | null } }).practice;
const generations = (account: string) => bindings.DB.prepare("SELECT id,status,input FROM jobs WHERE account_id=? AND kind='generate' ORDER BY created_at").bind(account).all<{ id: string; status: string; input: string }>();
async function readyQuestion(account: string, data: object) {
  const id = crypto.randomUUID();
  await bindings.DB.prepare("INSERT INTO challenges(id,account_id,lifecycle,data,created_at,available_at) VALUES(?,?,'ready',?,?,?)")
    .bind(id, account, JSON.stringify({ title: "Queue", prompt: "Design a reliable job queue for email.", topic: "System design", ...data }), new Date().toISOString(), new Date().toISOString()).run();
  await bindings.DB.prepare("INSERT INTO sessions(challenge_id,updated_at) VALUES(?,?)").bind(id, new Date().toISOString()).run();
  return id;
}

it("leaves practice unlimited while the gate is off", async () => {
  const { subject, id } = await person();
  const previous = bindings.PRACTICE_GATE;
  bindings.PRACTICE_GATE = undefined;
  try {
    expect(await access(subject)).toEqual({ freeReps: false, available: true, nextFreeRepAt: null });
    expect((await prepare(subject)).status).toBe(202);
    expect(JSON.parse((await generations(id)).results[0].input).freeRepAt).toBeUndefined();
  } finally { bindings.PRACTICE_GATE = previous; }
});

it("spends one free rep when a question is prepared and blocks the next until seven days pass", async () => {
  const { subject, id } = await person();
  expect(await access(subject)).toEqual({ freeReps: true, available: true, nextFreeRepAt: null });
  const first = await prepare(subject);
  expect(first.status).toBe(202);
  const job = (await generations(id)).results[0];
  expect(JSON.parse(job.input).freeRepAt).toBeTruthy();
  // The preparation finishing is the rep, not starting it.
  await bindings.DB.prepare("UPDATE jobs SET status='completed' WHERE id=?").bind(job.id).run();
  await readyQuestion(id, { freeRepAt: JSON.parse(job.input).freeRepAt });
  await bindings.DB.prepare("UPDATE challenges SET lifecycle='completed' WHERE account_id=?").bind(id).run();
  const blocked = await prepare(subject);
  expect(blocked.status).toBe(402);
  expect(await blocked.json()).toMatchObject({ error: { code: "practice_gate" } });
  const later = await access(subject);
  expect(later.available).toBe(false);
  expect(Date.parse(later.nextFreeRepAt!) - Date.parse(JSON.parse(job.input).freeRepAt)).toBe(7 * 86_400_000);
  // Seven days on, the free rep is back.
  await bindings.DB.prepare("UPDATE challenges SET data=json_set(data,'$.freeRepAt',?) WHERE account_id=?").bind(new Date(Date.now() - 7 * 86_400_000 - 1000).toISOString(), id).run();
  expect((await access(subject)).available).toBe(true);
  expect((await prepare(subject)).status).toBe(202);
});

it("never charges a failed preparation and retries it as a fresh rep", async () => {
  const { subject, id } = await person();
  expect((await prepare(subject)).status).toBe(202);
  const failed = (await generations(id)).results[0];
  await bindings.DB.prepare("UPDATE jobs SET status='failed' WHERE id=?").bind(failed.id).run();
  expect((await access(subject)).available).toBe(true);
  const retried = await request("jobs/" + failed.id + "/retry", subject, "POST", undefined, crypto.randomUUID());
  expect(retried.status).toBe(202);
  const fresh = (await generations(id)).results.find(j => j.status === "pending")!;
  expect(Date.parse(JSON.parse(fresh.input).freeRepAt)).toBeGreaterThan(Date.parse(JSON.parse(failed.input).freeRepAt));
  expect((await access(subject)).available).toBe(false);
});

it("includes exactly one swap of a free rep's question", async () => {
  const { subject, id } = await person();
  const spentAt = new Date().toISOString();
  const original = await readyQuestion(id, { freeRepAt: spentAt });
  const swap = await prepare(subject, { replaceId: original });
  expect(swap.status).toBe(202);
  const job = (await generations(id)).results[0];
  expect(JSON.parse(job.input)).toMatchObject({ freeRepAt: spentAt, swapped: true });
  await bindings.DB.batch([
    bindings.DB.prepare("UPDATE jobs SET status='completed' WHERE id=?").bind(job.id),
    bindings.DB.prepare("UPDATE challenges SET lifecycle='expired' WHERE id=?").bind(original),
  ]);
  const swapped = await readyQuestion(id, { freeRepAt: spentAt, swapped: true });
  expect((await prepare(subject, { replaceId: swapped })).status).toBe(402);
});

it("prepares one question when two preparations race for the same free rep", async () => {
  const { subject, id } = await person();
  const [a, b] = await Promise.all([prepare(subject), prepare(subject)]);
  expect([a.status, b.status].sort()).toEqual([202, 202]);
  expect((await generations(id)).results).toHaveLength(1);
  expect((await a.json() as { id: string }).id).toBe((await b.json() as { id: string }).id);
});

it("keeps allowlisted accounts unlimited and never auto-prepares a free account's daily question", async () => {
  const unlimited = await person();
  bindings.PRACTICE_UNLIMITED_ACCOUNTS = "someone-else, " + unlimited.id;
  try {
    expect((await access(unlimited.subject)).freeReps).toBe(false);
    expect((await prepare(unlimited.subject)).status).toBe(202);
    expect(JSON.parse((await generations(unlimited.id)).results[0].input).freeRepAt).toBeUndefined();
  } finally { bindings.PRACTICE_UNLIMITED_ACCOUNTS = undefined; }
  const free = await person();
  expect(await dailyQuestion(bindings, free.id)).not.toHaveProperty("job");
  expect((await generations(free.id)).results).toHaveLength(0);
});

it("gates starting a Library question once the free rep is spent", async () => {
  const { subject, id } = await person();
  await readyQuestion(id, { freeRepAt: new Date().toISOString() });
  await bindings.DB.prepare("UPDATE challenges SET lifecycle='completed' WHERE account_id=?").bind(id).run();
  const question = crypto.randomUUID();
  await bindings.DB.prepare("INSERT INTO questions(id,account_id,data,created_at,eligibility_updated_at) VALUES(?,?,?,?,?)")
    .bind(question, id, JSON.stringify({ title: "Cache", prompt: "Design a read-through cache for profiles.", topic: "System design" }), "now", "now").run();
  const started = await request("questions/" + question + "/start", subject, "POST", undefined, crypto.randomUUID());
  expect(started.status).toBe(402);
});

it("publishes the opener, free-rep markers and practice access on the wire", async () => {
  const { subject, id } = await person();
  await readyQuestion(id, { opener: "A worker can crash at any point. What should a client be able to rely on?", freeRepAt: new Date().toISOString() });
  const bootstrap = await (await request("bootstrap", subject)).json() as { challenge: { opener?: string } };
  expect(wire.Bootstrap.safeParse(bootstrap).success).toBe(true);
  expect(bootstrap.challenge.opener).toContain("What should a client be able to rely on?");
});

it("caps follow-ups and nudges inside a free rep only", () => {
  const turns = (kind: string, n: number) => Array.from({ length: n }, () => ({ kind }));
  const data = { freeRepAt: new Date().toISOString() };
  expect(() => freeRepLimit(bindings, "a", data, "answer", turns("answer", 7))).not.toThrow();
  expect(() => freeRepLimit(bindings, "a", data, "answer", [...turns("answer", 6), ...turns("clarification", 2)])).toThrow(/every follow-up/);
  expect(() => freeRepLimit(bindings, "a", data, "hint", [...turns("hint", 1), ...turns("answer", 3)])).not.toThrow();
  expect(() => freeRepLimit(bindings, "a", data, "example", [...turns("hint", 1), ...turns("example", 1)])).toThrow(/nudges/);
  expect(() => freeRepLimit({ ...bindings, FREE_REP_NUDGES: "5" }, "a", data, "hint", turns("hint", 3))).not.toThrow();
  expect(() => freeRepLimit(bindings, "a", {}, "answer", turns("answer", 30))).not.toThrow();
});
