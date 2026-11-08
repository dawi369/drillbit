// A Pro subscriber's week against real D1, day by day, through the HTTP API the app uses: purchase, the daily
// question, rerolls, reps with interview turns, feedback, Recall, voice minutes, renewal, export and deletion.
// Only Date is faked, so provider streams and timeouts keep their real timers. The AI and voice providers, Clerk
// and the JWKS are answered locally; the network is off.
import { createExecutionContext, env, fetchMock, waitOnExecutionContext } from "cloudflare:test";
import { X509CertificateGenerator } from "@peculiar/x509";
import { CompactSign, SignJWT, exportJWK, generateKeyPair } from "jose";
import { afterAll, beforeAll, describe, expect, it, vi } from "vitest";
import { app } from "../src/index";
import { reconcile, runJob } from "../src/jobs";
import type { Env } from "../src/platform";
import { initializeDatabase } from "./migrations";

const ISSUER = "https://auth.drillbit.test";
const WEEKLY = "dawi.drillbit.pro.weekly", YEARLY = "dawi.drillbit.pro.yearly";
const DAY = 86_400_000;
/** Jobs handed to the Workflow instead of running inline; only account deletion should ever land here. */
const dispatched: string[] = [];
const bindings = {
  ...env,
  JOBS: { create: async ({ id }: { id: string }) => { dispatched.push(id); return { id }; } },
  CLERK_ISSUER: ISSUER,
  CLERK_AUDIENCE: "drillbit",
  CLERK_SECRET_KEY: "sk_test_week",
  MANAGED_AI_ENABLED: "true",
  OPENROUTER_API_KEY: "test-openrouter",
  OPENAI_API_KEY: "test-openai",
  VOICE_ENABLED: "true",
  INTERACTIVE_INLINE_ENABLED: "true",
  OPEN_SIGNUP: "true",
  PRACTICE_GATE: "true",
  FREE_REPS_PER_DAY: "3",
  FREE_REPS_LIFETIME: "3",
  FREE_VOICE_LIFETIME: "1",
  FREE_VOICE_TASTE_DAYS: "0",
  FREE_VOICE_SESSION_MINUTES: "10",
  PRO_REPS_PER_DAY: "10",
  PRO_GENERATIONS_PER_DAY: "20",
  PRO_VOICE_STARTS_PER_DAY: "20",
  PRO_VOICE_SESSION_MINUTES: "20",
  PRO_VOICE_MINUTES_PER_DAY: "60",
  PRO_VOICE_MINUTES_PER_WEEK: "75",
  APPLE_BUNDLE_ID: "dawi.drillbit",
  APPLE_PRODUCT_IDS: `${WEEKLY},${YEARLY}`,
  APPLE_ENVIRONMENT: undefined,
  DEVELOPER_ACCOUNTS: undefined,
  PRACTICE_UNLIMITED_ACCOUNTS: undefined,
  VOICE_UNLIMITED_ACCOUNTS: undefined,
} as unknown as Env;
const DB = bindings.DB;

// ---------- clock ----------
const at = (iso: string | number) => vi.setSystemTime(new Date(iso));
const tick = (seconds: number) => vi.setSystemTime(new Date(Date.now() + seconds * 1000));
const now = () => new Date().toISOString();
/**
 * The cron's reconcile sweeps every account in the D1 that all test files share: it requeues any job `running` for
 * more than two minutes. Run on the simulated clock, days ahead of the wall clock, that sweep would catch other files'
 * in-flight jobs. So it runs at the real time, as the deployed cron would; none of this file's jobs is ever left running.
 */
async function cron() {
  const simulated = Date.now();
  vi.useRealTimers();
  try { await reconcile(bindings); }
  finally { vi.useFakeTimers({ toFake: ["Date"] }); at(simulated); }
}

// ---------- Apple: a throwaway root → intermediate → leaf chain, valid all year whatever the fake clock says ----------
const alg = { name: "ECDSA", namedCurve: "P-256", hash: "SHA-256" } as const;
const b64 = (buffer: ArrayBuffer) => btoa(String.fromCharCode(...new Uint8Array(buffer)));
async function appleChain() {
  const notBefore = new Date("2026-01-01T00:00:00Z"), notAfter = new Date("2028-01-01T00:00:00Z");
  const rootKeys = await crypto.subtle.generateKey(alg, true, ["sign", "verify"]);
  const root = await X509CertificateGenerator.createSelfSigned({ serialNumber: "01", name: "CN=Week Root CA", notBefore, notAfter, signingAlgorithm: alg, keys: rootKeys });
  const midKeys = await crypto.subtle.generateKey(alg, true, ["sign", "verify"]);
  const mid = await X509CertificateGenerator.create({ serialNumber: "02", subject: "CN=Week Intermediate", issuer: root.subject, notBefore, notAfter, signingAlgorithm: alg, publicKey: midKeys.publicKey, signingKey: rootKeys.privateKey });
  const leafKeys = await crypto.subtle.generateKey(alg, true, ["sign", "verify"]);
  const leaf = await X509CertificateGenerator.create({ serialNumber: "03", subject: "CN=Week Leaf", issuer: mid.subject, notBefore, notAfter, signingAlgorithm: alg, publicKey: leafKeys.publicKey, signingKey: midKeys.privateKey });
  const sign = (payload: object) => new CompactSign(new TextEncoder().encode(JSON.stringify(payload)))
    .setProtectedHeader({ alg: "ES256", x5c: [b64(leaf.rawData), b64(mid.rawData), b64(root.rawData)] }).sign(leafKeys.privateKey);
  return { rootB64: b64(root.rawData), sign };
}
let apple: Awaited<ReturnType<typeof appleChain>>;

// ---------- providers ----------
const ai = {
  questions: 0,
  /** The concept the next feedback is about; set from the challenge being finished. */
  concept: "",
  signal: "needs_practice" as "needs_practice" | "demonstrated",
  voiceDown: false,
  calls: { generate: 0, interview: 0, summarize: 0, delegate: 0, voice: 0, clerk: 0 },
};
const QUOTE = "durable queue";
const ANSWERS = [
  "I would keep a durable queue between the API and the workers.",
  "Each job carries an idempotency key, so a retry never runs it twice.",
  "Workers acknowledge only after the write commits, so a crash just redelivers.",
  "Past a few retries the job moves to a dead letter queue someone can inspect.",
  "I would cap concurrency per tenant so one big customer can't starve the rest.",
  "Metrics on queue age tell us when to add workers before anyone notices.",
];
const SAID = ["I'd put a durable queue between the API and the workers.", "Then each job gets an idempotency key."];
function sse(content: object) {
  const frame = (value: object) => `data: ${JSON.stringify(value)}\n\n`;
  return new Response(frame({ choices: [{ delta: { content: JSON.stringify(content) } }] }) + frame({ choices: [], usage: { prompt_tokens: 20, completion_tokens: 20 } }) + "data: [DONE]\n\n",
    { status: 200, headers: { "content-type": "text/event-stream" } });
}
const completion = (content: object) => Response.json({ choices: [{ message: { content: JSON.stringify(content) } }], usage: { prompt_tokens: 20, completion_tokens: 20 } });
let realFetch: typeof fetch;
async function providers(request: RequestInfo | URL, init?: RequestInit): Promise<Response> {
  const url = typeof request === "string" ? request : request instanceof URL ? request.href : request.url;
  if (url === "https://openrouter.ai/api/v1/chat/completions") {
    const body = JSON.parse(String(init?.body));
    const properties = body.response_format?.json_schema?.schema?.properties ?? {};
    if (properties.primaryConceptId) {
      ai.calls.generate++;
      const n = ++ai.questions, concept = properties.primaryConceptId.const ?? properties.primaryConceptId.enum?.[0];
      return sse({
        kind: "design", targetSkill: "Reliable background work", topic: "System design", scenario: `Queue ${n}`, primaryConceptId: concept,
        ambiguityPolicy: "State assumptions.", minutes: 20, path: ["Pin down the jobs", "Sketch the queue", "Handle failures"],
        opener: "Let's start where it hurts. A worker can crash at any point. What should a client rely on?",
        title: `Background jobs, take ${n}`, prompt: `Design background job processing number ${n} that survives worker crashes.`, constraints: [],
        tagEvidence: [{ conceptId: concept, requirementIndex: 0 }],
      });
    }
    if (properties.summary) {
      ai.calls.summarize++;
      return completion({
        summary: "Solid queue thinking.", worked: ["Kept accepted work durable."], improve: "Say what happens to a duplicate.", takeaway: "Name the retry key.",
        strengths: ["durability"], gaps: ["duplicates"], nextExercise: "Explain a lost acknowledgement.",
        evidence: [{ conceptId: ai.concept, observation: "Kept accepted work durable.", quote: QUOTE, signal: ai.signal, assistance: "unknown",
          recall: { prompt: "Why put a durable queue in front of the workers?", answer: "So a worker crash never loses a job that was already accepted." } }],
        lesson: { learned: ["A durable queue survives a crash"], tryAlone: "Apply it to payment retries." },
        debrief: { verdict: "borderline", reason: "Durability is right; duplicates were never covered.", toPass: "Explain dedup.",
          signals: ["requirements", "design", "trade_offs", "communication"].map(area => ({ area, rating: "mixed", note: "Partly covered." })) },
      });
    }
    if (body.stream) { ai.calls.interview++; return sse({ move: "ask_one", text: "What happens when a worker dies halfway through a job?" }); }
    ai.calls.delegate++;
    return completion({ move: "ask_one", text: "Good. What stops a retry from running the job twice?" });
  }
  if (url === "https://api.openai.com/v1/live/sessions") {
    ai.calls.voice++;
    return ai.voiceDown ? new Response("busy", { status: 503 }) : Response.json({ session: { id: "live_" + crypto.randomUUID() }, transport: { sdp: "answer" } }, { status: 201 });
  }
  if (url.startsWith("https://api.clerk.com/v1/users/")) { ai.calls.clerk++; return Response.json({ deleted: true }); }
  return realFetch(request, init);
}

// ---------- HTTP ----------
let key: CryptoKey;
type User = { subject: string; id: string };
type Reply = { status: number; body: any };
async function call(user: Pick<User, "subject">, method: string, path: string, body?: unknown, command: string = crypto.randomUUID()): Promise<Reply> {
  // Every request happens a little after the last, so rows never share a timestamp.
  tick(2);
  const token = await new SignJWT({}).setProtectedHeader({ alg: "RS256", kid: "week" }).setSubject(user.subject)
    .setIssuer(ISSUER).setAudience("drillbit").setIssuedAt().setExpirationTime("5m").sign(key);
  const ctx = createExecutionContext();
  const response = await app.fetch(new Request("https://api.test" + path, {
    method, headers: { "Content-Type": "application/json", Authorization: "Bearer " + token, "Idempotency-Key": command },
    body: body === undefined ? undefined : JSON.stringify(body),
  }), bindings, ctx);
  await waitOnExecutionContext(ctx);
  const text = await response.text();
  return { status: response.status, body: text ? JSON.parse(text) : null };
}
async function notify(payload: object): Promise<Reply> {
  tick(2);
  const ctx = createExecutionContext();
  const response = await app.fetch(new Request("https://api.test/apple/notifications", {
    method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ signedPayload: await apple.sign(payload) }),
  }), bindings, ctx);
  await waitOnExecutionContext(ctx);
  return { status: response.status, body: await response.json() };
}
type Claims = Record<string, unknown> & { originalTransactionId: string };
async function subscribe(user: User, productId: string, purchaseDate: number, expiresDate: number) {
  const claims: Claims = { bundleId: "dawi.drillbit", productId, originalTransactionId: crypto.randomUUID(), transactionId: crypto.randomUUID(),
    type: "Auto-Renewable Subscription", environment: "Sandbox", purchaseDate, expiresDate, signedDate: Date.now() };
  const reply = await call(user, "POST", "/v1/entitlement", { signedTransaction: await apple.sign(claims) });
  return { reply, claims };
}
/** An App Store Server Notification V2 about a known subscription, signed now. */
async function appStore(notificationType: string, subtype: string | undefined, claims: Claims, changes: object, renewal?: object) {
  const transaction = { ...claims, transactionId: crypto.randomUUID(), ...changes, signedDate: Date.now() };
  return notify({ notificationType, ...(subtype ? { subtype } : {}), signedDate: Date.now(), notificationUUID: crypto.randomUUID(),
    data: { bundleId: "dawi.drillbit", environment: "Sandbox", signedTransactionInfo: await apple.sign(transaction), ...(renewal ? { signedRenewalInfo: await apple.sign(renewal) } : {}) } });
}
async function signUp(timezone: string): Promise<User> {
  const subject = "user_" + crypto.randomUUID();
  const first = await call({ subject }, "GET", "/v1/bootstrap");
  expect(first.status).toBe(200);
  const user = { subject, id: first.body.account.id as string };
  const saved = await call(user, "PUT", "/v1/settings", { timezone, onboardingComplete: true, engineeringLevel: "mid", dailyMinutes: 480, reminderEnabled: true });
  expect(saved.status).toBe(200);
  expect(saved.body).toMatchObject({ timezone, onboardingComplete: true, engineeringLevel: "mid" });
  return user;
}
const bootstrap = async (user: User) => { const r = await call(user, "GET", "/v1/bootstrap"); expect(r.status).toBe(200); return r.body; };
const challenge = async (user: User, id: string) => { const r = await call(user, "GET", `/v1/challenges/${id}`); expect(r.status).toBe(200); return r.body; };
const voiceCapability = async (user: User) => (await bootstrap(user)).capabilities.voice;
const usage = async (account: string, kind: string, day: string) =>
  (await DB.prepare("SELECT count FROM usage WHERE account_id=? AND day=? AND kind=?").bind(account, day, kind).first<{ count: number }>())?.count ?? 0;
const jobStatus = async (id: string) => (await DB.prepare("SELECT status FROM jobs WHERE id=?").bind(id).first<{ status: string }>())?.status;
const lifecycle = async (id: string) => (await DB.prepare("SELECT lifecycle FROM challenges WHERE id=?").bind(id).first<{ lifecycle: string }>())?.lifecycle;

// ---------- practice ----------
/** POST /v1/challenges, run inline, and the ready question it wrote. */
async function prepare(user: User, body: object = {}) {
  const reply = await call(user, "POST", "/v1/challenges", body);
  expect(reply.status, JSON.stringify(reply.body)).toBe(202);
  expect(await jobStatus(reply.body.id)).toBe("completed");
  expect(await lifecycle(reply.body.id)).toBe("ready");
  return reply.body.id as string;
}
async function answer(user: User, id: string, text: string) {
  const d = await challenge(user, id);
  const promptId = d.interview.turns.filter((t: any) => ["answer", "continue"].includes(t.kind) && t.result).at(-1)?.id ?? "original";
  return call(user, "POST", `/v1/challenges/${id}/interview`, { kind: "answer", text, revision: d.session.revision, saveDraft: true, promptId });
}
async function practise(user: User, id: string, answers = 2) {
  expect((await call(user, "POST", `/v1/challenges/${id}/start`)).status).toBe(200);
  for (let i = 0; i < answers; i++) {
    const reply = await answer(user, id, ANSWERS[i % ANSWERS.length]);
    expect(reply.status, JSON.stringify(reply.body)).toBe(202);
  }
  const turns = (await challenge(user, id)).interview.turns.filter((t: any) => t.kind === "answer");
  expect(turns).toHaveLength(answers);
  expect(turns.every((t: any) => t.status === "completed" && t.result?.outcome === "follow_up")).toBe(true);
}
/** Finish and read the feedback the summarize job wrote, grounded in the person's own words. */
async function finish(user: User, id: string, signal: typeof ai.signal = "needs_practice") {
  const before = await challenge(user, id);
  ai.concept = before.primaryConceptId; ai.signal = signal;
  const reply = await call(user, "POST", `/v1/challenges/${id}/complete`, { answer: "", revision: before.session.revision });
  expect(reply.status, JSON.stringify(reply.body)).toBe(200);
  const done = await challenge(user, id);
  expect(done.lifecycle).toBe("completed");
  expect(done.reflection).toMatchObject({ summary: "Solid queue thinking.", evidence: [{ conceptId: before.primaryConceptId, quote: QUOTE, signal }] });
  expect(await DB.prepare("SELECT due_at FROM recall_cards WHERE id=? AND account_id=?").bind(`${id}:${before.primaryConceptId}`, user.id).first()).not.toBeNull();
  return done;
}
async function rep(user: User, answers = 2, signal: typeof ai.signal = "needs_practice") {
  const id = await prepare(user);
  await practise(user, id, answers);
  return finish(user, id, signal);
}
async function startVoice(user: User, id: string) {
  const d = await challenge(user, id);
  return call(user, "POST", `/v1/challenges/${id}/voice`, { sdp: "offer", revision: d.session.revision });
}
/** One voice session: the interviewer speaks, the person says `said`, optionally one delegation, then a confirmed close
 * `seconds` after the session started, reporting `reported` billed seconds. */
async function voiceSession(user: User, id: string, { seconds, reported, said = [], delegate = false }: { seconds: number; reported: number; said?: string[]; delegate?: boolean }) {
  const started = await startVoice(user, id);
  expect(started.status, JSON.stringify(started.body)).toBe(201);
  const sid = started.body.id as string;
  const row = await DB.prepare("SELECT created_at,provider_id,status FROM voice_sessions WHERE id=? AND account_id=?").bind(sid, user.id).first<{ created_at: string; provider_id: string; status: string }>();
  expect(row).toMatchObject({ status: "active", provider_id: expect.stringMatching(/^live_/) });
  const fragments = [{ id: "a0", sequence: 0, speaker: "assistant", text: "Where do the jobs wait?", startMs: 0, endMs: 1500 },
    ...said.map((text, i) => ({ id: "u" + i, sequence: i + 1, speaker: "user", text, startMs: 2000 + i * 4000, endMs: 5500 + i * 4000 }))];
  expect((await call(user, "POST", `/v1/challenges/${id}/voice/${sid}/events`, { fragments })).status).toBe(200);
  if (delegate) {
    const delegated = await call(user, "POST", `/v1/challenges/${id}/voice/${sid}/delegate`, { id: "delegation-1" });
    expect(delegated.status, JSON.stringify(delegated.body)).toBe(200);
    expect(delegated.body).toEqual({ text: "Good. What stops a retry from running the job twice?" });
  }
  at(Date.parse(row!.created_at) + seconds * 1000 - 2000);
  const closed = await call(user, "POST", `/v1/challenges/${id}/voice/${sid}/events`, { fragments: [], closed: true, finalized: true, usageSeconds: reported });
  expect(closed.status, JSON.stringify(closed.body)).toBe(200);
  return { id: sid, createdAt: row!.created_at, sessionSeconds: started.body.sessionSeconds as number, expiresAt: started.body.expiresAt as string };
}
const voiceRow = (id: string) => DB.prepare("SELECT status,provider_id,usage_seconds,waived FROM voice_sessions WHERE id=?").bind(id).first<{ status: string; provider_id: string | null; usage_seconds: number | null; waived: number }>();

// ---------- invariants ----------
/** Nothing left running or failed, nothing sent to the Workflow, and every job and voice session belongs to its challenge's account. */
async function endOfDay(users: User[]) {
  const ids = users.map(u => u.id), slots = ids.map(() => "?").join(",");
  const open = await DB.prepare(`SELECT account_id,kind,status FROM jobs WHERE account_id IN (${slots}) AND status IN ('pending','running','failed')`).bind(...ids).all();
  expect(open.results).toEqual([]);
  const crossed = await DB.prepare(`SELECT
    (SELECT COUNT(*) FROM jobs j JOIN challenges c ON c.id=j.challenge_id WHERE j.account_id IN (${slots}) AND j.account_id<>c.account_id)
    + (SELECT COUNT(*) FROM voice_sessions v JOIN challenges c ON c.id=v.challenge_id WHERE v.account_id IN (${slots}) AND v.account_id<>c.account_id)
    + (SELECT COUNT(*) FROM recall_cards r JOIN challenges c ON c.id=r.source_challenge_id WHERE r.account_id IN (${slots}) AND r.account_id<>c.account_id) n`)
    .bind(...ids, ...ids, ...ids).first<{ n: number }>();
  expect(crossed!.n).toBe(0);
  const workflow = dispatched.length ? await DB.prepare(`SELECT id,kind FROM jobs WHERE account_id IN (${slots}) AND id IN (${dispatched.map(() => "?").join(",")})`).bind(...ids, ...dispatched).all() : { results: [] };
  expect(workflow.results).toEqual([]);
}
/** Home, Library, Recall, history and the Bit map agree with each other and with the reps finished so far. */
async function consistent(user: User, finished: { id: string; completedAt: string }[]) {
  const boot = await bootstrap(user), recall = (await call(user, "GET", "/v1/recall")).body, memory = (await call(user, "GET", "/v1/memory")).body;
  const n = finished.length;
  expect(boot.todayPlan.dueRecallCount).toBe(recall.dueCount);
  expect(recall.dueCount).toBe(recall.cards.filter((c: any) => c.dueAt <= now()).length);
  expect(recall.cards).toHaveLength(n);
  expect(boot.todayPlan.completedTotal).toBe(n);
  expect(boot.todayPlan.nextTicket).toBe(n + 1);
  expect(memory.statistics.completed).toBe(n);
  expect(memory.statistics.lastSevenDays).toBe(finished.filter(f => Date.parse(f.completedAt) >= Date.now() - 7 * DAY).length);
  expect(memory.sessions.map((s: any) => s.id).sort()).toEqual(finished.map(f => f.id).sort());
  expect(memory.sessions.map((s: any) => s.ticket).sort((a: number, b: number) => a - b)).toEqual(Array.from({ length: n }, (_, i) => i + 1));
  const library: any[] = [];
  for (let cursor: string | null = ""; cursor !== null;) {
    const page: any = (await call(user, "GET", "/v1/library" + (cursor ? "?cursor=" + encodeURIComponent(cursor) : ""))).body;
    library.push(...page.questions); cursor = page.nextCursor;
  }
  expect(library).toHaveLength(n);
  const coverage = (await call(user, "GET", "/v1/library/coverage")).body.concepts as { completedAttempts: number }[];
  expect(coverage.reduce((total, c) => total + c.completedAttempts, 0)).toBe(n);
  const history = (await call(user, "GET", "/v1/sessions")).body;
  expect(history.sessions).toHaveLength(Math.min(25, n));
  return { boot, recall, memory };
}

beforeAll(async () => {
  vi.useFakeTimers({ toFake: ["Date"] });
  at("2026-11-08T17:00:00Z");
  await initializeDatabase(DB);
  apple = await appleChain();
  bindings.APPLE_ROOT_CERTS = apple.rootB64;
  const pair = await generateKeyPair("RS256");
  key = pair.privateKey;
  fetchMock.activate();
  fetchMock.disableNetConnect();
  fetchMock.get(ISSUER).intercept({ path: "/.well-known/jwks.json" })
    .reply(200, { keys: [{ ...(await exportJWK(pair.publicKey)), kid: "week", alg: "RS256" }] }).persist();
  realFetch = globalThis.fetch.bind(globalThis);
  vi.spyOn(globalThis, "fetch").mockImplementation(providers as typeof fetch);
});
afterAll(() => {
  vi.restoreAllMocks();
  vi.useRealTimers();
  fetchMock.deactivate();
});

describe("a Pro subscriber's week (America/Los_Angeles, UTC-8, no DST change)", () => {
  // Pacific time: the local day starts at 08:00 UTC and the UTC day (which meters reps, questions and voice) at 16:00 local.
  let A: User, B: User;
  let weekly: Claims;
  const finishedA: { id: string; completedAt: string }[] = [];
  const finishedB: { id: string; completedAt: string }[] = [];
  const done = (list: typeof finishedA, d: any) => list.push({ id: d.id, completedAt: d.completedAt });
  const voice: Record<string, { id: string; createdAt: string }> = {};
  let day0Cards: string[] = [];

  it("day 0 (Sun 10:00): signs up, onboards, spends a free rep, buys the weekly plan and is Pro", async () => {
    at("2026-11-08T18:00:00Z");
    A = await signUp("America/Los_Angeles");
    let boot = await bootstrap(A);
    expect(boot.account).toMatchObject({ status: "active", plan: "free" });
    expect(boot.practice).toMatchObject({ plan: "free", freeReps: true, lifetime: true, limit: 3, remaining: 3, available: true });
    expect(boot.settings).toMatchObject({ timezone: "America/Los_Angeles", onboardingComplete: true });
    // Free accounts get no automatic question, and the visit claims today's local day.
    const visit = await call(A, "POST", "/v1/daily-question", {});
    expect(visit.status).toBe(200);
    expect(visit.body).toEqual({ day: "2026-11-08" });
    // The first rep is a free one.
    const free = await call(A, "POST", "/v1/challenges", {});
    expect(free.status).toBe(202);
    expect(JSON.parse((await DB.prepare("SELECT input FROM jobs WHERE id=?").bind(free.body.id).first<{ input: string }>())!.input).freeRepAt).toBeTruthy();
    await practise(A, free.body.id);
    done(finishedA, await finish(A, free.body.id));
    expect((await bootstrap(A)).practice).toMatchObject({ plan: "free", remaining: 2 });

    // Buys the weekly plan; the server verifies the signed transaction and answers with the plan.
    const purchase = Date.now();
    const bought = await subscribe(A, WEEKLY, purchase, purchase + 7 * DAY);
    weekly = bought.claims;
    expect(bought.reply.status).toBe(200);
    expect(bought.reply.body).toMatchObject({ plan: "pro", entitlement: { productId: WEEKLY, status: "active", activeUntil: new Date(purchase + 7 * DAY).toISOString() } });
    boot = await bootstrap(A);
    expect(boot.account.plan).toBe("pro");
    expect(boot.practice).toEqual({ plan: "pro", freeReps: false, available: true, nextFreeRepAt: null });
    expect(boot.capabilities.voice).toMatchObject({ available: true, plan: "pro", sessionSeconds: 20 * 60 });
    expect(boot.capabilities.voice).not.toHaveProperty("remaining");
    // Today's automatic question was already claimed by the free visit; Pro starts with tomorrow's.
    expect((await call(A, "POST", "/v1/daily-question", {})).body).toEqual({ day: "2026-11-08" });

    // A Pro rep carries no free-rep stamp.
    const pro = await call(A, "POST", "/v1/challenges", {});
    expect(pro.status).toBe(202);
    expect(JSON.parse((await DB.prepare("SELECT input FROM jobs WHERE id=?").bind(pro.body.id).first<{ input: string }>())!.input).freeRepAt).toBeUndefined();
    await practise(A, pro.body.id);
    done(finishedA, await finish(A, pro.body.id));
    expect((await bootstrap(A)).practice.freeReps).toBe(false);

    // A second subscriber, on the yearly plan, practises alongside all week.
    tick(600);
    B = await signUp("Europe/Berlin");
    expect((await subscribe(B, YEARLY, Date.now(), Date.now() + 365 * DAY)).reply.body).toMatchObject({ plan: "pro" });
    done(finishedB, await rep(B));

    const { recall } = await consistent(A, finishedA);
    // Both reps left something worth practising, so both cards are due at once.
    expect(recall.dueCount).toBe(2);
    day0Cards = recall.cards.map((c: any) => c.id);
    await consistent(B, finishedB);
    await endOfDay([A, B]);
  });

  it("day 1 (Mon 07:30): the daily question, Recall from yesterday, and a voice rep that uses up the 60-minute day", async () => {
    at("2026-11-09T15:30:00Z");
    const generations = async () => (await DB.prepare("SELECT COUNT(*) n FROM jobs WHERE account_id=? AND kind='generate'").bind(A.id).first<{ n: number }>())!.n;
    const before = await generations();
    await cron();
    expect(await generations()).toBe(before);
    const daily = await call(A, "POST", "/v1/daily-question", {});
    expect(daily.status).toBe(200);
    expect(daily.body.day).toBe("2026-11-09");
    expect(daily.body.job).toMatchObject({ kind: "generate" });
    const id = daily.body.job.id as string;
    expect(await lifecycle(id)).toBe("ready");
    // A second device the same morning gets the same question and no new generation.
    expect((await call(A, "POST", "/v1/daily-question", {})).body).toMatchObject({ day: "2026-11-09", challenge: { id, lifecycle: "ready" } });
    expect(await generations()).toBe(before + 1);
    expect((await bootstrap(A)).todayPlan).toMatchObject({ state: "review_due", dueRecallCount: 2 });

    // Recall: yesterday's cards, both remembered.
    for (const card of day0Cards) {
      const reviewed = await call(A, "POST", `/v1/recall/${card}/review`, { rating: "got_it", responseMs: 4000 });
      expect(reviewed.status).toBe(200);
      expect(reviewed.body.card).toMatchObject({ intervalDays: 1, repetitions: 1 });
      expect(Date.parse(reviewed.body.card.dueAt) - Date.now()).toBe(DAY);
    }
    expect((await call(A, "GET", "/v1/recall")).body.dueCount).toBe(0);

    expect((await call(A, "POST", `/v1/challenges/${id}/start`)).status).toBe(200);
    expect(await voiceCapability(A)).toMatchObject({ available: true, plan: "pro", sessionSeconds: 1200 });
    const today = "2026-11-09";
    // The provider never creates a session: the start is refunded and no minutes are counted.
    ai.voiceDown = true;
    const failed = await startVoice(A, id);
    ai.voiceDown = false;
    expect(failed.status).toBe(502);
    expect(failed.body.error.code).toBe("voice_provider");
    expect(await usage(A.id, "voice_start", today)).toBe(0);
    expect(await voiceRow((await DB.prepare("SELECT id FROM voice_sessions WHERE account_id=?").bind(A.id).first<{ id: string }>())!.id)).toMatchObject({ status: "uncertain", provider_id: null });

    // Two silent looks a day are free and give their start back; the third silent one is billed.
    for (const look of ["lookA", "lookB"]) {
      voice[look] = await voiceSession(A, id, { seconds: 30, reported: 30 });
      expect(await voiceRow(voice[look].id)).toMatchObject({ status: "closed", waived: 1 });
      expect(await usage(A.id, "voice_start", today)).toBe(0);
    }
    voice.lookC = await voiceSession(A, id, { seconds: 29, reported: 30 });
    expect(await voiceRow(voice.lookC.id)).toMatchObject({ waived: 0, usage_seconds: 30 });
    expect(await usage(A.id, "voice_start", today)).toBe(1);

    // Two full 20-minute sessions with speech, one delegation to the backend interviewer.
    voice.s1 = await voiceSession(A, id, { seconds: 1199, reported: 1200, said: SAID, delegate: true });
    expect(await usage(A.id, "voice_reasoning", today)).toBe(1);
    expect(ai.calls.delegate).toBe(1);
    voice.s2 = await voiceSession(A, id, { seconds: 1199, reported: 1200, said: ["The queue keeps jobs if a worker dies."] });
    // 2,430 seconds today: the next session is trimmed to what's left of the day.
    expect(await voiceCapability(A)).toMatchObject({ available: true, sessionSeconds: 1170 });
    voice.s3 = await voiceSession(A, id, { seconds: 1169, reported: 1170, said: ["Retries carry the same key."] });
    expect(voice.s3.sessionSeconds).toBe(1170);
    expect(Date.parse(voice.s3.expiresAt) - Date.parse(voice.s3.createdAt)).toBe((1170 + 30) * 1000);
    expect(await voiceCapability(A)).toMatchObject({ available: false, plan: "pro", reason: "That’s a lot of talking for one day. Voice is back tomorrow.", resetsAt: "2026-11-10T00:00:00.000Z" });
    const refused = await startVoice(A, id);
    expect(refused.status).toBe(429);
    expect(refused.body.error).toMatchObject({ code: "usage_limit", message: "That’s a lot of talking for one day. Voice is back tomorrow." });
    expect(await usage(A.id, "voice_start", today)).toBe(4);

    // The spoken rep gets feedback quoting what was said; this time the idea held up.
    const spoken = await finish(A, id, "demonstrated");
    done(finishedA, spoken);
    expect(spoken.interview.turns.filter((t: any) => t.kind === "voice" && t.voice?.some((f: any) => f.speaker === "user"))).toHaveLength(3);
    const card = (await call(A, "GET", "/v1/recall")).body.cards.find((c: any) => c.sourceChallengeId === id);
    expect(Date.parse(card.dueAt) - Date.parse(spoken.completedAt)).toBe(3 * DAY);

    // B's minutes are B's own.
    const bRep = await prepare(B);
    expect((await call(B, "POST", `/v1/challenges/${bRep}/start`)).status).toBe(200);
    expect(await voiceCapability(B)).toMatchObject({ available: true, sessionSeconds: 1200 });
    await voiceSession(B, bRep, { seconds: 599, reported: 600, said: SAID });
    done(finishedB, await finish(B, bRep));

    await consistent(A, finishedA);
    await consistent(B, finishedB);
    await endOfDay([A, B]);
  });

  it("day 2 (Tue): the rolling week trims and then pauses voice; ten practised reps, then the cap until UTC midnight", async () => {
    at("2026-11-10T16:00:00Z");
    const daily = await call(A, "POST", "/v1/daily-question", {});
    expect(daily.body).toMatchObject({ day: "2026-11-10", job: { kind: "generate" } });
    const id = daily.body.job.id as string;

    // Yesterday's two cards are due again: one remembered, one forgotten.
    const deck = (await call(A, "GET", "/v1/recall")).body;
    expect(deck.cards.filter((c: any) => c.dueAt <= now()).map((c: any) => c.id).sort()).toEqual([...day0Cards].sort());
    const kept = await call(A, "POST", `/v1/recall/${day0Cards[0]}/review`, { rating: "got_it" });
    expect(kept.body.card).toMatchObject({ intervalDays: 3, repetitions: 2 });
    const forgot = await call(A, "POST", `/v1/recall/${day0Cards[1]}/review`, { rating: "again" });
    expect(forgot.body.card).toMatchObject({ intervalDays: 0, repetitions: 0, lapses: 1 });
    expect(Date.parse(forgot.body.card.dueAt) - Date.now()).toBe(5 * 60_000);

    // 60 of the week's 75 minutes went yesterday: today's first session is cut to the 15 left.
    expect(await voiceCapability(A)).toEqual({ available: true, plan: "pro", checkedAt: expect.any(String), sessionSeconds: 900 });
    expect((await call(A, "POST", `/v1/challenges/${id}/start`)).status).toBe(200);
    // The app under-reports, but a close counts at least the time from start to close.
    voice.s4 = await voiceSession(A, id, { seconds: 900, reported: 600, said: SAID });
    expect(voice.s4.sessionSeconds).toBe(900);
    expect((await voiceRow(voice.s4.id))!.usage_seconds).toBeCloseTo(900, 2);
    // Monday's 30-second look leaving frees less than a minute; voice is back when the first full session leaves.
    const back = new Date(Date.parse(voice.s1.createdAt) + 7 * DAY).toISOString();
    const paused = await voiceCapability(A);
    expect(paused).toMatchObject({ available: false, plan: "pro", reason: "That’s a big week of talking. Voice is back Monday.", resetsAt: back });
    const refused = await startVoice(A, id);
    expect(refused.status).toBe(429);
    expect(refused.body.error).toMatchObject({ code: "usage_limit", message: "That’s a big week of talking. Voice is back Monday." });
    done(finishedA, await finish(A, id));
    // B still has a full session.
    expect(await voiceCapability(B)).toMatchObject({ available: true, sessionSeconds: 1200 });

    // Reps 2 to 9 of the UTC day, typed.
    for (let i = 2; i <= 9; i++) done(finishedA, await rep(A));
    // The tenth: once it's practised the cap is reached, but an open rep always finishes.
    const tenth = await prepare(A);
    await practise(A, tenth, 2);
    expect((await answer(A, tenth, ANSWERS[2])).status).toBe(202);
    const tenthDone = await finish(A, tenth);
    done(finishedA, tenthDone);
    const generateToday = await usage(A.id, "generate", "2026-11-10");
    expect(generateToday).toBe(10);

    // The eleventh rep is refused wherever a rep can start: preparation, Library and a moment retry.
    const limit = { code: "practice_limit", message: "That’s 10 reps today, which is plenty. More tomorrow." };
    const eleventh = await call(A, "POST", "/v1/challenges", {});
    expect(eleventh.status).toBe(429);
    expect(eleventh.body.error).toMatchObject(limit);
    const question = (await call(A, "GET", "/v1/library")).body.questions[0].id;
    const library = await call(A, "POST", `/v1/questions/${question}/start`);
    expect(library.status).toBe(429);
    expect(library.body.error).toMatchObject(limit);
    const moment = tenthDone.interview.turns.find((t: any) => t.kind === "answer").id;
    const retry = await call(A, "POST", `/v1/challenges/${tenth}/retry-moment/${moment}`);
    expect(retry.status).toBe(429);
    expect(retry.body.error).toMatchObject(limit);
    // Refusals spend nothing and start nothing.
    expect(await usage(A.id, "generate", "2026-11-10")).toBe(generateToday);
    expect((await bootstrap(A)).challenge).toBeNull();
    // The cap is A's: B keeps practising.
    done(finishedB, await rep(B));

    // The forgotten card is back five minutes later; remembered now, it starts over at one day.
    const relearned = await call(A, "POST", `/v1/recall/${day0Cards[1]}/review`, { rating: "got_it" });
    expect(relearned.body.card).toMatchObject({ intervalDays: 1, repetitions: 1, lapses: 1 });

    // 16:30 in Los Angeles is past UTC midnight: the rep cap has reset, though it's still the same local day.
    at("2026-11-11T00:30:00Z");
    const evening = await rep(A);
    done(finishedA, evening);
    const { boot } = await consistent(A, finishedA);
    expect(boot.todayPlan.completedToday).toBe(11);
    expect(await usage(A.id, "generate", "2026-11-11")).toBe(1);
    await consistent(B, finishedB);
    await endOfDay([A, B]);
  });

  it("day 3 (Wed): cron creates nothing; the daily question plus rerolls hit the 20 questions a day, voice stays paused", async () => {
    at("2026-11-11T16:00:00Z");
    const before = (await DB.prepare("SELECT COUNT(*) n FROM jobs WHERE account_id=?").bind(A.id).first<{ n: number }>())!.n;
    await cron();
    expect((await DB.prepare("SELECT COUNT(*) n FROM jobs WHERE account_id=?").bind(A.id).first<{ n: number }>())!.n).toBe(before);
    const daily = await call(A, "POST", "/v1/daily-question", {});
    expect(daily.status, JSON.stringify(daily.body)).toBe(200);
    expect(daily.body).toMatchObject({ day: "2026-11-11", job: { kind: "generate" } });
    expect(JSON.parse((await DB.prepare("SELECT input FROM jobs WHERE id=?").bind(daily.body.job.id).first<{ input: string }>())!.input).availableAt).toBeUndefined();
    let current = daily.body.job.id as string;
    // Last night's rep was the first question of this UTC day; the daily question is the second.
    expect(await usage(A.id, "generate", "2026-11-11")).toBe(2);
    // Eighteen rerolls: a reroll isn't a new rep, so only the question cap applies.
    for (let i = 0; i < 18; i++) {
      const previous = current;
      current = await prepare(A, { replaceId: previous });
      expect(await lifecycle(previous)).toBe("expired");
    }
    expect(await usage(A.id, "generate", "2026-11-11")).toBe(20);
    const capped = await call(A, "POST", "/v1/challenges", { replaceId: current });
    expect(capped.status).toBe(429);
    expect(capped.body.error).toEqual(expect.objectContaining({ code: "usage_limit", message: "That’s a lot of new questions for one day. Practise one you’ve got, or more tomorrow." }));
    expect(await lifecycle(current)).toBe("ready");
    expect(await usage(A.id, "generate", "2026-11-11")).toBe(20);
    // The one kept is practised; rerolled questions never reach Library.
    await practise(A, current);
    done(finishedA, await finish(A, current));

    const paused = await voiceCapability(A);
    expect(paused).toMatchObject({ available: false, reason: "That’s a big week of talking. Voice is back Monday." });
    // Monday's spoken rep only becomes due for Recall three days after it was finished.
    const spokenCard = (await call(A, "GET", "/v1/recall")).body.cards.find((c: any) => c.sourceChallengeId === finishedA[2].id);
    expect(spokenCard.dueAt > now()).toBe(true);
    await consistent(A, finishedA);
    await endOfDay([A, B]);
  });

  it("day 4 (Thu): Monday's card comes due; tonight's rep is saved to shape tomorrow's question", async () => {
    at("2026-11-12T17:30:00Z");
    const daily = await call(A, "POST", "/v1/daily-question", {});
    expect(daily.body).toMatchObject({ day: "2026-11-12", job: { kind: "generate" } });
    const deck = (await call(A, "GET", "/v1/recall")).body;
    const spokenCard = deck.cards.find((c: any) => c.sourceChallengeId === finishedA[2].id);
    expect(spokenCard.dueAt <= now()).toBe(true);
    expect((await call(A, "POST", `/v1/recall/${spokenCard.id}/review`, { rating: "got_it" })).body.card).toMatchObject({ intervalDays: 1 });
    await practise(A, daily.body.job.id);
    const today = await finish(A, daily.body.job.id);
    done(finishedA, today);
    const queued = await call(A, "PUT", `/v1/challenges/${today.id}/next`);
    expect(queued.status).toBe(200);
    expect(queued.body.queuedNext).toMatchObject({ sourceId: today.id, conceptId: today.primaryConceptId });
    expect((await bootstrap(A)).queuedNext).toMatchObject({ sourceId: today.id });
    await consistent(A, finishedA);
    await endOfDay([A, B]);
  });

  it("day 5 (Fri): the daily question builds on yesterday's rep exactly once; voice is still paused until Monday", async () => {
    at("2026-11-13T17:00:00Z");
    const source = finishedA.at(-1)!.id;
    const daily = await call(A, "POST", "/v1/daily-question", {});
    expect(daily.body).toMatchObject({ day: "2026-11-13", job: { kind: "generate" } });
    const input = JSON.parse((await DB.prepare("SELECT input FROM jobs WHERE id=?").bind(daily.body.job.id).first<{ input: string }>())!.input);
    expect(input).toMatchObject({ followUpId: source, followUp: { question: { id: source } } });
    expect((await bootstrap(A)).queuedNext).toBeNull();
    await practise(A, daily.body.job.id);
    done(finishedA, await finish(A, daily.body.job.id));
    // Day 0's first card, remembered on Tuesday, is due again three days later.
    const card = (await call(A, "GET", "/v1/recall")).body.cards.find((c: any) => c.id === day0Cards[0]);
    expect(card.dueAt <= now()).toBe(true);
    expect((await call(A, "POST", `/v1/recall/${card.id}/review`, { rating: "got_it" })).body.card).toMatchObject({ intervalDays: 7, repetitions: 3 });
    expect(await voiceCapability(A)).toMatchObject({ available: false, reason: "That’s a big week of talking. Voice is back Monday." });
    expect(await voiceCapability(B)).toMatchObject({ available: true });
    await consistent(A, finishedA);
    await endOfDay([A, B]);
  });

  it("day 7 (Sun): one question after a day away, no backlog; the weekly renewal keeps Pro", async () => {
    // Saturday: the app was never opened.
    at("2026-11-15T17:00:00Z");
    await cron();
    const daily = await call(A, "POST", "/v1/daily-question", {});
    expect(daily.body).toMatchObject({ day: "2026-11-15", job: { kind: "generate" } });
    expect((await call(A, "POST", "/v1/daily-question", {})).body).toMatchObject({ challenge: { id: daily.body.job.id } });
    const visits = await DB.prepare("SELECT local_day FROM daily_visits WHERE account_id=? ORDER BY local_day").bind(A.id).all<{ local_day: string }>();
    expect(visits.results.map(v => v.local_day)).toEqual(["2026-11-08", "2026-11-09", "2026-11-10", "2026-11-11", "2026-11-12", "2026-11-13", "2026-11-15"]);
    const automatic = await DB.prepare("SELECT COUNT(*) n FROM jobs WHERE account_id=? AND kind='generate' AND created_at>=?").bind(A.id, "2026-11-14T08:00:00.000Z").first<{ n: number }>();
    expect(automatic!.n).toBe(1);

    // The paid week runs to 18:00 UTC; Apple renews just before and tells the server.
    expect((await bootstrap(A)).account.plan).toBe("pro");
    const original = await DB.prepare("SELECT active_until FROM entitlements WHERE account_id=?").bind(A.id).first<{ active_until: string }>();
    at("2026-11-15T17:59:00Z");
    const renewed = await appStore("DID_RENEW", undefined, weekly, { purchaseDate: Date.parse(original!.active_until), expiresDate: Date.parse(original!.active_until) + 7 * DAY });
    expect(renewed).toEqual({ status: 200, body: { applied: true, notificationType: "DID_RENEW" } });
    expect(await DB.prepare("SELECT status,active_until FROM entitlements WHERE account_id=?").bind(A.id).first()).toEqual({ status: "active", active_until: new Date(Date.parse(original!.active_until) + 7 * DAY).toISOString() });
    // Past the old expiry, still Pro, and the receipt the app posts again changes nothing.
    at("2026-11-15T18:30:00Z");
    expect((await bootstrap(A)).account.plan).toBe("pro");
    expect((await call(A, "POST", "/v1/entitlement", { signedTransaction: await apple.sign({ ...weekly, signedDate: Date.parse("2026-11-08T18:00:00Z") }) })).body).toMatchObject({ plan: "pro" });
    await practise(A, daily.body.job.id);
    done(finishedA, await finish(A, daily.body.job.id));
    expect(await voiceCapability(A)).toMatchObject({ available: false, reason: "That’s a big week of talking. Voice is back Monday." });
    await consistent(A, finishedA);
    await endOfDay([A, B]);
  });

  it("day 8 (Mon): voice comes back as the rolling week moves past Monday's sessions", async () => {
    // The paused capability promised voice back when enough of Monday's sessions rolled out of the window.
    const promised = Date.parse(voice.s1.createdAt) + 7 * DAY;
    at(promised + 1000);
    expect.soft(await voiceCapability(A), "voice is available at the resetsAt it promised").toMatchObject({ available: true });
    // Once Monday's full sessions are out of the window, a whole session is back.
    at(Date.parse(voice.s1.createdAt) + 7 * DAY + 1000);
    expect(await voiceCapability(A)).toMatchObject({ available: true, sessionSeconds: 1200 });
    const daily = await call(A, "POST", "/v1/daily-question", {});
    expect(daily.body).toMatchObject({ day: "2026-11-16", job: { kind: "generate" } });
    const id = daily.body.job.id as string;
    expect((await call(A, "POST", `/v1/challenges/${id}/start`)).status).toBe(200);
    await voiceSession(A, id, { seconds: 299, reported: 300, said: SAID });
    done(finishedA, await finish(A, id));
    // Voice starts and counted sessions agree, day by day: refunded and waived starts were given back.
    const perDay = await DB.prepare("SELECT substr(created_at,1,10) day,COUNT(*) n FROM voice_sessions WHERE account_id=? AND provider_id IS NOT NULL AND waived=0 GROUP BY 1").bind(A.id).all<{ day: string; n: number }>();
    for (const row of perDay.results) expect(await usage(A.id, "voice_start", row.day)).toBe(row.n);
    // Questions written per UTC day match the usage the caps read, and belong to A.
    const written = await DB.prepare("SELECT substr(created_at,1,10) day,COUNT(*) n FROM jobs WHERE account_id=? AND kind='generate' GROUP BY 1").bind(A.id).all<{ day: string; n: number }>();
    for (const row of written.results) expect(await usage(A.id, "generate", row.day)).toBe(row.n);
    await consistent(A, finishedA);
    await consistent(B, finishedB);
    await endOfDay([A, B]);
  });

  it("end of the week: the export holds A's week and nothing of B's; deleting A removes A's data and leaves B's alone", async () => {
    const sessions: any[] = [], questions: any[] = [];
    let first: any;
    for (let cursor: string | null = ""; cursor !== null;) {
      const page = await call(A, "GET", "/v1/account/export" + (cursor ? "?cursor=" + encodeURIComponent(cursor) : ""));
      expect(page.status).toBe(200);
      first ??= page.body;
      expect(page.body.sessions.length).toBeLessThanOrEqual(10);
      sessions.push(...page.body.sessions); questions.push(...page.body.questions); cursor = page.body.nextCursor;
    }
    expect(first.settings).toMatchObject({ timezone: "America/Los_Angeles" });
    const own = await DB.prepare("SELECT id FROM challenges WHERE account_id=? ORDER BY id").bind(A.id).all<{ id: string }>();
    const ownQuestions = await DB.prepare("SELECT id FROM questions WHERE account_id=? ORDER BY id").bind(A.id).all<{ id: string }>();
    expect(sessions.map(s => s.id).sort()).toEqual(own.results.map(r => r.id));
    expect(questions.map(q => q.id).sort()).toEqual(ownQuestions.results.map(r => r.id));
    for (const f of finishedA) expect(sessions.find(s => s.id === f.id)).toMatchObject({ lifecycle: "completed", reflection: { summary: "Solid queue thinking." } });
    const spoken = sessions.find(s => s.id === finishedA[2].id);
    expect(spoken.interview.turns.flatMap((t: any) => t.voice ?? []).map((f: any) => f.text)).toContain(SAID[0]);
    const exported = JSON.stringify({ sessions, questions });
    for (const f of finishedB) expect(exported).not.toContain(f.id);
    expect(exported).not.toContain(B.id);

    const tables = ["challenges", "jobs", "usage", "voice_sessions", "recall_cards", "recall_reviews", "entitlements", "daily_visits", "questions", "settings", "ai_runs"];
    const counts = async (account: string) => Object.fromEntries(await Promise.all(tables.map(async t =>
      [t, (await DB.prepare(`SELECT COUNT(*) n FROM ${t} WHERE account_id=?`).bind(account).first<{ n: number }>())!.n] as const)));
    // D1 binds at most 100 variables a statement, so the ids go in chunks.
    const challengeRows = async (ids: string[]) => {
      let n = 0;
      for (let i = 0; i < ids.length; i += 20) {
        const chunk = ids.slice(i, i + 20), slots = chunk.map(() => "?").join(",");
        const row = await DB.prepare(`SELECT (SELECT COUNT(*) FROM interview_turns WHERE challenge_id IN (${slots})) + (SELECT COUNT(*) FROM reflections WHERE challenge_id IN (${slots})) + (SELECT COUNT(*) FROM sessions WHERE challenge_id IN (${slots})) + (SELECT COUNT(*) FROM completion_context WHERE challenge_id IN (${slots})) n`).bind(...chunk, ...chunk, ...chunk, ...chunk).first<{ n: number }>();
        n += row!.n;
      }
      return n;
    };
    const voiceIds = (await DB.prepare("SELECT id FROM voice_sessions WHERE account_id=?").bind(A.id).all<{ id: string }>()).results.map(r => r.id);
    const aChallenges = own.results.map(r => r.id);
    const bBefore = await counts(B.id), bChildren = await challengeRows(finishedB.map(f => f.id));
    const aBefore = await counts(A.id);
    for (const t of ["challenges", "jobs", "usage", "voice_sessions", "recall_cards", "recall_reviews", "entitlements", "daily_visits", "questions", "settings"]) expect(aBefore[t], t).toBeGreaterThan(0);

    const deleting = await call(A, "DELETE", "/v1/account");
    expect(deleting).toEqual({ status: 202, body: { status: "deleting" } });
    const locked = await call(A, "GET", "/v1/bootstrap");
    expect(locked.status).toBe(403);
    expect(locked.body.error.code).toBe("account_unavailable");
    // The Workflow runs the deletion: Clerk first, then the account and everything that hangs off it.
    const job = await DB.prepare("SELECT id FROM jobs WHERE account_id=? AND kind='delete_account'").bind(A.id).first<{ id: string }>();
    expect(dispatched).toContain(job!.id);
    await runJob(bindings, job!.id);
    expect(ai.calls.clerk).toBe(1);
    expect(await DB.prepare("SELECT 1 FROM accounts WHERE id=?").bind(A.id).first()).toBeNull();
    expect(Object.values(await counts(A.id)).every(n => n === 0), JSON.stringify(await counts(A.id))).toBe(true);
    expect(await challengeRows(aChallenges)).toBe(0);
    const slots = voiceIds.map(() => "?").join(",");
    expect((await DB.prepare(`SELECT (SELECT COUNT(*) FROM voice_fragments WHERE session_id IN (${slots})) + (SELECT COUNT(*) FROM voice_delegations WHERE session_id IN (${slots})) n`).bind(...voiceIds, ...voiceIds).first<{ n: number }>())!.n).toBe(0);
    // B is untouched and carries on.
    expect(await counts(B.id)).toEqual(bBefore);
    expect(await challengeRows(finishedB.map(f => f.id))).toBe(bChildren);
    expect((await bootstrap(B)).account.plan).toBe("pro");
    await consistent(B, finishedB);
    await endOfDay([B]);
  });
});

describe("around the week", () => {
  it("a weekly plan lapses mid-week: grace keeps Pro, expiry falls back to free without losing anything, recovery restores Pro", async () => {
    // Europe/Berlin, UTC+1. A restore on a new device brings back a week bought on 26 November that ends on 3 December.
    at("2026-12-01T09:00:00Z");
    const V = await signUp("Europe/Berlin");
    const { reply, claims } = await subscribe(V, WEEKLY, Date.parse("2026-11-26T09:00:00Z"), Date.parse("2026-12-03T09:00:00Z"));
    expect(reply.body).toMatchObject({ plan: "pro", entitlement: { status: "active", activeUntil: "2026-12-03T09:00:00.000Z" } });
    const finished: { id: string; completedAt: string }[] = [];
    const first = await prepare(V);
    expect((await call(V, "POST", `/v1/challenges/${first}/start`)).status).toBe(200);
    await voiceSession(V, first, { seconds: 299, reported: 300, said: SAID });
    let d = await finish(V, first); finished.push({ id: d.id, completedAt: d.completedAt });
    at("2026-12-02T10:00:00Z");
    d = await rep(V); finished.push({ id: d.id, completedAt: d.completedAt });
    // A rep left open, one answer in.
    const open = await prepare(V);
    await practise(V, open, 1);

    // Renewal fails at the end of the period: billing retry with a grace period keeps Pro.
    at("2026-12-03T09:00:05Z");
    const grace = await appStore("DID_FAIL_TO_RENEW", "GRACE_PERIOD", claims, {}, { autoRenewStatus: 1, gracePeriodExpiresDate: Date.parse("2026-12-04T09:00:00Z") });
    expect(grace.body).toEqual({ applied: true, notificationType: "DID_FAIL_TO_RENEW" });
    expect(await DB.prepare("SELECT status,active_until FROM entitlements WHERE account_id=?").bind(V.id).first()).toEqual({ status: "grace", active_until: "2026-12-04T09:00:00.000Z" });
    expect((await bootstrap(V)).account.plan).toBe("pro");
    await endOfDay([V]);

    // The grace runs out before Apple's EXPIRED arrives: free from that moment, then the notification confirms it.
    at("2026-12-04T09:00:30Z");
    let boot = await bootstrap(V);
    expect(boot.account.plan).toBe("free");
    const expired = await appStore("EXPIRED", "BILLING_RETRY", claims, {});
    expect(expired.body).toEqual({ applied: true, notificationType: "EXPIRED" });
    expect((await DB.prepare("SELECT status FROM entitlements WHERE account_id=?").bind(V.id).first<{ status: string }>())!.status).toBe("expired");
    boot = await bootstrap(V);
    expect(boot.account.plan).toBe("free");
    // Pro reps were never free reps, so all three free reps are there.
    expect(boot.practice).toMatchObject({ plan: "free", freeReps: true, lifetime: true, limit: 3, remaining: 3 });
    expect(boot.capabilities.voice).toMatchObject({ plan: "free" });
    // The rep left open under Pro still finishes with feedback; nothing was lost.
    expect(boot.challenge).toMatchObject({ id: open, lifecycle: "in_progress" });
    expect((await answer(V, open, ANSWERS[1])).status).toBe(202);
    const voiceGate = await startVoice(V, open);
    expect(voiceGate.status).toBe(402);
    expect(voiceGate.body.error.code).toBe("voice_gate");
    d = await finish(V, open); finished.push({ id: d.id, completedAt: d.completedAt });
    await consistent(V, finished);
    // Free: no automatic question on a new local day, and the next rep spends a free rep.
    at("2026-12-05T08:00:00Z");
    expect((await call(V, "POST", "/v1/daily-question", {})).body).toEqual({ day: "2026-12-05" });
    const freeRep = await call(V, "POST", "/v1/challenges", {});
    expect(freeRep.status).toBe(202);
    expect(JSON.parse((await DB.prepare("SELECT input FROM jobs WHERE id=?").bind(freeRep.body.id).first<{ input: string }>())!.input).freeRepAt).toBeTruthy();
    expect((await bootstrap(V)).practice).toMatchObject({ remaining: 2 });
    const exported = (await call(V, "GET", "/v1/account/export")).body;
    expect(exported.sessions.map((s: any) => s.id)).toEqual(expect.arrayContaining(finished.map(f => f.id)));

    // Billing recovers: Pro again, straight away.
    const recovered = await appStore("DID_RENEW", "BILLING_RECOVERY", claims, { purchaseDate: Date.now(), expiresDate: Date.now() + 7 * DAY });
    expect(recovered.body).toEqual({ applied: true, notificationType: "DID_RENEW" });
    boot = await bootstrap(V);
    expect(boot.account.plan).toBe("pro");
    expect(boot.practice.freeReps).toBe(false);
    await practise(V, freeRep.body.id);
    d = await finish(V, freeRep.body.id); finished.push({ id: d.id, completedAt: d.completedAt });
    await consistent(V, finished);
    await endOfDay([V]);
  });

  it("the daily question follows the local calendar across the end of daylight saving time", async () => {
    // Los Angeles falls back at 09:00 UTC on 1 November 2026: 01:00–02:00 local happens twice and the day lasts 25 hours.
    at("2026-11-01T06:30:00Z"); // 23:30 PDT, 31 October
    const D = await signUp("America/Los_Angeles");
    await subscribe(D, YEARLY, Date.now(), Date.now() + 365 * DAY);
    const daily = async () => (await call(D, "POST", "/v1/daily-question", {})).body;
    let today = await daily();
    expect(today).toMatchObject({ day: "2026-10-31", job: { kind: "generate" } });
    expect((await call(D, "POST", `/v1/challenges/${today.job.id}/skip`)).status).toBe(200);
    at("2026-11-01T07:30:00Z"); // 00:30 PDT, 1 November
    today = await daily();
    expect(today).toMatchObject({ day: "2026-11-01", job: { kind: "generate" } });
    await practise(D, today.job.id);
    await finish(D, today.job.id);
    for (const instant of ["2026-11-01T08:30:00Z", "2026-11-01T09:30:00Z", "2026-11-02T07:50:00Z"]) { // 01:30 PDT, 01:30 PST, 23:50 PST
      at(instant);
      expect(await daily()).toEqual({ day: "2026-11-01" });
      expect((await bootstrap(D)).todayPlan.completedToday).toBe(1);
    }
    at("2026-11-02T08:10:00Z"); // 00:10 PST, 2 November
    expect((await bootstrap(D)).todayPlan.completedToday).toBe(0);
    expect(await daily()).toMatchObject({ day: "2026-11-02", job: { kind: "generate" } });
    const generated = await DB.prepare("SELECT COUNT(*) n FROM jobs WHERE account_id=? AND kind='generate'").bind(D.id).first<{ n: number }>();
    expect(generated!.n).toBe(3);
    await endOfDay([D]);
  });

  it("an evening of rerolls doesn't cost a Pro subscriber the next morning's daily question", async () => {
    // Los Angeles: 17:00 local is already the next UTC day, so the evening and the next morning share a UTC day.
    at("2026-11-17T16:00:00Z"); // 08:00 PST, 17 November
    const E = await signUp("America/Los_Angeles");
    await subscribe(E, YEARLY, Date.now(), Date.now() + 365 * DAY);
    const morning = await call(E, "POST", "/v1/daily-question", {});
    expect(morning.body).toMatchObject({ day: "2026-11-17", job: { kind: "generate" } });
    await practise(E, morning.body.job.id);
    await finish(E, morning.body.job.id);
    at("2026-11-18T01:00:00Z"); // 17:00 PST, 17 November: twelve questions written, rerolls included, well inside 20 a day.
    let current = await prepare(E);
    for (let i = 0; i < 11; i++) current = await prepare(E, { replaceId: current });
    await practise(E, current);
    await finish(E, current);
    expect(await usage(E.id, "generate", "2026-11-18")).toBe(12);
    at("2026-11-18T16:00:00Z"); // 08:00 PST, 18 November: the first visit of the new local day.
    const next = await call(E, "POST", "/v1/daily-question", {});
    expect(next.status, JSON.stringify(next.body)).toBe(200);
    expect(next.body).toMatchObject({ day: "2026-11-18", job: { kind: "generate" } });
    await endOfDay([E]);
  });

  it("a Pro day inside the fair-use caps never stops an open rep: nine reps of six typed answers", async () => {
    at("2026-11-20T16:00:00Z");
    const F = await signUp("America/Los_Angeles");
    await subscribe(F, YEARLY, Date.now(), Date.now() + 365 * DAY);
    const refused: string[] = [];
    for (let r = 1; r <= 9 && !refused.length; r++) {
      const id = await prepare(F);
      expect((await call(F, "POST", `/v1/challenges/${id}/start`)).status).toBe(200);
      for (let t = 1; t <= 6; t++) {
        const reply = await answer(F, id, ANSWERS[t - 1]);
        if (reply.status !== 202) { refused.push(`rep ${r}, answer ${t}: ${reply.status} ${reply.body.error.code}`); break; }
      }
      if (!refused.length) await finish(F, id);
    }
    expect(refused).toEqual([]);
  });

  it("an hour of Pro voice can delegate to the interviewer throughout, and the rep still gets its feedback", async () => {
    at("2026-11-25T16:00:00Z");
    const G = await signUp("America/Los_Angeles");
    await subscribe(G, YEARLY, Date.now(), Date.now() + 365 * DAY);
    const id = await prepare(G);
    expect((await call(G, "POST", `/v1/challenges/${id}/start`)).status).toBe(200);
    const failed: string[] = [];
    // Three 20-minute sessions, the documented day, with a delegation about every 35 seconds.
    for (let s = 0; s < 3; s++) {
      const started = await startVoice(G, id);
      expect(started.status).toBe(201);
      const sid = started.body.id;
      const created = Date.parse((await DB.prepare("SELECT created_at FROM voice_sessions WHERE id=?").bind(sid).first<{ created_at: string }>())!.created_at);
      expect((await call(G, "POST", `/v1/challenges/${id}/voice/${sid}/events`, { fragments: [{ id: "u0", sequence: 0, speaker: "user", text: SAID[0], startMs: 0, endMs: 3000 }] })).status).toBe(200);
      for (let k = 0; k < 34; k++) {
        at(created + 30_000 + k * 34_000);
        const reply = await call(G, "POST", `/v1/challenges/${id}/voice/${sid}/delegate`, { id: `d${k}` });
        if (reply.status !== 200) failed.push(`session ${s + 1}, delegation ${k + 1}: ${reply.status} ${reply.body.error.code}`);
      }
      at(created + 1_197_000);
      expect((await call(G, "POST", `/v1/challenges/${id}/voice/${sid}/events`, { fragments: [], closed: true, finalized: true, usageSeconds: 1200 })).status).toBe(200);
    }
    expect.soft(failed, "delegations refused inside the documented hour of Pro voice").toEqual([]);
    ai.concept = (await challenge(G, id)).primaryConceptId; ai.signal = "needs_practice";
    const revision = (await challenge(G, id)).session.revision;
    expect((await call(G, "POST", `/v1/challenges/${id}/complete`, { answer: "", revision })).status).toBe(200);
    expect((await challenge(G, id)).reflection, "feedback for the spoken rep").not.toBeNull();
  });
});
