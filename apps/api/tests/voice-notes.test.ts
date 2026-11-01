import { createExecutionContext, env, fetchMock, waitOnExecutionContext } from "cloudflare:test";
import { SignJWT, exportJWK, generateKeyPair } from "jose";
import { afterAll, beforeAll, expect, it } from "vitest";
import { wire } from "../../../packages/contracts/wire";
import { app } from "../src/index";
import type { Env } from "../src/platform";
import { accountFor } from "../src/store";
import { initializeDatabase } from "./migrations";

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
  const response = await app.fetch(new Request("https://api.test/v1/" + path, { method, headers, body: typeof body === "string" ? body : body ? JSON.stringify(body) : undefined }), bindings, ctx);
  await waitOnExecutionContext(ctx);
  return response;
}
async function person() {
  const subject = crypto.randomUUID();
  const account = await accountFor(bindings, subject);
  await bindings.DB.prepare("UPDATE accounts SET status='active' WHERE id=?").bind(account.id).run();
  return { subject, id: account.id };
}
/** A stand-in .m4a: the container's "ftyp" box at bytes 4–7, then `size` bytes in all. */
function m4a(size = 2048) {
  const bytes = new Uint8Array(size);
  bytes.set([0, 0, 0, 24, ...new TextEncoder().encode("ftypM4A ")]);
  for (let i = 12; i < size; i++) bytes[i] = i % 251;
  let binary = "";
  for (const b of bytes) binary += String.fromCharCode(b);
  return btoa(binary);
}
const send = (subject: string, body: object, command = crypto.randomUUID()) => request("feedback/voice", subject, "POST", body, command);
const notes = (account: string) => bindings.DB.prepare("SELECT id,length(audio) AS bytes,duration_seconds,app_version FROM voice_notes WHERE account_id=?").bind(account).all<{ id: string; bytes: number; duration_seconds: number; app_version: string | null }>();

it("keeps a voice note with the account and answers a retried command with the same note", async () => {
  const { subject, id } = await person();
  const command = crypto.randomUUID();
  const first = await send(subject, { audio: m4a(), durationSeconds: 12.4, appVersion: "1.0 (17)" }, command);
  expect(first.status).toBe(201);
  const note = await first.json();
  expect(wire.VoiceNote.safeParse(note).success).toBe(true);
  expect(note).toMatchObject({ id: command, durationSeconds: 12.4 });
  const again = await send(subject, { audio: m4a(), durationSeconds: 12.4 }, command);
  expect(again.status).toBe(200);
  expect(await again.json()).toEqual(note);
  expect((await notes(id)).results).toEqual([{ id: command, bytes: 2048, duration_seconds: 12.4, app_version: "1.0 (17)" }]);
  // Another account can't claim the same command.
  const other = await person();
  expect((await send(other.subject, { audio: m4a(), durationSeconds: 3 }, command)).status).toBe(409);
});

it("refuses anything that isn't a short .m4a recording", async () => {
  const { subject, id } = await person();
  const notAudio = btoa("x".repeat(200));
  expect((await send(subject, { audio: notAudio, durationSeconds: 5 })).status).toBe(400);
  expect((await send(subject, { audio: "%%%", durationSeconds: 5 })).status).toBe(400);
  expect((await send(subject, { audio: m4a(), durationSeconds: 400 })).status).toBe(400);
  expect((await send(subject, { audio: m4a(), durationSeconds: 0 })).status).toBe(400);
  // Over 1 MB of audio, still under the route's body limit.
  expect((await send(subject, { audio: m4a(1100 * 1024), durationSeconds: 60 })).status).toBe(400);
  // Over the route's body limit.
  const huge = await send(subject, { audio: m4a(1200 * 1024), durationSeconds: 60 });
  expect(huge.status).toBe(413);
  expect(await huge.json()).toMatchObject({ error: { code: "request_too_large", message: "Keep your voice note under two minutes." } });
  expect((await notes(id)).results).toHaveLength(0);
  // Every other route keeps the small text limit.
  const answer = await request("settings/preview", subject, "POST", { goals: "x".repeat(200 * 1024) });
  expect(answer.status).toBe(413);
});

it("takes five voice notes a day", async () => {
  const { subject, id } = await person();
  for (let i = 0; i < 5; i++) expect((await send(subject, { audio: m4a(), durationSeconds: 4 })).status).toBe(201);
  const sixth = await send(subject, { audio: m4a(), durationSeconds: 4 });
  expect(sixth.status).toBe(429);
  expect(await sixth.json()).toMatchObject({ error: { code: "usage_limit", message: "That’s five voice notes today. I’ll listen to those first." } });
  expect((await notes(id)).results).toHaveLength(5);
});

it("lists voice notes once in the export, without the audio, and deletes them with the account", async () => {
  const { subject, id } = await person();
  const command = crypto.randomUUID();
  await send(subject, { audio: m4a(), durationSeconds: 8 }, command);
  const page = await (await request("account/export", subject)).json() as { voiceNotes?: { id: string; durationSeconds: number }[] };
  expect(wire.AccountExport.safeParse(page).success).toBe(true);
  expect(page.voiceNotes).toEqual([expect.objectContaining({ id: command, durationSeconds: 8 })]);
  expect(JSON.stringify(page)).not.toContain(m4a().slice(0, 40));
  await bindings.DB.prepare("DELETE FROM accounts WHERE id=?").bind(id).run();
  expect((await notes(id)).results).toHaveLength(0);
});
