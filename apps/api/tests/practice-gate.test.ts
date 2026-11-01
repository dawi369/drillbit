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
    .bind(crypto.randomUUID(), id, "dawi.drillbit.pro.weekly", "Sandbox", "active", new Date(Date.now() + 86_400_000).toISOString(), "now", "now", "now").run();
  await expect(freeRepLimit(bindings, id, data, "answer", turns("answer", 30))).resolves.toBeUndefined();
  expect(await access((await bindings.DB.prepare("SELECT subject FROM accounts WHERE id=?").bind(id).first<{ subject: string }>())!.subject)).toMatchObject({ plan: "pro", freeReps: false });
});

it("gives lifetime free reps that never refill and stay spent when their question is deleted", async () => {
  const { subject, id } = await person();
  bindings.FREE_REPS_LIFETIME = "2";
  try {
    expect(await access(subject)).toMatchObject({ plan: "free", freeReps: true, available: true, remaining: 2, limit: 2, resetsAt: null, lifetime: true });
    // Two reps from days ago still count: lifetime reps don't come back at midnight.
    for (let i = 0; i < 2; i++) {
      const at = new Date(Date.now() - (3 + i) * 86_400_000).toISOString();
      await bindings.DB.prepare("INSERT INTO challenges(id,account_id,lifecycle,data,created_at,available_at,completed_at) VALUES(?,?,'completed',?,?,?,?)")
        .bind(`lifetime-${id}-${i}`, id, JSON.stringify({ title: "Queue", prompt: "Design a reliable job queue for email.", topic: "System design", freeRepAt: at }), at, at, at).run();
    }
    expect(await access(subject)).toMatchObject({ available: false, remaining: 0, nextFreeRepAt: null, lifetime: true });
    const blocked = await prepare(subject);
    expect(blocked.status).toBe(402);
    expect(await blocked.json()).toMatchObject({ error: { code: "practice_gate", message: "That’s your free reps. Go Pro to keep practising." } });
    // Deleting a finished free rep doesn't hand it back.
    expect((await request(`challenges/lifetime-${id}-0`, subject, "DELETE")).status).toBe(200);
    expect(await access(subject)).toMatchObject({ available: false, remaining: 0 });
    expect((await prepare(subject)).status).toBe(402);
  } finally { bindings.FREE_REPS_LIFETIME = undefined; }
});

/** User messages on a challenge: typed answers, and spoken utterances in one voice session. */
async function messages(account: string, challenge: string, typed: number, spoken = 0, at = new Date().toISOString()) {
  let ordinal = 0;
  const turn = async (kind: string) => {
    const id = crypto.randomUUID();
    await bindings.DB.batch([
      bindings.DB.prepare("INSERT INTO jobs(id,account_id,challenge_id,kind,status,input,created_at,updated_at) VALUES(?,?,?,'interview','completed','{}',?,?)").bind(id, account, challenge, at, at),
      bindings.DB.prepare("INSERT INTO interview_turns(id,challenge_id,ordinal,kind,prompt,text,job_id,created_at) VALUES(?,?,?,?,'original','A durable queue.',?,?)").bind(id, challenge, ordinal++, kind, id, at),
    ]);
    return id;
  };
  for (let i = 0; i < typed; i++) await turn("answer");
  if (spoken) {
    const session = await turn("voice");
    await bindings.DB.prepare("INSERT INTO voice_sessions(id,account_id,challenge_id,provider_id,status,created_at,expires_at,finalized) VALUES(?,?,?,'live','closed',?,?,1)").bind(session, account, challenge, at, at).run();
    for (let i = 0; i < spoken; i++)
      await bindings.DB.prepare("INSERT INTO voice_fragments(session_id,id,sequence,speaker,text,start_ms,end_ms) VALUES(?,?,?,?,?,?,?)")
        .bind(session, `u${i}`, i * 2, "user", "Retries need a key.", i * 1000, i * 1000 + 500).run();
    // The interviewer talking doesn't make it practice.
    await bindings.DB.prepare("INSERT INTO voice_fragments(session_id,id,sequence,speaker,text,start_ms,end_ms) VALUES(?,'a0',1,'assistant','Go on.',0,1)").bind(session).run();
  }
}
const skip = (subject: string, challenge: string) => request(`challenges/${challenge}/skip`, subject, "POST");

it("gives a free rep back only when it's skipped before the user's first message, typed or spoken", async () => {
  const { subject, id } = await person();
  bindings.FREE_REPS_LIFETIME = "2";
  try {
    const untouched = await readyQuestion(id, { freeRepAt: new Date(Date.now() - 4000).toISOString() });
    expect((await access(subject)).remaining).toBe(1);
    expect((await skip(subject, untouched)).status).toBe(200);
    expect(await access(subject)).toMatchObject({ available: true, remaining: 2 });

    // One typed message already earned an interviewer reply, so the rep is spent even skipped.
    const oneLine = await readyQuestion(id, { freeRepAt: new Date(Date.now() - 3000).toISOString() });
    await messages(id, oneLine, 1);
    await skip(subject, oneLine);
    expect((await access(subject)).remaining).toBe(1);
    // So is one spoken utterance; the interviewer talking alone doesn't count.
    const spoken = await readyQuestion(id, { freeRepAt: new Date(Date.now() - 1000).toISOString() });
    await messages(id, spoken, 0, 1);
    await skip(subject, spoken);
    expect((await access(subject)).remaining).toBe(0);
    expect((await prepare(subject)).status).toBe(402);
  } finally { bindings.FREE_REPS_LIFETIME = undefined; }
});

it("refunds a swapped free rep only when its replacement is abandoned unused too, and never records a deleted unused one", async () => {
  const { subject, id } = await person();
  bindings.FREE_REPS_LIFETIME = "1";
  try {
    const stamp = new Date().toISOString();
    const original = await readyQuestion(id, { freeRepAt: stamp });
    await bindings.DB.prepare("UPDATE challenges SET lifecycle='expired' WHERE id=?").bind(original).run();
    const swapped = await readyQuestion(id, { freeRepAt: stamp, swapped: true });
    expect((await access(subject)).remaining).toBe(0);
    await skip(subject, swapped);
    expect((await access(subject)).remaining).toBe(1);
    // Deleting the abandoned question from Library doesn't spend the rep after all.
    expect((await request("challenges/" + swapped, subject, "DELETE")).status).toBe(200);
    expect((await access(subject)).remaining).toBe(1);
    expect((await bindings.DB.prepare("SELECT COUNT(*) n FROM spent_free_reps WHERE account_id=?").bind(id).first<{ n: number }>())!.n).toBe(0);
    // A finished rep is spent whatever its message count, and stays spent when deleted.
    const finished = await readyQuestion(id, { freeRepAt: new Date(Date.now() + 1000).toISOString() });
    await bindings.DB.prepare("UPDATE challenges SET lifecycle='completed' WHERE id=?").bind(finished).run();
    await request("challenges/" + finished, subject, "DELETE");
    expect((await access(subject)).remaining).toBe(0);
  } finally { bindings.FREE_REPS_LIFETIME = undefined; }
});

/** A Pro account with `practised` reps (two messages each) today. */
async function proWith(practised: number, at = new Date().toISOString()) {
  const who = await person();
  await bindings.DB.prepare("INSERT INTO entitlements(original_transaction_id,account_id,product_id,environment,status,active_until,signed_at,created_at,updated_at) VALUES(?,?,?,?,?,?,?,?,?)")
    .bind(crypto.randomUUID(), who.id, "dawi.drillbit.pro.yearly", "Sandbox", "active", new Date(Date.now() + 86_400_000).toISOString(), "now", "now", "now").run();
  for (let i = 0; i < practised; i++) {
    const challenge = crypto.randomUUID();
    await bindings.DB.prepare("INSERT INTO challenges(id,account_id,lifecycle,data,created_at,available_at,completed_at) VALUES(?,?,'completed',?,?,?,?)")
      .bind(challenge, who.id, JSON.stringify({ title: "Queue", prompt: "Design a reliable job queue for email.", topic: "System design" }), at, at, at).run();
    await messages(who.id, challenge, 2, 0, at);
  }
  return who;
}

it("stops a Pro account starting an eleventh practised rep today, counting only reps with two messages", async () => {
  const nine = await proWith(9);
  // Browsing doesn't count: a question with one message, and a skipped one with none.
  const browsed = crypto.randomUUID();
  await bindings.DB.prepare("INSERT INTO challenges(id,account_id,lifecycle,data,created_at,available_at) VALUES(?,?,'skipped','{}',?,?)").bind(browsed, nine.id, new Date().toISOString(), new Date().toISOString()).run();
  await messages(nine.id, browsed, 1);
  expect((await prepare(nine.subject)).status).toBe(202);

  const ten = await proWith(10);
  const blocked = await prepare(ten.subject);
  expect(blocked.status).toBe(429);
  expect(await blocked.json()).toMatchObject({ error: { code: "practice_limit", message: "That’s 10 reps today, which is plenty. More tomorrow." } });
  // Library and moment retries start reps too.
  const question = crypto.randomUUID();
  await bindings.DB.prepare("INSERT INTO questions(id,account_id,data,created_at,eligibility_updated_at) VALUES(?,?,?,?,?)")
    .bind(question, ten.id, JSON.stringify({ title: "Cache", prompt: "Design a read-through cache for profiles.", topic: "System design" }), "now", "now").run();
  expect((await request("questions/" + question + "/start", ten.subject, "POST", undefined, crypto.randomUUID())).status).toBe(429);
  // Swapping a question already prepared isn't a new rep.
  const ready = await readyQuestion(ten.id, {});
  expect((await prepare(ten.subject, { replaceId: ready })).status).toBe(202);
  // Developers are counted, never stopped.
  bindings.DEVELOPER_ACCOUNTS = ten.id;
  try { await bindings.DB.prepare("DELETE FROM jobs WHERE account_id=? AND kind='generate'").bind(ten.id).run(); await bindings.DB.prepare("DELETE FROM challenges WHERE id=?").bind(ready).run(); expect((await prepare(ten.subject)).status).toBe(202); }
  finally { bindings.DEVELOPER_ACCOUNTS = undefined; }
});

it("resets Pro's practised reps at UTC midnight and honours a configured count", async () => {
  const yesterday = await proWith(10, new Date(Date.now() - 86_400_000).toISOString());
  expect((await prepare(yesterday.subject)).status).toBe(202);
  const three = await proWith(3);
  bindings.PRO_REPS_PER_DAY = "3";
  try { expect((await prepare(three.subject)).status).toBe(429); }
  finally { bindings.PRO_REPS_PER_DAY = undefined; }
});

it("prepares one question when a Pro account races for its last practised rep", async () => {
  const { subject, id } = await proWith(9);
  const [a, b] = await Promise.all([prepare(subject), prepare(subject)]);
  expect([a.status, b.status]).toEqual([202, 202]);
  expect((await generations(id)).results).toHaveLength(1);
});

it("caps Pro question writing at 20 a day with its own message", async () => {
  const { subject, id } = await proWith(0);
  await bindings.DB.prepare("INSERT INTO usage(account_id,day,kind,count) VALUES(?,?,'generate',20)").bind(id, new Date().toISOString().slice(0, 10)).run();
  const blocked = await prepare(subject);
  expect(blocked.status).toBe(429);
  expect(await blocked.json()).toMatchObject({ error: { code: "usage_limit", message: "That’s a lot of new questions for one day. Practise one you’ve got, or more tomorrow." } });
});
