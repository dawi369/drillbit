import {
  env,
  fetchMock,
  createExecutionContext,
  waitOnExecutionContext,
} from "cloudflare:test";
import { beforeAll, afterAll, it, expect } from "vitest";
import { SignJWT, generateKeyPair, exportJWK } from "jose";
import { app } from "../src/index";
import { accountFor } from "../src/store";
import { initializeDatabase } from "./migrations";
import { wire } from "../../../packages/contracts/wire";
import type { Env } from "../src/platform";
const bindings = {
  ...env,
  JOBS: { create: async () => ({ id: "test" }) },
  CLERK_ISSUER: "https://auth.drillbit.test",
  CLERK_AUDIENCE: "drillbit",
} as unknown as Env;
let key: CryptoKey;
beforeAll(async () => {
  await initializeDatabase(bindings.DB);
  const pair = await generateKeyPair("RS256");
  key = pair.privateKey;
  const publicKey = await exportJWK(pair.publicKey);
  fetchMock.activate();
  fetchMock.disableNetConnect();
  fetchMock
    .get("https://auth.drillbit.test")
    .intercept({ path: "/.well-known/jwks.json" })
    .reply(200, { keys: [{ ...publicKey, kid: "test", alg: "RS256" }] })
    .persist();
});
afterAll(() => fetchMock.deactivate());
async function token(subject: string, audience = "drillbit") {
  return new SignJWT({})
    .setProtectedHeader({ alg: "RS256", kid: "test" })
    .setSubject(subject)
    .setIssuer(bindings.CLERK_ISSUER)
    .setAudience(audience)
    .setIssuedAt()
    .setExpirationTime("5m")
    .sign(key);
}
async function request(
  path: string,
  subject?: string,
  method = "GET",
  body?: unknown,
  command?: string,
) {
  const ctx = createExecutionContext();
  const headers: Record<string, string> = {
    "Content-Type": "application/json",
  };
  if (subject) headers.Authorization = "Bearer " + (await token(subject));
  if (command) headers["Idempotency-Key"] = command;
  const response = await app.fetch(
    new Request("https://api.test/v1/" + path, {
      method,
      headers,
      body: body ? JSON.stringify(body) : undefined,
    }),
    bindings,
    ctx,
  );
  await waitOnExecutionContext(ctx);
  return response;
}
it("requires authentication and does not expose database internals", async () => {
  const response = await request("bootstrap");
  expect(response.status).toBe(401);
  expect(await response.json()).toMatchObject({
    error: { code: "unauthenticated" },
  });
});
it("blocks product access until an invitation is redeemed", async () => {
  const response = await request("memory", "new-person");
  expect(response.status).toBe(403);
});
it("rejects tokens for another audience", async () => {
  const response = await app.fetch(
    new Request("https://api.test/v1/bootstrap", {
      headers: {
        Authorization: "Bearer " + (await token("person", "other-app")),
      },
    }),
    bindings,
  );
  expect(response.status).toBe(401);
});
it("does not let one account read another challenge", async () => {
  const a = await accountFor(bindings, "alice"),
    b = await accountFor(bindings, "bob");
  await bindings.DB.prepare(
    "UPDATE accounts SET status='active' WHERE id IN (?,?)",
  )
    .bind(a.id, b.id)
    .run();
  const id = crypto.randomUUID();
  await bindings.DB.prepare(
    "INSERT INTO challenges(id,account_id,lifecycle,data,created_at,available_at) VALUES(?,?,'completed','{}','now','now')",
  )
    .bind(id, a.id)
    .run();
  const response = await request("challenges/" + id, "bob");
  expect(response.status).toBe(404);
});

it("publishes a bootstrap matching the cross-platform wire schema", async () => {
  const response = await request("bootstrap", "contract-person");
  expect(response.status).toBe(200);
  expect(wire.Bootstrap.safeParse(await response.json()).success).toBe(true);
});
it("paginates history without repeating sessions and supports topic search", async () => {
  const account = await accountFor(bindings, "history-person");
  await bindings.DB.prepare("UPDATE accounts SET status='active' WHERE id=?")
    .bind(account.id)
    .run();
  await bindings.DB.batch(
    Array.from({ length: 26 }, (_, i) =>
      bindings.DB.prepare(
        "INSERT INTO challenges(id,account_id,lifecycle,data,created_at,available_at,completed_at) VALUES(?,?,'completed',?,?,?,?)",
      ).bind(
        crypto.randomUUID(),
        account.id,
        JSON.stringify({
          title: "Question " + i,
          prompt: "A concrete question with realistic constraints.",
          topic: i === 0 ? "databases" : "networking",
        }),
        "2026-09-08T00:00:00Z",
        "2026-09-08T00:00:00Z",
        "2026-09-08T00:00:00Z",
      ),
    ),
  );
  const first = wire.HistoryPage.parse(
    await (await request("sessions", "history-person")).json(),
  );
  expect(first.sessions).toHaveLength(25);
  expect(first.nextCursor).toBeTruthy();
  const second = wire.HistoryPage.parse(
    await (
      await request(
        "sessions?cursor=" + encodeURIComponent(first.nextCursor!),
        "history-person",
      )
    ).json(),
  );
  expect(second.sessions).toHaveLength(1);
  expect(first.sessions.map((x) => x.id)).not.toContain(second.sessions[0].id);
  expect(second.nextCursor).toBeNull();
  const search = wire.HistoryPage.parse(
    await (await request("sessions?q=databases", "history-person")).json(),
  );
  expect(search.sessions).toHaveLength(1);
});

it("a synced offline draft claims ready work and retries without another revision", async () => {
  const account = await accountFor(bindings, "offline-writer");
  await bindings.DB.prepare("UPDATE accounts SET status='active' WHERE id=?")
    .bind(account.id)
    .run();
  const id = crypto.randomUUID(),
    command = crypto.randomUUID();
  await bindings.DB.batch([
    bindings.DB.prepare(
      "INSERT INTO challenges(id,account_id,lifecycle,data,created_at,available_at) VALUES(?,?,'ready',?,'now','now')",
    ).bind(
      id,
      account.id,
      JSON.stringify({
        title: "Offline",
        prompt: "A concrete realistic question to answer.",
        topic: "Systems",
      }),
    ),
    bindings.DB.prepare(
      "INSERT INTO sessions(challenge_id,updated_at) VALUES(?,'now')",
    ).bind(id),
  ]);
  const first = await request(
    "challenges/" + id + "/draft",
    "offline-writer",
    "PUT",
    { answer: "offline work", revision: 0 },
    command,
  );
  expect(first.status).toBe(200);
  expect(await first.json()).toEqual({ revision: 1 });
  const replay = await request(
    "challenges/" + id + "/draft",
    "offline-writer",
    "PUT",
    { answer: "offline work", revision: 0 },
    command,
  );
  expect(await replay.json()).toEqual({ revision: 1 });
  const current = wire.Challenge.parse(
    await (await request("challenges/" + id, "offline-writer")).json(),
  );
  expect(current.lifecycle).toBe("in_progress");
  expect(current.session?.answer).toBe("offline work");
});

it("serves explicit help and adoption through the authenticated wire contract", async () => {
  const subject = crypto.randomUUID(),
    account = await accountFor(bindings, subject),
    id = crypto.randomUUID();
  await bindings.DB.prepare("UPDATE accounts SET status='active' WHERE id=?")
    .bind(account.id)
    .run();
  await bindings.DB.prepare(
    "INSERT INTO challenges(id,account_id,lifecycle,data,created_at,available_at) VALUES(?,?,'in_progress',?,'now','now')",
  )
    .bind(
      id,
      account.id,
      JSON.stringify({
        title: "Cache",
        prompt: "Design reliable configuration caching.",
        topic: "Systems",
      }),
    )
    .run();
  await bindings.DB.prepare(
    "INSERT INTO sessions(challenge_id,answer,revision,updated_at) VALUES(?,'My draft',0,'now')",
  )
    .bind(id)
    .run();
  const opened = wire.Challenge.parse(
    await (await request("challenges/" + id, subject)).json(),
  );
  expect(opened.help).toEqual([]);
  const command = crypto.randomUUID();
  const response = await request(
    `challenges/${id}/help`,
    subject,
    "POST",
    { kind: "draft", mode: "guided", revision: 0 },
    command,
  );
  expect(response.status).toBe(202);
  expect(wire.Job.parse(await response.json()).id).toBe(command);
  await bindings.DB.prepare("UPDATE jobs SET status='completed' WHERE id=?")
    .bind(command)
    .run();
  await bindings.DB.prepare("INSERT INTO help_results(id,data) VALUES(?,?)")
    .bind(
      command,
      JSON.stringify({
        body: "A suggestion",
        suggestedAnswer: "Suggested wording",
      }),
    )
    .run();
  const adopted = await request(
    `challenges/${id}/adopt`,
    subject,
    "POST",
    { sourceId: command, operation: "append", revision: 0 },
    crypto.randomUUID(),
  );
  expect(adopted.status).toBe(200);
  const current = wire.Challenge.parse(await adopted.json());
  expect(current.session?.answer).toBe("My draft\n\nSuggested wording");
  expect(current.adoptions?.[0].source_id).toBe(command);
});

it("preserves engineering level for legacy updates and saves the selected time zone", async () => {
  const account = await accountFor(bindings, "level-owner");
  await bindings.DB.prepare("UPDATE accounts SET status='active' WHERE id=?").bind(account.id).run();
  for (const engineeringLevel of ["intern", "junior", "mid", "senior", "staff", "principal"]) {
    const response = await request("settings", "level-owner", "PUT", { engineeringLevel, timezone: "America/New_York", dailyMinutes: 540 });
    expect(response.status).toBe(200);
    expect(await response.json()).toMatchObject({ engineeringLevel, timezone: "America/New_York" });
  }
  const legacy = await request("settings", "level-owner", "PUT", { difficulty: "easy", timezone: "Asia/Kolkata" });
  expect(await legacy.json()).toMatchObject({ engineeringLevel: "principal", timezone: "Asia/Kolkata" });
  const fresh = await request("bootstrap", "level-owner");
  expect((await fresh.json() as any).settings).toMatchObject({ engineeringLevel: "principal", timezone: "Asia/Kolkata" });
});
it("counts all completed practice independently of the 100-session page and account", async () => {
  const a = await accountFor(bindings, "dashboard-owner");
  const b = await accountFor(bindings, "dashboard-other");
  await bindings.DB.prepare("UPDATE accounts SET status='active' WHERE id IN (?,?)").bind(a.id,b.id).run();
  const now = new Date().toISOString();
  const old = new Date(Date.now()-8*86400000).toISOString();
  await bindings.DB.batch(Array.from({length: 106}, (_,i) => bindings.DB.prepare("INSERT INTO challenges(id,account_id,lifecycle,data,created_at,available_at,completed_at) VALUES(?,?,'completed',?,?,?,?)").bind(crypto.randomUUID(),i === 105 ? b.id : a.id,JSON.stringify({title: "Practice",prompt: "A sufficiently long question prompt",topic:"Backend"}),old,old,i < 3 || i === 105 ? now : old)));
  const response = await request("memory", "dashboard-owner");
  const body = await response.json() as any;
  expect(response.status).toBe(200);
  expect(body.sessions).toHaveLength(100);
  expect(body.statistics).toMatchObject({completed:105,lastSevenDays:3});
  expect(wire.Memory.safeParse(body).success).toBe(true);
});
it("serves revision-checked interview turns through the authenticated public contract",async()=>{
 const subject=crypto.randomUUID(),a=await accountFor(bindings,subject),id=crypto.randomUUID();
 await bindings.DB.prepare("UPDATE accounts SET status='active' WHERE id=?").bind(a.id).run();
 await bindings.DB.prepare("INSERT INTO challenges(id,account_id,lifecycle,data,created_at,available_at) VALUES(?,?,'in_progress',?,'now','now')").bind(id,a.id,JSON.stringify({title:"Queue",prompt:"Design a queue.",topic:"Backend"})).run();
 await bindings.DB.prepare("INSERT INTO sessions(challenge_id,answer,revision,updated_at) VALUES(?,'Durable jobs',0,'now')").bind(id).run();
 const cmd=crypto.randomUUID(),input={kind:"answer",revision:0,text:"Durable jobs"};
 const response=await request(`challenges/${id}/interview`,subject,"POST",input,cmd);
 expect(response.status).toBe(202);expect(wire.InterviewState.safeParse(await response.json()).success).toBe(true);
 const replay=await request(`challenges/${id}/interview`,subject,"POST",input,cmd);expect(replay.status).toBe(202);
 const missing=await request(`challenges/${id}/interview`,subject,"POST",input);expect(missing.status).toBe(400);
 const fixture=await import("../../../packages/contracts/fixtures/interview.json");expect(wire.InterviewState.safeParse(fixture.default).success).toBe(true);
});
