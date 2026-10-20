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
const access = async (subject: string) => ((await (await request("bootstrap", subject)).json()) as { practice: { plan: string; freeReps: boolean; available: boolean; nextFreeRepAt: string | null; remaining?: number; limit?: number; resetsAt?: string } }).practice;
const utcMidnight = () => { const d = new Date(); d.setUTCHours(24, 0, 0, 0); return d.toISOString(); };
const generations = (account: string) => bindings.DB.prepare("SELECT id,status,input FROM jobs WHERE account_id=? AND kind='generate' ORDER BY created_at").bind(account).all<{ id: string; status: string; input: string }>();
/** Completed free reps from earlier today; each carries its own stamp. */
async function spentToday(account: string, n: number) {
  for (let i = 0; i < n; i++) {
    const at = new Date(Date.now() - 60_000 - i * 1000).toISOString();
    await bindings.DB.prepare("INSERT INTO challenges(id,account_id,lifecycle,data,created_at,available_at,completed_at) VALUES(?,?,'completed',?,?,?,?)")
      .bind(crypto.randomUUID(), account, JSON.stringify({ title: "Queue", prompt: "Design a reliable job queue for email.", topic: "System design", freeRepAt: at }), at, at, at).run();
  }
}
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
    expect(await access(subject)).toEqual({ plan: "pro", freeReps: false, available: true, nextFreeRepAt: null });
    expect((await prepare(subject)).status).toBe(202);
    expect(JSON.parse((await generations(id)).results[0].input).freeRepAt).toBeUndefined();
  } finally { bindings.PRACTICE_GATE = previous; }
});

it("spends free reps as questions are prepared and blocks the fourth until UTC midnight", async () => {
  const { subject, id } = await person();
  expect(await access(subject)).toEqual({ plan: "free", freeReps: true, available: true, nextFreeRepAt: null, remaining: 3, limit: 3, resetsAt: utcMidnight() });
  const stamps: string[] = [];
  for (let rep = 0; rep < 3; rep++) {
    const prepared = await prepare(subject);
    expect(prepared.status).toBe(202);
    const job = (await generations(id)).results.find(j => j.status === "pending")!;
    const stamp = JSON.parse(job.input).freeRepAt as string;
    expect(stamp).toBeTruthy();
    stamps.push(stamp);
    // The preparation finishing is the rep, not starting it.
    await bindings.DB.prepare("UPDATE jobs SET status='completed' WHERE id=?").bind(job.id).run();
    await readyQuestion(id, { freeRepAt: stamp });
    await bindings.DB.prepare("UPDATE challenges SET lifecycle='completed' WHERE account_id=?").bind(id).run();
    expect((await access(subject)).remaining).toBe(2 - rep);
  }
  const blocked = await prepare(subject);
  expect(blocked.status).toBe(402);
  expect(await blocked.json()).toMatchObject({ error: { code: "practice_gate" } });
  const later = await access(subject);
  expect(later).toMatchObject({ available: false, remaining: 0, nextFreeRepAt: utcMidnight() });
  // Yesterday's reps don't count today.
  await bindings.DB.prepare("UPDATE challenges SET data=json_set(data,'$.freeRepAt',?) WHERE account_id=? AND json_extract(data,'$.freeRepAt')=?").bind(new Date(Date.now() - 86_400_000).toISOString(), id, stamps[0]).run();
  expect((await access(subject)).remaining).toBe(1);
  expect((await prepare(subject)).status).toBe(202);
});

it("honours a configured daily rep count", async () => {
  const { subject, id } = await person();
  bindings.FREE_REPS_PER_DAY = "1";
  try {
    expect((await access(subject)).limit).toBe(1);
    expect((await prepare(subject)).status).toBe(202);
    await bindings.DB.prepare("UPDATE jobs SET status='completed' WHERE account_id=?").bind(id).run();
    await spentToday(id, 1);
    expect((await prepare(subject)).status).toBe(402);
  } finally { bindings.FREE_REPS_PER_DAY = undefined; }
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
  expect((await access(subject)).remaining).toBe(2);
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
  // A swap shares its rep's stamp, so the original and its replacement count once.
  expect((await access(subject)).remaining).toBe(2);
  await spentToday(id, 2);
  expect((await access(subject)).remaining).toBe(0);
  expect((await prepare(subject, { replaceId: swapped })).status).toBe(402);
});

it("prepares one question when two preparations race for the last free rep", async () => {
  const { subject, id } = await person();
  await spentToday(id, 2);
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

it("gates starting a Library question once today's free reps are spent", async () => {
  const { subject, id } = await person();
  await spentToday(id, 3);
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

it("caps follow-ups and nudges inside a free rep only", async () => {
  const turns = (kind: string, n: number) => Array.from({ length: n }, () => ({ kind }));
  const data = { freeRepAt: new Date().toISOString() };
  const { id } = await person();
  await expect(freeRepLimit(bindings, id, data, "answer", turns("answer", 7))).resolves.toBeUndefined();
  await expect(freeRepLimit(bindings, id, data, "answer", [...turns("answer", 6), ...turns("clarification", 2)])).rejects.toThrow(/every follow-up/);
  await expect(freeRepLimit(bindings, id, data, "hint", [...turns("hint", 1), ...turns("answer", 3)])).resolves.toBeUndefined();
  await expect(freeRepLimit(bindings, id, data, "example", [...turns("hint", 1), ...turns("example", 1)])).rejects.toThrow(/nudges/);
  await expect(freeRepLimit({ ...bindings, FREE_REP_NUDGES: "5" }, id, data, "hint", turns("hint", 3))).resolves.toBeUndefined();
  await expect(freeRepLimit(bindings, id, {}, "answer", turns("answer", 30))).resolves.toBeUndefined();
  // Going Pro mid-rep lifts the budget.
  await bindings.DB.prepare("INSERT INTO entitlements(original_transaction_id,account_id,product_id,environment,status,active_until,signed_at,created_at,updated_at) VALUES(?,?,?,?,?,?,?,?,?)")
    .bind(crypto.randomUUID(), id, "dawi.drillbit.pro.monthly", "Sandbox", "active", new Date(Date.now() + 86_400_000).toISOString(), "now", "now", "now").run();
  await expect(freeRepLimit(bindings, id, data, "answer", turns("answer", 30))).resolves.toBeUndefined();
  expect(await access((await bindings.DB.prepare("SELECT subject FROM accounts WHERE id=?").bind(id).first<{ subject: string }>())!.subject)).toMatchObject({ plan: "pro", freeReps: false });
});
