// @peculiar/x509 resolves its internals through tsyringe, which needs the Reflect polyfill loaded first.
import "reflect-metadata";
import { X509Certificate } from "@peculiar/x509";
import { decodeProtectedHeader, compactVerify } from "jose";
import { z } from "zod";
import { Fault, timestamp } from "./domain";
import type { Env } from "./platform";

/**
 * Apple Root CA - G3, downloaded from https://www.apple.com/certificateauthority/AppleRootCA-G3.cer on 10 Oct 2026.
 * SHA-256 63:34:3A:BF:B8:9A:6A:03:EB:B5:7E:9B:3F:5F:A7:BE:7C:4F:5C:75:6F:30:17:B3:A8:C4:88:C3:65:3E:91:79, valid to 30 Apr 2039.
 * `APPLE_ROOT_CERTS` (comma-separated base64 DER) replaces it; tests pin their own root.
 */
const APPLE_ROOT_CA_G3 = "MIICQzCCAcmgAwIBAgIILcX8iNLFS5UwCgYIKoZIzj0EAwMwZzEbMBkGA1UEAwwSQXBwbGUgUm9vdCBDQSAtIEczMSYwJAYDVQQLDB1BcHBsZSBDZXJ0aWZpY2F0aW9uIEF1dGhvcml0eTETMBEGA1UECgwKQXBwbGUgSW5jLjELMAkGA1UEBhMCVVMwHhcNMTQwNDMwMTgxOTA2WhcNMzkwNDMwMTgxOTA2WjBnMRswGQYDVQQDDBJBcHBsZSBSb290IENBIC0gRzMxJjAkBgNVBAsMHUFwcGxlIENlcnRpZmljYXRpb24gQXV0aG9yaXR5MRMwEQYDVQQKDApBcHBsZSBJbmMuMQswCQYDVQQGEwJVUzB2MBAGByqGSM49AgEGBSuBBAAiA2IABJjpLz1AcqTtkyJygRMc3RCV8cWjTnHcFBbZDuWmBSp3ZHtfTjjTuxxEtX/1H7YyYl3J6YRbTzBPEVoA/VhYDKX1DyxNB0cTddqXl5dvMVztK517IDvYuVTZXpmkOlEKMaNCMEAwHQYDVR0OBBYEFLuw3qFYM4iapIqZ3r6966/ayySrMA8GA1UdEwEB/wQFMAMBAf8wDgYDVR0PAQH/BAQDAgEGMAoGCCqGSM49BAMDA2gAMGUCMQCD6cHEFl4aXTQY2e3v9GwOAEZLuN+yRhHFD/3meoyhpmvOwgPUnPWTxnS4at+qIxUCMG1mihDK1A3UT82NQz60imOlM27jbdoXt2QfyFMm+YhidDkLF1vLUagM6BgD56KyKA==";

export const entitlementInputSchema = z.object({ signedTransaction: z.string().min(1).max(16_000) });
export const appleNotificationSchema = z.object({ signedPayload: z.string().min(1).max(32_000) });

const transactionSchema = z.object({
  bundleId: z.string(),
  productId: z.string(),
  originalTransactionId: z.string(),
  transactionId: z.string().optional(),
  type: z.string().optional(),
  environment: z.enum(["Sandbox", "Production", "Xcode"]),
  purchaseDate: z.number(),
  expiresDate: z.number().optional(),
  revocationDate: z.number().optional(),
  signedDate: z.number(),
});
const renewalSchema = z.object({ gracePeriodExpiresDate: z.number().optional(), autoRenewStatus: z.number().optional() }).passthrough();
const notificationSchema = z.object({
  notificationType: z.string(),
  subtype: z.string().optional(),
  signedDate: z.number().optional(),
  data: z.object({ bundleId: z.string().optional(), environment: z.string().optional(), signedTransactionInfo: z.string().optional(), signedRenewalInfo: z.string().optional() }).optional(),
});
export type AppleTransaction = z.infer<typeof transactionSchema>;

const fromBase64 = (value: string) => Uint8Array.from(atob(value), c => c.charCodeAt(0)).buffer;

function roots(env: Env) {
  return (env.APPLE_ROOT_CERTS ?? APPLE_ROOT_CA_G3).split(",").map(s => s.trim()).filter(Boolean).map(b64 => new X509Certificate(fromBase64(b64)));
}

/**
 * Verifies an App Store signed payload: the x5c chain must end in a pinned Apple root, every link must be
 * validly signed and in date, and the JWS signature must come from the leaf. Returns the decoded claims.
 */
export async function verifyAppleJWS(env: Env, token: string, now = new Date()): Promise<unknown> {
  let header: ReturnType<typeof decodeProtectedHeader>;
  try { header = decodeProtectedHeader(token); } catch { throw new Fault("invalid_receipt", 400, "That receipt couldn’t be read."); }
  if (header.alg !== "ES256" || !Array.isArray(header.x5c) || header.x5c.length < 2) throw new Fault("invalid_receipt", 400, "That receipt couldn’t be read.");
  const chain = header.x5c.map(b64 => new X509Certificate(fromBase64(b64)));
  const trusted = roots(env);
  for (let i = 0; i < chain.length; i++) {
    const cert = chain[i], issuer = chain[i + 1] ?? trusted.find(root => root.subject === cert.issuer);
    if (!issuer) throw new Fault("untrusted_receipt", 401, "That receipt isn’t from the App Store.");
    if (cert.notBefore > now || cert.notAfter < now) throw new Fault("untrusted_receipt", 401, "That receipt isn’t from the App Store.");
    if (!(await cert.verify({ publicKey: await issuer.publicKey.export(), signatureOnly: true }))) throw new Fault("untrusted_receipt", 401, "That receipt isn’t from the App Store.");
  }
  const last = chain[chain.length - 1];
  const root = trusted.find(r => r.subject === last.issuer);
  if (!root || root.notAfter < now) throw new Fault("untrusted_receipt", 401, "That receipt isn’t from the App Store.");
  try {
    const key = await chain[0].publicKey.export({ name: "ECDSA", namedCurve: "P-256", hash: "SHA-256" }, ["verify"]);
    const { payload } = await compactVerify(token, key, { algorithms: ["ES256"] });
    return JSON.parse(new TextDecoder().decode(payload));
  } catch { throw new Fault("untrusted_receipt", 401, "That receipt isn’t from the App Store."); }
}

export function knownProducts(env: Env) {
  return (env.APPLE_PRODUCT_IDS ?? "dawi.drillbit.pro.monthly,dawi.drillbit.pro.yearly").split(",").map(s => s.trim()).filter(Boolean);
}

/** The row an Apple transaction (plus optional renewal info) implies right now. */
export function entitlementState(transaction: AppleTransaction, renewal?: { gracePeriodExpiresDate?: number }, now = Date.now()) {
  if (transaction.revocationDate) return { status: "revoked" as const, activeUntil: new Date(transaction.revocationDate).toISOString() };
  const expires = transaction.expiresDate ?? null;
  if (expires === null) return { status: "active" as const, activeUntil: null };
  if (expires > now) return { status: "active" as const, activeUntil: new Date(expires).toISOString() };
  if (renewal?.gracePeriodExpiresDate && renewal.gracePeriodExpiresDate > now) return { status: "grace" as const, activeUntil: new Date(renewal.gracePeriodExpiresDate).toISOString() };
  return { status: "expired" as const, activeUntil: new Date(expires).toISOString() };
}

function acceptedTransaction(env: Env, raw: unknown) {
  const parsed = transactionSchema.safeParse(raw);
  if (!parsed.success) throw new Fault("invalid_receipt", 400, "That receipt couldn’t be read.");
  const t = parsed.data;
  if (t.bundleId !== (env.APPLE_BUNDLE_ID ?? "dawi.drillbit")) throw new Fault("invalid_receipt", 400, "That receipt belongs to a different app.");
  if (!knownProducts(env).includes(t.productId)) throw new Fault("invalid_receipt", 400, "That product isn’t part of Drillbit Pro.");
  if (env.APPLE_ENVIRONMENT && t.environment !== env.APPLE_ENVIRONMENT) throw new Fault("invalid_receipt", 400, "That receipt is from a different App Store environment.");
  return t;
}

async function upsert(env: Env, account: string | null, t: AppleTransaction, state: ReturnType<typeof entitlementState>) {
  const now = timestamp();
  const signedAt = new Date(t.signedDate).toISOString();
  if (account) {
    const owner = await env.DB.prepare("SELECT account_id FROM entitlements WHERE original_transaction_id=?").bind(t.originalTransactionId).first<{ account_id: string }>();
    if (owner && owner.account_id !== account) throw new Fault("entitlement_taken", 409, "This subscription is already linked to another Drillbit account.");
    // Newest signed statement wins; a replayed older receipt changes nothing.
    await env.DB.prepare(
      "INSERT INTO entitlements(original_transaction_id,account_id,product_id,environment,status,active_until,signed_at,created_at,updated_at) VALUES(?,?,?,?,?,?,?,?,?) ON CONFLICT(original_transaction_id) DO UPDATE SET product_id=excluded.product_id,status=excluded.status,active_until=excluded.active_until,signed_at=excluded.signed_at,updated_at=excluded.updated_at WHERE excluded.signed_at>=entitlements.signed_at",
    ).bind(t.originalTransactionId, account, t.productId, t.environment, state.status, state.activeUntil, signedAt, now, now).run();
    return true;
  }
  const result = await env.DB.prepare(
    "UPDATE entitlements SET product_id=?,status=?,active_until=?,signed_at=?,updated_at=? WHERE original_transaction_id=? AND signed_at<=?",
  ).bind(t.productId, state.status, state.activeUntil, signedAt, now, t.originalTransactionId, signedAt).run();
  return result.meta.changes > 0;
}

/** A client posts the StoreKit 2 signed transaction after purchase or restore; the row is bound to the caller's account. */
export async function recordEntitlement(env: Env, account: string, raw: unknown) {
  const { signedTransaction } = entitlementInputSchema.parse(raw);
  const t = acceptedTransaction(env, await verifyAppleJWS(env, signedTransaction));
  const state = entitlementState(t);
  await upsert(env, account, t, state);
  return { productId: t.productId, status: state.status, activeUntil: state.activeUntil };
}

/** App Store Server Notifications V2. Unknown transactions are acknowledged and ignored; Apple retries nothing we can't use. */
export async function applyAppleNotification(env: Env, raw: unknown) {
  const { signedPayload } = appleNotificationSchema.parse(raw);
  const decoded = notificationSchema.safeParse(await verifyAppleJWS(env, signedPayload));
  if (!decoded.success) throw new Fault("invalid_receipt", 400, "That notification couldn’t be read.");
  const note = decoded.data;
  if (note.notificationType === "TEST" || !note.data?.signedTransactionInfo) return { applied: false, notificationType: note.notificationType };
  const transaction = transactionSchema.safeParse(await verifyAppleJWS(env, note.data.signedTransactionInfo));
  if (!transaction.success) throw new Fault("invalid_receipt", 400, "That notification couldn’t be read.");
  if (env.APPLE_ENVIRONMENT && transaction.data.environment !== env.APPLE_ENVIRONMENT) return { applied: false, notificationType: note.notificationType };
  const renewal = note.data.signedRenewalInfo ? renewalSchema.safeParse(await verifyAppleJWS(env, note.data.signedRenewalInfo)) : undefined;
  const state = entitlementState(transaction.data, renewal?.success ? renewal.data : undefined);
  const applied = await upsert(env, null, transaction.data, state);
  console.info(JSON.stringify({ event: "apple_notification", notificationType: note.notificationType, subtype: note.subtype, applied, status: state.status }));
  return { applied, notificationType: note.notificationType };
}
