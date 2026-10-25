import { createExecutionContext, env, fetchMock, waitOnExecutionContext } from "cloudflare:test";
import { X509CertificateGenerator } from "@peculiar/x509";
import { CompactSign, SignJWT, exportJWK, generateKeyPair } from "jose";
import { afterAll, beforeAll, expect, it } from "vitest";
import { app } from "../src/index";
import { entitlementState, verifyAppleJWS } from "../src/entitlements";
import type { Env } from "../src/platform";
import { planFor } from "../src/plans";
import { accountFor } from "../src/store";
import { initializeDatabase } from "./migrations";

const alg = { name: "ECDSA", namedCurve: "P-256", hash: "SHA-256" } as const;
const b64 = (buffer: ArrayBuffer) => btoa(String.fromCharCode(...new Uint8Array(buffer)));
const days = (n: number) => new Date(Date.now() + n * 86_400_000);

/** A throwaway Apple-shaped chain: root → intermediate → leaf. Only the root is pinned in the environment. */
async function chain() {
  const rootKeys = await crypto.subtle.generateKey(alg, true, ["sign", "verify"]);
  const root = await X509CertificateGenerator.createSelfSigned({ serialNumber: "01", name: "CN=Test Root CA", notBefore: days(-1), notAfter: days(365), signingAlgorithm: alg, keys: rootKeys });
  const midKeys = await crypto.subtle.generateKey(alg, true, ["sign", "verify"]);
  const mid = await X509CertificateGenerator.create({ serialNumber: "02", subject: "CN=Test Intermediate", issuer: root.subject, notBefore: days(-1), notAfter: days(365), signingAlgorithm: alg, publicKey: midKeys.publicKey, signingKey: rootKeys.privateKey });
  const leafKeys = await crypto.subtle.generateKey(alg, true, ["sign", "verify"]);
  const leaf = await X509CertificateGenerator.create({ serialNumber: "03", subject: "CN=Test Leaf", issuer: mid.subject, notBefore: days(-1), notAfter: days(365), signingAlgorithm: alg, publicKey: leafKeys.publicKey, signingKey: midKeys.privateKey });
  const sign = (payload: object) => new CompactSign(new TextEncoder().encode(JSON.stringify(payload)))
    .setProtectedHeader({ alg: "ES256", x5c: [b64(leaf.rawData), b64(mid.rawData), b64(root.rawData)] }).sign(leafKeys.privateKey);
  return { rootB64: b64(root.rawData), sign };
}

let apple: Awaited<ReturnType<typeof chain>>;
let bindings: Env;
let key: CryptoKey;
beforeAll(async () => {
  apple = await chain();
  bindings = { ...env, JOBS: { create: async () => ({ id: "test" }) }, CLERK_ISSUER: "https://auth.drillbit.test", CLERK_AUDIENCE: "drillbit", PRACTICE_GATE: "true", APPLE_ROOT_CERTS: apple.rootB64 } as unknown as Env;
  await initializeDatabase(bindings.DB);
  const pair = await generateKeyPair("RS256");
  key = pair.privateKey;
  fetchMock.activate();
  fetchMock.disableNetConnect();
  fetchMock.get("https://auth.drillbit.test").intercept({ path: "/.well-known/jwks.json" })
    .reply(200, { keys: [{ ...(await exportJWK(pair.publicKey)), kid: "test", alg: "RS256" }] }).persist();
});
afterAll(() => fetchMock.deactivate());

async function request(path: string, subject: string | null, method = "GET", body?: unknown) {
  const headers: Record<string, string> = { "Content-Type": "application/json" };
  if (subject) {
    const token = await new SignJWT({}).setProtectedHeader({ alg: "RS256", kid: "test" }).setSubject(subject)
      .setIssuer(bindings.CLERK_ISSUER).setAudience("drillbit").setIssuedAt().setExpirationTime("5m").sign(key);
    headers.Authorization = "Bearer " + token;
  }
  const ctx = createExecutionContext();
  const response = await app.fetch(new Request("https://api.test/" + path, { method, headers, body: body ? JSON.stringify(body) : undefined }), bindings, ctx);
  await waitOnExecutionContext(ctx);
  return response;
}
async function person() {
  const subject = crypto.randomUUID();
  const account = await accountFor(bindings, subject);
  await bindings.DB.prepare("UPDATE accounts SET status='active' WHERE id=?").bind(account.id).run();
  return { subject, id: account.id };
}
const transaction = (overrides: object = {}) => ({
  bundleId: "dawi.drillbit", productId: "dawi.drillbit.pro.weekly", originalTransactionId: crypto.randomUUID(), transactionId: crypto.randomUUID(),
  type: "Auto-Renewable Subscription", environment: "Sandbox", purchaseDate: Date.now() - 1000, expiresDate: Date.now() + 30 * 86_400_000, signedDate: Date.now(), ...overrides,
});
const post = async (subject: string | null, body: object) => request("v1/entitlement", subject, "POST", body);
const notify = async (payload: object) => request("apple/notifications", null, "POST", { signedPayload: await apple.sign(payload) });

it("verifies the chain against the pinned root and rejects anything else", async () => {
  const claims = transaction();
  expect(await verifyAppleJWS(bindings, await apple.sign(claims))).toMatchObject({ originalTransactionId: claims.originalTransactionId });
  const stranger = await chain();
  await expect(verifyAppleJWS(bindings, await stranger.sign(claims))).rejects.toMatchObject({ code: "untrusted_receipt", status: 401 });
  await expect(verifyAppleJWS({ ...bindings, APPLE_ROOT_CERTS: stranger.rootB64 }, await apple.sign(claims))).rejects.toMatchObject({ code: "untrusted_receipt" });
  // A token that drops the chain or tampers with the body fails before the signature is even checked.
  const token = await apple.sign(claims);
  const [header, , signature] = token.split(".");
  const tampered = header + "." + btoa(JSON.stringify({ ...claims, productId: "dawi.drillbit.pro.yearly" })).replace(/=+$/, "") + "." + signature;
  await expect(verifyAppleJWS(bindings, tampered)).rejects.toMatchObject({ code: "untrusted_receipt" });
  await expect(verifyAppleJWS(bindings, "not-a-token")).rejects.toMatchObject({ code: "invalid_receipt", status: 400 });
});

it("derives active, grace, expired and revoked from the transaction", () => {
  const now = Date.now();
  expect(entitlementState(transaction() as never, undefined, now)).toMatchObject({ status: "active" });
  expect(entitlementState(transaction({ expiresDate: now - 1000 }) as never, undefined, now)).toMatchObject({ status: "expired" });
  expect(entitlementState(transaction({ expiresDate: now - 1000 }) as never, { gracePeriodExpiresDate: now + 86_400_000 }, now)).toMatchObject({ status: "grace" });
  expect(entitlementState(transaction({ revocationDate: now - 500 }) as never, undefined, now)).toMatchObject({ status: "revoked" });
});

it("records a verified purchase for the caller and turns the plan Pro", async () => {
  const { subject, id } = await person();
  expect(await planFor(bindings, id)).toBe("free");
  const claims = transaction();
  const accepted = await post(subject, { signedTransaction: await apple.sign(claims) });
  expect(accepted.status).toBe(200);
  expect(await accepted.json()).toMatchObject({ plan: "pro", entitlement: { productId: "dawi.drillbit.pro.weekly", status: "active" } });
  expect(await planFor(bindings, id)).toBe("pro");
  const bootstrap = await (await request("v1/bootstrap", subject)).json() as { account: { plan: string }; practice: { freeReps: boolean } };
  expect(bootstrap.account.plan).toBe("pro");
  expect(bootstrap.practice.freeReps).toBe(false);
  // Posting the same receipt again changes nothing; an older statement never downgrades.
  expect((await post(subject, { signedTransaction: await apple.sign(claims) })).status).toBe(200);
  expect((await post(subject, { signedTransaction: await apple.sign({ ...claims, expiresDate: Date.now() - 1000, signedDate: claims.signedDate - 60_000 }) })).status).toBe(200);
  expect(await planFor(bindings, id)).toBe("pro");
});

it("rejects receipts for other apps, unknown products and the wrong environment", async () => {
  const { subject } = await person();
  for (const [claims, message] of [
    [transaction({ bundleId: "someone.else" }), /different app/],
    [transaction({ productId: "dawi.drillbit.lifetime" }), /isn’t part of/],
  ] as const) {
    const response = await post(subject, { signedTransaction: await apple.sign(claims) });
    expect(response.status).toBe(400);
    expect(((await response.json()) as { error: { message: string } }).error.message).toMatch(message);
  }
  const production = { ...bindings, APPLE_ENVIRONMENT: "Production" } as Env;
  const ctx = createExecutionContext();
  const token = await new SignJWT({}).setProtectedHeader({ alg: "RS256", kid: "test" }).setSubject(subject).setIssuer(bindings.CLERK_ISSUER).setAudience("drillbit").setIssuedAt().setExpirationTime("5m").sign(key);
  const response = await app.fetch(new Request("https://api.test/v1/entitlement", { method: "POST", headers: { "Content-Type": "application/json", Authorization: "Bearer " + token }, body: JSON.stringify({ signedTransaction: await apple.sign(transaction()) }) }), production, ctx);
  await waitOnExecutionContext(ctx);
  expect(response.status).toBe(400);
});

it("binds a subscription to one account", async () => {
  const first = await person(), second = await person();
  const claims = transaction();
  expect((await post(first.subject, { signedTransaction: await apple.sign(claims) })).status).toBe(200);
  const stolen = await post(second.subject, { signedTransaction: await apple.sign(claims) });
  expect(stolen.status).toBe(409);
  expect(await stolen.json()).toMatchObject({ error: { code: "entitlement_taken" } });
  expect(await planFor(bindings, second.id)).toBe("free");
});

it("applies App Store notifications to a known subscription and ignores unknown ones", async () => {
  const { subject, id } = await person();
  const claims = transaction();
  await post(subject, { signedTransaction: await apple.sign(claims) });
  expect(await planFor(bindings, id)).toBe("pro");
  // Expired: Pro ends.
  let response = await notify({ notificationType: "EXPIRED", subtype: "VOLUNTARY", data: { bundleId: "dawi.drillbit", environment: "Sandbox", signedTransactionInfo: await apple.sign({ ...claims, expiresDate: Date.now() - 1000, signedDate: Date.now() }) } });
  expect(response.status).toBe(200);
  expect(await response.json()).toMatchObject({ applied: true, notificationType: "EXPIRED" });
  expect(await planFor(bindings, id)).toBe("free");
  // Billing retry with a grace period keeps Pro until the grace ends.
  response = await notify({ notificationType: "DID_FAIL_TO_RENEW", subtype: "GRACE_PERIOD", data: { signedTransactionInfo: await apple.sign({ ...claims, expiresDate: Date.now() - 1000, signedDate: Date.now() + 1 }), signedRenewalInfo: await apple.sign({ autoRenewStatus: 1, gracePeriodExpiresDate: Date.now() + 86_400_000 }) } });
  expect(await response.json()).toMatchObject({ applied: true });
  expect(await planFor(bindings, id)).toBe("pro");
  // Renewal extends it; refund revokes it.
  await notify({ notificationType: "DID_RENEW", data: { signedTransactionInfo: await apple.sign({ ...claims, expiresDate: Date.now() + 30 * 86_400_000, signedDate: Date.now() + 2 }) } });
  expect(await planFor(bindings, id)).toBe("pro");
  await notify({ notificationType: "REFUND", data: { signedTransactionInfo: await apple.sign({ ...claims, revocationDate: Date.now(), signedDate: Date.now() + 3 }) } });
  expect(await planFor(bindings, id)).toBe("free");
  expect((await bindings.DB.prepare("SELECT status FROM entitlements WHERE original_transaction_id=?").bind(claims.originalTransactionId).first<{ status: string }>())!.status).toBe("revoked");
  // Unknown transaction: acknowledged, nothing stored. TEST pings are acknowledged too.
  response = await notify({ notificationType: "SUBSCRIBED", data: { signedTransactionInfo: await apple.sign(transaction()) } });
  expect(await response.json()).toMatchObject({ applied: false });
  expect((await notify({ notificationType: "TEST" })).status).toBe(200);
  // A forged notification is refused.
  const stranger = await chain();
  expect((await request("apple/notifications", null, "POST", { signedPayload: await stranger.sign({ notificationType: "REFUND" }) })).status).toBe(401);
});
