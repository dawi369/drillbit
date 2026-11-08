import { createExecutionContext, env, fetchMock, waitOnExecutionContext } from "cloudflare:test";
import { SignJWT, exportJWK, generateKeyPair } from "jose";
import { afterAll, beforeAll, expect, it, vi } from "vitest";
import { app } from "../src/index";
import { requestInterview } from "../src/interview";
import type { Env } from "../src/platform";
import { accountFor } from "../src/store";
import { startVoice, voiceCapability } from "../src/voice";
import { initializeDatabase } from "./migrations";

// Voice sessions outliving their interview: a skip after the app died mid-voice, and a question deleted from Library.
const bindings = {
  ...env,
  JOBS: { create: async () => ({ id: "test" }) },
  CLERK_ISSUER: "https://auth.drillbit.test",
  CLERK_AUDIENCE: "drillbit",
  VOICE_ENABLED: "true",
  OPENAI_API_KEY: "test",
  MANAGED_AI_ENABLED: "true",
  OPENROUTER_API_KEY: "test",
} as unknown as Env;
const free = { ...bindings, PRACTICE_GATE: "true", FREE_VOICE_TASTE_DAYS: "0", FREE_VOICE_LIFETIME: "1", FREE_VOICE_SESSION_MINUTES: "10" } as Env;
let key: CryptoKey;
beforeAll(async () => {
  await initializeDatabase(bindings.DB);
  const pair = await generateKeyPair("RS256");
  key = pair.privateKey;
  fetchMock.activate();
  fetchMock.get("https://auth.drillbit.test").intercept({ path: "/.well-known/jwks.json" })
    .reply(200, { keys: [{ ...(await exportJWK(pair.publicKey)), kid: "test", alg: "RS256" }] }).persist();
});
afterAll(() => fetchMock.deactivate());

async function request(path: string, subject: string, method = "GET", target = bindings) {
  const token = await new SignJWT({}).setProtectedHeader({ alg: "RS256", kid: "test" }).setSubject(subject)
    .setIssuer(bindings.CLERK_ISSUER).setAudience("drillbit").setIssuedAt().setExpirationTime("5m").sign(key);
  const ctx = createExecutionContext();
  const response = await app.fetch(new Request("https://api.test/v1/" + path, { method, headers: { Authorization: "Bearer " + token } }), target, ctx);
  await waitOnExecutionContext(ctx);
  return response;
}
async function person() {
  const subject = crypto.randomUUID();
  const account = await accountFor(bindings, subject);
  await bindings.DB.prepare("UPDATE accounts SET status='active' WHERE id=?").bind(account.id).run();
  return { subject, a: account.id };
}
async function question(account: string, lifecycle = "in_progress") {
  const id = crypto.randomUUID();
  await bindings.DB.batch([
    bindings.DB.prepare("INSERT INTO challenges(id,account_id,lifecycle,data,created_at,available_at) VALUES(?,?,?,?,?,?)")
      .bind(id, account, lifecycle, JSON.stringify({ title: "Queue", prompt: "Design a job queue", topic: "System design" }), new Date().toISOString(), new Date().toISOString()),
    bindings.DB.prepare("INSERT INTO sessions(challenge_id,answer,revision,updated_at) VALUES(?,'Use a durable queue.',2,?)").bind(id, new Date().toISOString()),
  ]);
  return id;
}
// Only the voice provider is faked; Clerk's keys still come from fetchMock.
const provider = () => {
  const real = globalThis.fetch.bind(globalThis);
  return vi.spyOn(globalThis, "fetch").mockImplementation(async (input, init) =>
    String(input instanceof Request ? input.url : input).startsWith("https://api.openai.com/")
      ? new Response(JSON.stringify({ session: { id: "live_test" }, transport: { sdp: "answer" } }), { status: 201 })
      : real(input, init));
};

it("skipping a question whose voice was never closed frees typing and voice on the next one, billing only the time used", async () => {
  const { subject, a } = await person(), first = await question(a), mock = provider();
  try {
    const voice = await startVoice(bindings, a, first, crypto.randomUUID(), { sdp: "offer", revision: 2 });
    // The app was killed mid-voice, then the question was skipped from Home: nothing ever closes the session.
    expect((await request(`challenges/${first}/skip`, subject, "POST")).status).toBe(200);
    const ended = await bindings.DB.prepare("SELECT status,usage_seconds FROM voice_sessions WHERE id=?").bind(voice.id).first<{ status: string; usage_seconds: number }>();
    expect(ended?.status).toBe("uncertain");
    expect(ended?.usage_seconds).toBeLessThan(60);
    const next = await question(a);
    await bindings.DB.prepare("UPDATE challenges SET created_at=? WHERE id=?").bind(new Date().toISOString(), next).run();
    const typed = await requestInterview(bindings, a, next, crypto.randomUUID(), { kind: "answer", text: "Use a durable queue.", revision: 2, promptId: "original" });
    expect(typed.turns.at(-1)).toMatchObject({ kind: "answer" });
    expect(await voiceCapability(bindings, a)).toMatchObject({ available: true });
  } finally {
    mock.mockRestore();
  }
});

it("deleting a practised question keeps its voice counted: no second free voice mock", async () => {
  const { subject, a } = await person(), id = await question(a), mock = provider();
  try {
    const voice = await startVoice(free, a, id, crypto.randomUUID(), { sdp: "offer", revision: 2 });
    await bindings.DB.prepare("UPDATE voice_sessions SET status='closed',finalized=1,usage_seconds=240 WHERE id=?").bind(voice.id).run();
    const spent = { available: false, plan: "free", reason: "That was your free voice mock. Pro has voice any time." };
    expect(await voiceCapability(free, a)).toMatchObject(spent);
    await bindings.DB.prepare("UPDATE challenges SET lifecycle='completed' WHERE id=?").bind(id).run();
    expect((await request(`challenges/${id}`, subject, "DELETE", free)).status).toBe(200);
    expect(await bindings.DB.prepare("SELECT id FROM voice_sessions WHERE id=?").bind(voice.id).first()).toBeNull();
    expect(await voiceCapability(free, a)).toMatchObject(spent);
  } finally {
    mock.mockRestore();
  }
});

it("deleting a practised question keeps Pro's voice minutes counted for the day and the week", async () => {
  const { subject, a } = await person(), id = await question(a), mock = provider();
  try {
    const voice = await startVoice(bindings, a, id, crypto.randomUUID(), { sdp: "offer", revision: 2 });
    await bindings.DB.prepare("UPDATE voice_sessions SET status='closed',finalized=1,usage_seconds=3600 WHERE id=?").bind(voice.id).run();
    const paused = await voiceCapability(bindings, a);
    expect(paused).toMatchObject({ available: false, plan: "pro" });
    await bindings.DB.prepare("UPDATE challenges SET lifecycle='completed' WHERE id=?").bind(id).run();
    expect((await request(`challenges/${id}`, subject, "DELETE")).status).toBe(200);
    expect(await voiceCapability(bindings, a)).toMatchObject({ available: false, plan: "pro", reason: paused.reason });
  } finally {
    mock.mockRestore();
  }
});

it("deleting a question keeps its waived silent look: a free account still gets only one", async () => {
  const { subject, a } = await person(), id = await question(a), mock = provider();
  try {
    const free1 = { ...free, FREE_VOICE_LIFETIME: "3" } as Env;
    const look = await startVoice(free1, a, id, crypto.randomUUID(), { sdp: "offer", revision: 2 });
    const { voiceEvents } = await import("../src/voice");
    await voiceEvents(free1, a, id, look.id, { fragments: [], closed: true, finalized: true, usageSeconds: 5 });
    expect(await bindings.DB.prepare("SELECT waived FROM voice_sessions WHERE id=?").bind(look.id).first()).toEqual({ waived: 1 });
    await bindings.DB.prepare("UPDATE challenges SET lifecycle='completed' WHERE id=?").bind(id).run();
    expect((await request(`challenges/${id}`, subject, "DELETE", free1)).status).toBe(200);
    // A second silent look on a new question is billed: the free plan's one waived look is spent.
    const next = await question(a);
    const second = await startVoice(free1, a, next, crypto.randomUUID(), { sdp: "offer", revision: 2 });
    await voiceEvents(free1, a, next, second.id, { fragments: [], closed: true, finalized: true, usageSeconds: 5 });
    expect(await bindings.DB.prepare("SELECT waived FROM voice_sessions WHERE id=?").bind(second.id).first()).toEqual({ waived: 0 });
  } finally {
    mock.mockRestore();
  }
});
