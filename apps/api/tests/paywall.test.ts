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
const view = (subject: string, placement: unknown) => request("paywall/view", subject, "POST", { placement });
const views = (account: string) => bindings.DB.prepare("SELECT placement FROM paywall_views WHERE account_id=? ORDER BY rowid").bind(account).all<{ placement: string }>();

it("counts a paywall view against the signed-in account and nothing else", async () => {
  const a = await person(), b = await person();
  const first = await view(a.subject, "first_rep");
  expect(first.status).toBe(201);
  expect(wire.OK.safeParse(await first.json()).success).toBe(true);
  expect((await view(a.subject, "practice_rep")).status).toBe(201);
  expect((await views(a.id)).results.map(r => r.placement)).toEqual(["first_rep", "practice_rep"]);
  expect((await views(b.id)).results).toHaveLength(0);
  const columns = await bindings.DB.prepare("SELECT name FROM pragma_table_info('paywall_views')").all<{ name: string }>();
  expect(columns.results.map(c => c.name).sort()).toEqual(["account_id", "created_at", "placement"]);
});

it("refuses an unknown placement and an unsigned request", async () => {
  const { subject, id } = await person();
  for (const placement of ["settings", "", 3, null]) expect((await view(subject, placement)).status).toBe(400);
  expect((await request("paywall/view", subject, "POST", {})).status).toBe(400);
  const ctx = createExecutionContext();
  const anonymous = await app.fetch(new Request("https://api.test/v1/paywall/view", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ placement: "first_rep" }) }), bindings, ctx);
  await waitOnExecutionContext(ctx);
  expect(anonymous.status).toBe(401);
  expect((await views(id)).results).toHaveLength(0);
});

it("caps views at fifty a day, counts races exactly and goes with the account", async () => {
  const { subject, id } = await person();
  await bindings.DB.prepare("INSERT INTO usage(account_id,day,kind,count) VALUES(?,?,'paywall_view',45)").bind(id, new Date().toISOString().slice(0, 10)).run();
  const results = await Promise.all(Array.from({ length: 8 }, () => view(subject, "voice_session")));
  expect(results.filter(r => r.status === 201)).toHaveLength(5);
  expect(results.filter(r => r.status === 429)).toHaveLength(3);
  expect((await views(id)).results).toHaveLength(5);
  await bindings.DB.prepare("DELETE FROM accounts WHERE id=?").bind(id).run();
  expect((await views(id)).results).toHaveLength(0);
});
