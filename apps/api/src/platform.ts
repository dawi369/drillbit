import { createRemoteJWKSet, jwtVerify } from "jose";
import { Fault, timestamp } from "./domain";
export interface Env {
  DB: D1Database;
  JOBS: Workflow<{ jobId: string }>;
  CLERK_ISSUER: string;
  CLERK_AUDIENCE: string;
  CLERK_SECRET_KEY?: string;
  OPENROUTER_API_KEY?: string;
  CREDENTIAL_KEY?: string;
  CREDENTIAL_KEY_VERSION: string;
  MODEL_ID: string;
  MANAGED_AI_ENABLED: string;
  COMPANION_AUTO_ENABLED?: string;
}
const jwks = new Map<string, ReturnType<typeof createRemoteJWKSet>>();
export async function identity(env: Env, authorization?: string) {
  if (!authorization?.startsWith("Bearer "))
    throw new Fault("unauthenticated", 401, "Sign in to continue.");
  try {
    const issuer = new URL(env.CLERK_ISSUER);
    if (issuer.protocol !== "https:") throw new Error("issuer");
    let keys = jwks.get(issuer.origin);
    if (!keys) {
      keys = createRemoteJWKSet(new URL("/.well-known/jwks.json", issuer));
      jwks.set(issuer.origin, keys);
    }
    const { payload } = await jwtVerify(authorization.slice(7), keys, {
      issuer: issuer.origin,
      audience: env.CLERK_AUDIENCE || "drillbit",
      algorithms: ["RS256"],
    });
    if (!payload.sub || !payload.exp) throw new Error("claims");
    return payload.sub;
  } catch {
    throw new Fault(
      "unauthenticated",
      401,
      "Your session expired. Sign in again.",
    );
  }
}
export async function hash(value: string) {
  return Array.from(
    new Uint8Array(
      await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value)),
    ),
  )
    .map((x) => x.toString(16).padStart(2, "0"))
    .join("");
}
const encode = (value: Uint8Array) => btoa(String.fromCharCode(...value));
const decode = (value: string) =>
  Uint8Array.from(atob(value), (c) => c.charCodeAt(0));
async function encryptionKey(env: Env) {
  if (!env.CREDENTIAL_KEY)
    throw new Fault("configuration", 503, "Credential storage is unavailable.");
  return crypto.subtle.importKey(
    "raw",
    decode(env.CREDENTIAL_KEY),
    { name: "AES-GCM" },
    false,
    ["encrypt", "decrypt"],
  );
}
export async function encrypt(env: Env, value: string, owner: string) {
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const result = await crypto.subtle.encrypt(
    { name: "AES-GCM", iv, additionalData: new TextEncoder().encode(owner) },
    await encryptionKey(env),
    new TextEncoder().encode(value),
  );
  return `${encode(iv)}.${encode(new Uint8Array(result))}`;
}
export async function decrypt(env: Env, value: string, owner: string) {
  const [iv, data] = value.split(".");
  return new TextDecoder().decode(
    await crypto.subtle.decrypt(
      {
        name: "AES-GCM",
        iv: decode(iv),
        additionalData: new TextEncoder().encode(owner),
      },
      await encryptionKey(env),
      decode(data),
    ),
  );
}
export async function consumeUsage(
  env: Env,
  account: string,
  kind: string,
  limit: number,
) {
  const row = await env.DB.prepare(
    `INSERT INTO usage(account_id,day,kind,count) VALUES(?,?,?,1) ON CONFLICT(account_id,day,kind) DO UPDATE SET count=count+1 WHERE count<? RETURNING count`,
  )
    .bind(account, timestamp().slice(0, 10), kind, limit)
    .first();
  if (!row)
    throw new Fault(
      "usage_limit",
      429,
      "Daily usage limit reached. Try again tomorrow.",
    );
}
