/**
 * Live end-to-end run of a Pro user against the deployed DEVELOPMENT backend.
 *
 *   bun scripts/e2e-live.ts
 *
 * Creates a throwaway Clerk development user, redeems a fresh invite, grants Pro with a manual entitlement in the
 * development D1, walks a Pro user's day (onboarding, daily question, extra questions, an interview rep with help,
 * feedback, Recall, Library, voice, warm-up, export) and finally deletes the account through the API and verifies
 * that nothing account-owned is left. Never touches production. Secrets and tokens are never printed or written;
 * practice content is reported by length and id only. The timeline lands in .local/e2e/<timestamp>.json.
 * Voice needs `werift` installed under .local/e2e/voice (bun add werift there); without it voice is skipped.
 */
import { createHash, randomBytes } from "node:crypto";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join, resolve } from "node:path";

const ROOT = resolve(import.meta.dir, "..");
const BASE = "https://drillbit-api-development.david-erwin-cz68.workers.dev";
const D1_DATABASE = "drillbit-development";
const CLERK_API = "https://api.clerk.com/v1";
const STUCK_MS = 120_000;
if (/drillbit\.t23\.dev|production/i.test(BASE) || D1_DATABASE !== "drillbit-development")
  throw new Error("Refusing to run: this script only targets the development backend.");

const clerkEnv = Object.fromEntries(
  readFileSync(join(ROOT, ".local/clerk.env"), "utf8").split("\n").map(line => line.trim())
    .filter(line => line && !line.startsWith("#") && line.includes("="))
    .map(line => { const at = line.indexOf("="); return [line.slice(0, at).trim(), line.slice(at + 1).trim().replace(/^["']|["']$/g, "")]; }),
);
const CLERK_SECRET: string = clerkEnv.CLERK_SECRET_KEY ?? "";
if (!CLERK_SECRET.startsWith("sk_test_")) throw new Error("Refusing to run: .local/clerk.env must hold a development (sk_test_) key.");

// ---------------------------------------------------------------------------------------------------------------
// Timeline

type Kind = "bug" | "contract" | "script" | "observation";
type Step = { name: string; at: string; ms: number; ok: boolean; method?: string; path?: string; status?: number; requestId?: string | null; error?: string; data?: Record<string, unknown> };
const startedAt = new Date();
const stamp = startedAt.toISOString().replace(/[:.]/g, "-");
const outFile = join(ROOT, ".local/e2e", `${stamp}.json`);
mkdirSync(join(ROOT, ".local/e2e"), { recursive: true, mode: 0o700 });
const run = {
  startedAt: startedAt.toISOString(), finishedAt: null as string | null, base: BASE, d1: D1_DATABASE,
  account: null as string | null, clerkUser: null as string | null,
  steps: [] as Step[],
  streams: [] as Record<string, unknown>[],
  jobs: [] as Record<string, unknown>[],
  findings: [] as { kind: Kind; step: string; message: string; requestId?: string | null }[],
  voice: {} as Record<string, unknown>,
  checks: {} as Record<string, unknown>,
  cost: {} as Record<string, unknown>,
  cleanup: {} as Record<string, unknown>,
  sentry: null as unknown,
};
const save = () => writeFileSync(outFile, JSON.stringify(run, null, 2) + "\n", { mode: 0o600 });
const now = () => performance.now();
const iso = () => new Date().toISOString();
const sleep = (ms: number) => new Promise(r => setTimeout(r, ms));
const uuid = () => crypto.randomUUID();
const short = (id?: string | null) => (id ? id.slice(0, 8) : "-");

function record(step: Step) {
  run.steps.push(step);
  const mark = step.ok ? "ok " : "ERR";
  const status = step.status !== undefined ? String(step.status) : "   ";
  console.log(`${mark} ${status.padEnd(3)} ${String(Math.round(step.ms)).padStart(6)}ms  ${step.name}${step.ok ? "" : `  [${step.error ?? ""}${step.requestId ? ` req=${step.requestId}` : ""}]`}`);
  save();
}
function finding(kind: Kind, step: string, message: string, requestId?: string | null) {
  run.findings.push({ kind, step, message, requestId });
  console.log(`  ⚑ ${kind}: ${step}: ${message}${requestId ? ` (req ${requestId})` : ""}`);
  save();
}
function check(name: string, condition: boolean, message: string, kind: Kind = "bug", requestId?: string | null) {
  (run.checks[name] as unknown) = condition;
  if (!condition) finding(kind, name, message, requestId);
  return condition;
}
async function timed<T>(name: string, work: () => Promise<T>, data?: (value: T) => Record<string, unknown>): Promise<T> {
  const started = now();
  try {
    const value = await work();
    record({ name, at: iso(), ms: now() - started, ok: true, data: data?.(value) });
    return value;
  } catch (error) {
    record({ name, at: iso(), ms: now() - started, ok: false, error: (error as Error).message.slice(0, 300) });
    throw error;
  }
}

// ---------------------------------------------------------------------------------------------------------------
// Contracts: the shared zod wire schemas, and the iOS DTOs' required keys (Swift's synthesized Decodable requires
// every non-optional property, defaults included, and rejects unknown enum values even on optional properties).

let wire: Record<string, { safeParse(value: unknown): { success: boolean; error?: { issues: { path: PropertyKey[]; message: string }[] } } }> | null = null;
try { wire = (await import("../packages/contracts/wire")).wire as never; }
catch (error) { finding("script", "contracts", "Couldn't import packages/contracts/wire.ts: " + (error as Error).message); }

const GUIDANCE = "enum:learn_together|coach_me|mock_interview";
const STYLE = "enum:quick|standard|in_depth";
const swift: Record<string, Record<string, string>> = {
  SessionDraft: { answer: "string", revision: "int", updatedAt: "?string" },
  CoachTurn: { id: "string", role: "string", text: "string", state: "string" },
  RecallPrompt: { prompt: "string", answer: "string" },
  LearningEvidence: { conceptId: "string", observation: "string", quote: "string", signal: "string", assistance: "string", sessionId: "?string", at: "?string", sourceTurnId: "?string", recall: "?RecallPrompt" },
  Reflection: { evidence: "?[LearningEvidence]", nextExercise: "?string", summary: "string", worked: "[string]", improve: "string", takeaway: "string", strengths: "[string]", gaps: "[string]", guidanceMode: "?" + GUIDANCE, lesson: "?Lesson", debrief: "?Debrief" },
  Lesson: { learned: "[string]", tryAlone: "string" },
  Debrief: { verdict: "enum:pass|borderline|not_yet", reason: "string", signals: "[DebriefSignal]", toPass: "string" },
  DebriefSignal: { area: "string", rating: "string", note: "string" },
  ExampleAnswer: { overview: "string", sections: "[ExamplePart]", tradeoffs: "[string]", pitfalls: "[string]" },
  ExamplePart: { heading: "string", body: "string" },
  RequestStatus: { id: "string", status: "string" },
  Challenge: {
    questionId: "?string", scenario: "?string", primaryConceptId: "?string", conceptIds: "?[string]", selectionReason: "?string", constraints: "?[string]",
    guidanceMode: "?" + GUIDANCE, warmUp: "?bool", ticket: "?int", minutes: "?int", startedAt: "?string", path: "?[string]", opener: "?string",
    freeRepAt: "?string", swapped: "?bool", interviewStyle: "?" + STYLE, interview: "?InterviewState", engineeringLevel: "?string", difficulty: "?string",
    id: "string", lifecycle: "string", title: "string", prompt: "string", topic: "string", createdAt: "?string", completedAt: "?string",
    session: "?SessionDraft", turns: "?[CoachTurn]", reflection: "?Reflection", example: "?ExampleAnswer", coachRequest: "?RequestStatus",
    help: "?[HelpResult]", adoptions: "?[AdoptionEvent]", companion: "?CompanionContext", automaticCompanion: "?bool",
  },
  Job: { id: "string", kind: "string", status: "string", error: "?string", challengeId: "?string" },
  VoiceCapability: { available: "bool", plan: "?string", reason: "?string", checkedAt: "string", sessionSeconds: "?int", remaining: "?int", limit: "?int", resetsAt: "?string", kind: "?string" },
  Capabilities: { voice: "?VoiceCapability", developerTools: "?bool" },
  Account: { id: "string", status: "string", plan: "?string", planOverride: "?string" },
  Credential: { suffix: "string", model: "?string" },
  PracticeProfile: { goals: "string", background: "string", preferences: "string" },
  LearningPlan: { version: "int", objective: "string", roleTrack: "string", weakAreas: "[string]", dailyGoalMinutes: "int", targetDate: "?string" },
  PracticeSettings: { practiceProfile: "?PracticeProfile", learningPlan: "?LearningPlan", onboardingComplete: "bool", focus: "string", difficulty: "string", engineeringLevel: "?string", timezone: "string", dailyMinutes: "int", reminderEnabled: "bool", aiMode: "string", model: "string", questionFormatting: "?bool" },
  PracticeAccess: { plan: "?string", freeReps: "bool", available: "bool", nextFreeRepAt: "?string", remaining: "?int", limit: "?int", resetsAt: "?string", lifetime: "?bool" },
  TodayPlan: { state: "string", completedTotal: "int", completedLastSevenDays: "int", completedToday: "int", dueRecallCount: "int", recommendedRecallCount: "int", estimatedRecallMinutes: "int", dailyGoalMinutes: "int", nextTicket: "?int" },
  QueuedNext: { sourceId: "string", title: "string", conceptId: "?string", label: "?string", createdAt: "string" },
  QueuedNextResult: { queuedNext: "?QueuedNext" },
  Bootstrap: { capabilities: "?Capabilities", practiceEpoch: "?string", account: "Account", settings: "PracticeSettings", challenge: "?Challenge", jobs: "[Job]", credential: "?Credential", todayPlan: "?TodayPlan", queuedNext: "?QueuedNext", practice: "?PracticeAccess" },
  DailyQuestionResponse: { day: "string", challenge: "?Challenge", job: "?Job" },
  GenerationResponse: { id: "?string", challenge: "?Challenge" },
  HistoryPage: { sessions: "[Challenge]", nextCursor: "?string" },
  Statistics: { completed: "int", lastSevenDays: "int", asOf: "string" },
  Pattern: { label: "string", kind: "string", sessionIds: "[string]" },
  MemoryResponse: { evidence: "?[LearningEvidence]", statistics: "?Statistics", sessions: "[Challenge]", patterns: "[Pattern]" },
  RecallCardDTO: { id: "string", sourceChallengeId: "string", conceptId: "string", question: "string", answer: "string", dueAt: "string", intervalDays: "int", repetitions: "int", lapses: "int", createdAt: "string", updatedAt: "string", sourceTitle: "?string", sourceCompletedAt: "?string", sourceTicket: "?int", evidence: "?LearningEvidence" },
  RecallDeckResponse: { cards: "[RecallCardDTO]", dueCount: "int" },
  RecallReviewResponse: { card: "RecallCardDTO" },
  CompanionCapture: { contextRevision: "int", modeEpoch: "int", cycle: "string", digest: "string", trigger: "string" },
  HelpResult: { id: "string", status: "string", kind: "string", revision: "int", body: "?string", suggestedAnswer: "?string", capture: "?CompanionCapture", deliveries: "?[string]", outcome: "?string", suggestedFocus: "?string", plan: "?[string]" },
  AdoptionEvent: { id: "string", sourceId: "string", operation: "string", revision: "int" },
  Decision: { id: "string", text: "string" },
  CompanionContext: { cycleConsumed: "?bool", guidedStarted: "?bool", revision: "int", mode: "string", modeEpoch: "int", paused: "bool", selectedFocus: "?string", decisions: "[Decision]", automaticCount: "int", lastAutomaticAt: "?string", digest: "string", cycle: "string" },
  InterviewParameter: { label: "string", value: "string" },
  InterviewResponse: { outcome: "string", text: "string", parameters: "?[InterviewParameter]", choices: "?[string]", step: "?int", path: "?[string]", covered: "?bool" },
  VoiceFragment: { id: "string", sequence: "int", speaker: "string", text: "string", startMs: "int", endMs: "int" },
  InterviewTurn: { id: "string", ordinal: "int", kind: "string", prompt: "string", text: "string", createdAt: "string", jobId: "string", status: "string", error: "?string", result: "?InterviewResponse", partial: "?string", voice: "?[VoiceFragment]" },
  InterviewState: { guidanceMode: "?" + GUIDANCE, style: STYLE, prompt: "string", wrapUp: "bool", guidedStep: "?int", path: "?[string]", turns: "[InterviewTurn]" },
  InterviewStreamSnapshot: { status: "string", text: "string" },
  QuestionStreamSnapshot: { status: "string", error: "?string", title: "string", prompt: "string", textDone: "?bool", challenge: "?Challenge" },
  PracticeConcept: { id: "string", label: "string", category: "string", aliases: "[string]", description: "?string" },
  TaxonomyResponse: { version: "int", concepts: "[PracticeConcept]" },
  LibraryQuestion: { id: "string", title: "string", prompt: "string", scenario: "string", engineeringLevel: "string", primaryConceptId: "string", conceptIds: "[string]", eligible: "bool", eligibilityRevision: "int", lastActivity: "?string", attemptCount: "?int" },
  LibraryPage: { questions: "[LibraryQuestion]", nextCursor: "?string" },
  LibraryDetail: { question: "LibraryQuestion", attempts: "[Challenge]", nextCursor: "?string" },
  CoverageEntry: { conceptId: "string", completedAttempts: "int", distinctQuestions: "int", lastPractised: "?string" },
  CoverageResponse: { concepts: "[CoverageEntry]" },
  VoiceConnection: { id: "string", sdp: "string", expiresAt: "string", sessionSeconds: "?int" },
  VoiceAck: { accepted: "[string]" },
  VoiceReply: { text: "string", step: "?int" },
  EmptyResponse: { ok: "?bool" },
  RevisionResponse: { revision: "int" },
  DeviceResponse: { id: "string", token: "string", expiresAt: "string" },
  WidgetSnapshot: { challenge: "?Challenge", updatedAt: "string" },
  PersonalizationPreview: { text: "string" },
};
const camel = (key: string) => key.replace(/_([a-z0-9])/g, (_, c: string) => c.toUpperCase());
function swiftIssues(type: string, value: unknown, path = "$", issues: string[] = []): string[] {
  if (issues.length > 20) return issues;
  const optional = type.startsWith("?");
  const bare = optional ? type.slice(1) : type;
  if (value === undefined || value === null) { if (!optional) issues.push(`${path}: missing ${bare}`); return issues; }
  if (bare.startsWith("[")) {
    if (!Array.isArray(value)) { issues.push(`${path}: expected array`); return issues; }
    value.forEach((item, index) => swiftIssues(bare.slice(1, -1), item, `${path}[${index}]`, issues));
    return issues;
  }
  if (bare.startsWith("enum:")) { if (!bare.slice(5).split("|").includes(value as string)) issues.push(`${path}: unknown enum value ${JSON.stringify(value)}`); return issues; }
  if (bare === "string") { if (typeof value !== "string") issues.push(`${path}: expected string, got ${typeof value}`); return issues; }
  if (bare === "bool") { if (typeof value !== "boolean") issues.push(`${path}: expected bool, got ${typeof value}`); return issues; }
  if (bare === "int") { if (!Number.isInteger(value)) issues.push(`${path}: expected int, got ${JSON.stringify(value)}`); return issues; }
  const spec = swift[bare];
  if (!spec) { issues.push(`${path}: no spec for ${bare}`); return issues; }
  if (typeof value !== "object" || Array.isArray(value)) { issues.push(`${path}: expected object ${bare}`); return issues; }
  const keyed = Object.fromEntries(Object.entries(value as object).map(([key, item]) => [camel(key), item]));
  for (const [key, fieldType] of Object.entries(spec)) swiftIssues(fieldType, keyed[key], `${path}.${key}`, issues);
  return issues;
}
function conform(step: string, value: unknown, contract?: string, dto?: string, requestId?: string | null) {
  if (contract && wire) {
    const schema = wire[contract];
    if (!schema) finding("script", step, `No wire schema named ${contract}`);
    else {
      const parsed = schema.safeParse(value);
      if (!parsed.success) finding("contract", step, `Response violates OpenAPI wire schema ${contract}: ` + parsed.error!.issues.slice(0, 5).map(i => `${i.path.join(".") || "$"} ${i.message}`).join("; "), requestId);
    }
  }
  if (dto) {
    const issues = swiftIssues(dto, value);
    if (issues.length) finding("contract", step, `iOS ${dto} would fail to decode: ` + issues.slice(0, 6).join("; "), requestId);
  }
}

// ---------------------------------------------------------------------------------------------------------------
// Clerk (development instance) and tokens

async function clerk(method: string, path: string, body?: unknown) {
  const response = await fetch(CLERK_API + path, {
    method, headers: { Authorization: `Bearer ${CLERK_SECRET}`, "Content-Type": "application/json" },
    body: body === undefined ? undefined : JSON.stringify(body), signal: AbortSignal.timeout(20000),
  });
  const json = await response.json().catch(() => null) as any;
  return { status: response.status, json, errors: Array.isArray(json?.errors) ? json.errors.map((e: any) => e.code).join(",") : undefined };
}
let clerkSession: string | null = null;
let minted: { jwt: string; at: number } | null = null;
let tokenMints = 0;
async function token() {
  if (minted && Date.now() - minted.at < 45_000) return minted.jwt;
  if (!clerkSession) throw new Error("No Clerk session");
  const result = await clerk("POST", `/sessions/${clerkSession}/tokens/drillbit`, {});
  if (result.status !== 200 || typeof result.json?.jwt !== "string") throw new Error(`Token mint failed (${result.status} ${result.errors ?? ""})`);
  minted = { jwt: result.json.jwt, at: Date.now() };
  tokenMints++;
  return minted.jwt;
}

// ---------------------------------------------------------------------------------------------------------------
// HTTP

class ApiFailure extends Error {
  constructor(public status: number, public code: string | undefined, public requestId: string | null, message: string) { super(message); }
}
type Call = { status: number; json: any; requestId: string | null; ms: number; command?: string };
async function api(name: string, method: string, path: string, options: { body?: unknown; command?: string | true; expect?: number[]; contract?: string; dto?: string; quiet?: boolean } = {}): Promise<Call> {
  const command = options.command === true ? uuid() : options.command;
  const headers: Record<string, string> = { Authorization: `Bearer ${await token()}`, "Content-Type": "application/json" };
  if (command) headers["Idempotency-Key"] = command;
  const started = now();
  let response: Response;
  try {
    response = await fetch(`${BASE}/v1/${path}`, { method, headers, body: options.body === undefined ? undefined : JSON.stringify(options.body), signal: AbortSignal.timeout(95_000) });
  } catch (error) {
    record({ name, at: iso(), ms: now() - started, ok: false, method, path, error: "network: " + (error as Error).message });
    finding("bug", name, `Network failure or timeout: ${(error as Error).message}`);
    throw error;
  }
  const text = await response.text();
  const ms = now() - started;
  const requestId = response.headers.get("x-request-id");
  let json: any = null;
  try { json = text ? JSON.parse(text) : null; } catch { /* reported below */ }
  const expect = options.expect ?? [200, 201, 202];
  const ok = expect.includes(response.status);
  const errorCode = json?.error?.code as string | undefined;
  record({ name, at: iso(), ms, ok, method, path, status: response.status, requestId, error: ok ? undefined : `${errorCode ?? ""} ${json?.error?.message ?? text.slice(0, 120)}`.trim() });
  if (json === null && text) finding("bug", name, "Response body is not JSON", requestId);
  if (!requestId) finding("bug", name, "Response has no X-Request-ID header", requestId);
  if (response.status >= 500) finding("bug", name, `HTTP ${response.status} ${errorCode ?? ""}: ${json?.error?.message ?? ""}`, requestId);
  else if (!ok && !options.quiet) finding("bug", name, `Unexpected HTTP ${response.status} ${errorCode ?? ""}: ${json?.error?.message ?? ""}`, requestId);
  if (!ok) throw new ApiFailure(response.status, errorCode, requestId, `${method} ${path} → ${response.status} ${errorCode ?? ""}`);
  conform(name, json, options.contract, options.dto, requestId);
  return { status: response.status, json, requestId, ms, command };
}

/** Reads a snapshot stream the way the app does: data lines until a terminal status. */
async function stream(name: string, path: string, contract: string, dto: string, limitMs = STUCK_MS + 10_000) {
  const started = now();
  const response = await fetch(`${BASE}/v1/${path}`, { headers: { Authorization: `Bearer ${await token()}` }, signal: AbortSignal.timeout(limitMs) });
  const requestId = response.headers.get("x-request-id");
  const summary: Record<string, unknown> = { name, path, status: response.status, requestId, contentType: response.headers.get("content-type") };
  if (response.status !== 200 || !response.body) {
    const body = await response.text().catch(() => "");
    record({ name, at: iso(), ms: now() - started, ok: false, method: "GET", path, status: response.status, requestId, error: body.slice(0, 160) });
    finding(response.status >= 500 ? "bug" : "bug", name, `Stream refused with HTTP ${response.status}`, requestId);
    run.streams.push(summary);
    return { last: null as any, terminal: false, requestId };
  }
  const reader = response.body.getReader();
  const decoder = new TextDecoder();
  let buffer = "", snapshots = 0, last: any = null, terminal = false;
  let firstSnapshotMs: number | null = null, firstTextMs: number | null = null, textDoneMs: number | null = null;
  try {
    reading: while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      buffer += decoder.decode(value, { stream: true });
      let index: number;
      while ((index = buffer.indexOf("\n")) >= 0) {
        const line = buffer.slice(0, index).replace(/\r$/, "");
        buffer = buffer.slice(index + 1);
        if (!line.startsWith("data:")) continue;
        let snapshot: any;
        try { snapshot = JSON.parse(line.slice(5)); } catch { finding("bug", name, "Unparseable SSE data line", requestId); continue; }
        snapshots++;
        const at = now() - started;
        firstSnapshotMs ??= at;
        if (firstTextMs === null && (snapshot.text || snapshot.title || snapshot.prompt)) firstTextMs = at;
        if (textDoneMs === null && snapshot.textDone) textDoneMs = at;
        if (snapshots === 1 || !["pending", "running"].includes(snapshot.status)) conform(name, snapshot, contract, dto, requestId);
        last = snapshot;
        if (!["pending", "running"].includes(snapshot.status)) { terminal = true; await reader.cancel().catch(() => {}); break reading; }
      }
    }
  } catch (error) {
    summary.readError = (error as Error).message;
  }
  const ms = now() - started;
  Object.assign(summary, { ms: Math.round(ms), snapshots, firstSnapshotMs: firstSnapshotMs && Math.round(firstSnapshotMs), firstTextMs: firstTextMs && Math.round(firstTextMs), textDoneMs: textDoneMs && Math.round(textDoneMs), finalStatus: last?.status ?? null, error: last?.error ?? null });
  run.streams.push(summary);
  record({ name, at: iso(), ms, ok: terminal && last?.status === "completed", method: "GET", path, status: 200, requestId, data: summary, error: terminal ? (last?.status !== "completed" ? `final ${last?.status} ${last?.error ?? ""}` : undefined) : "stream ended before a terminal snapshot" });
  if (!terminal) finding("observation", name, `Stream closed after ${Math.round(ms)}ms without a terminal status (last: ${last?.status ?? "none"}); app falls back to polling`, requestId);
  else if (last.status !== "completed") finding("bug", name, `Stream finished as ${last.status}: ${last.error ?? ""}`, requestId);
  return { last, terminal, requestId };
}

/** Polls a job like AppModel.waitForJob, but with the stuck threshold of this run. */
async function waitJob(name: string, id: string, startedAt = now()) {
  let job: any = null, polls = 0;
  while (now() - startedAt < STUCK_MS) {
    job = (await api(`${name} poll`, "GET", `jobs/${id}`, { contract: "Job", dto: "Job" })).json;
    polls++;
    if (!["pending", "running"].includes(job.status)) break;
    await sleep(now() - startedAt < 10_000 ? 500 : 1500);
  }
  const ms = Math.round(now() - startedAt);
  run.jobs.push({ name, id, kind: job?.kind, status: job?.status, error: job?.error ?? null, ms, polls });
  if (["pending", "running"].includes(job?.status)) finding("bug", name, `Job ${short(id)} (${job?.kind}) still ${job?.status} after ${ms}ms`);
  else if (job?.status !== "completed") finding("bug", name, `Job ${short(id)} (${job?.kind}) ended ${job?.status}: ${job?.error ?? ""}`);
  return job;
}

// ---------------------------------------------------------------------------------------------------------------
// Development D1 through wrangler

const safe = (value: string) => {
  if (!/^[A-Za-z0-9_.:+@\-]+$/.test(value)) throw new Error("Unsafe SQL literal");
  return `'${value}'`;
};
async function d1(sql: string, attempt = 1): Promise<any[]> {
  if (/production/i.test(sql)) throw new Error("Refusing a production-looking statement");
  try { return await d1Once(sql); }
  catch (error) {
    // Wrangler's own Cloudflare API calls occasionally fail in transit; the statements here are all safe to repeat.
    if (attempt >= 3 || !/fetch failed|ECONNRESET|timed out|no JSON/i.test((error as Error).message)) throw error;
    await sleep(2000 * attempt);
    return d1(sql, attempt + 1);
  }
}
async function d1Once(sql: string): Promise<any[]> {
  const process = Bun.spawn([join(ROOT, "apps/api/node_modules/.bin/wrangler"), "d1", "execute", D1_DATABASE, "--remote", "--json", "--command", sql], {
    cwd: join(ROOT, "apps/api"), stdout: "pipe", stderr: "pipe",
  });
  const [out] = await Promise.all([new Response(process.stdout).text(), new Response(process.stderr).text()]);
  await process.exited;
  let parsed: any;
  try { parsed = JSON.parse(out); } catch { throw new Error(`wrangler d1 returned no JSON (exit ${process.exitCode})`); }
  if (parsed?.error) throw new Error("wrangler d1: " + JSON.stringify(parsed.error.notes ?? parsed.error.text).slice(0, 300));
  return (Array.isArray(parsed) ? parsed : [parsed]).flatMap((part: any) => part.results ?? []);
}

// ---------------------------------------------------------------------------------------------------------------
// WebRTC (werift): a real offer with a send/receive audio transceiver and the provider's event channel.

const weriftPath = join(ROOT, ".local/e2e/voice/node_modules/werift");
type Peer = Awaited<ReturnType<typeof openPeer>>;
async function openPeer(label: string) {
  const werift: any = await import(weriftPath);
  const started = now();
  const pc = new werift.RTCPeerConnection({ bundlePolicy: "max-bundle", iceServers: [{ urls: "stun:stun.l.google.com:19302" }] });
  const track = new werift.MediaStreamTrack({ kind: "audio" });
  pc.addTransceiver(track, { direction: "sendrecv" });
  const channel = pc.createDataChannel("oai-events");
  const events: Record<string, number> = {};
  const marks: Record<string, number> = {};
  const listeners: ((event: any) => void)[] = [];
  let inboundPackets = 0, outboundPackets = 0, writeError: string | null = null;
  const mark = (name: string) => { marks[name] ??= Math.round(now() - started); };
  pc.connectionStateChange.subscribe((state: string) => mark("connection_" + state));
  pc.iceConnectionStateChange.subscribe((state: string) => mark("ice_" + state));
  channel.stateChanged.subscribe((state: string) => mark("channel_" + state));
  pc.onTrack.subscribe((remote: any) => { mark("remote_track"); remote.onReceiveRtp.subscribe(() => { inboundPackets++; if (inboundPackets === 1) mark("first_inbound_audio"); }); });
  channel.onMessage.subscribe((data: any) => {
    const text = typeof data === "string" ? data : Buffer.from(data).toString("utf8");
    let event: any;
    try { event = JSON.parse(text); } catch { events["<unparsed>"] = (events["<unparsed>"] ?? 0) + 1; return; }
    const type = String(event?.type ?? "<untyped>");
    events[type] = (events[type] ?? 0) + 1;
    if (events[type] === 1) mark("event_" + type);
    for (const listener of listeners) listener(event);
  });
  const offer = await pc.createOffer();
  await pc.setLocalDescription(offer);
  while (pc.iceGatheringState !== "complete" && now() - started < 5000) await sleep(50);
  mark("offer_ready");
  let silence: ReturnType<typeof setInterval> | null = null;
  const send = (event: Record<string, unknown>) => { if (channel.readyState === "open") channel.send(JSON.stringify({ event_id: "evt_" + uuid(), ...event })); };
  const waitFor = (predicate: () => boolean, ms: number) => new Promise<boolean>(resolve => {
    const deadline = Date.now() + ms;
    const tick = () => predicate() ? resolve(true) : Date.now() > deadline ? resolve(false) : setTimeout(tick, 50);
    tick();
  });
  return {
    label, sdp: pc.localDescription.sdp as string, events, marks, send, waitFor,
    on(listener: (event: any) => void) { listeners.push(listener); },
    get stats() { return { inboundPackets, outboundPackets, writeError, connectionState: pc.connectionState, iceState: pc.iceConnectionState, channelState: channel.readyState }; },
    async answer(sdp: string) {
      await pc.setRemoteDescription({ type: "answer", sdp });
      mark("answer_applied");
    },
    /** Opus silence at 20 ms frames, like an open, muted microphone. */
    startSilence() {
      let sequence = Math.floor(Math.random() * 60000), timestamp = Math.floor(Math.random() * 2 ** 31);
      silence = setInterval(() => {
        try {
          const header = new werift.RtpHeader({ payloadType: 96, sequenceNumber: sequence, timestamp, marker: false });
          track.writeRtp(new werift.RtpPacket(header, Buffer.from([0xf8, 0xff, 0xfe])));
          outboundPackets++;
        } catch (error) { writeError ??= (error as Error).message; }
        sequence = (sequence + 1) & 0xffff;
        timestamp = (timestamp + 960) >>> 0;
      }, 20);
    },
    async close() {
      if (silence) clearInterval(silence);
      await Promise.race([pc.close(), sleep(3000)]).catch(() => {});
    },
  };
}

// ---------------------------------------------------------------------------------------------------------------
// Practice helpers

const ANSWERS = [
  "Let me pin down requirements first. I'm assuming read-heavy traffic, roughly 10k requests per second at peak, and that writes must never be lost while reads can be a second stale. API: a POST that creates the item with an idempotency key, and a GET by id. Stateless API servers behind a load balancer, a primary Postgres with a read replica, and Redis in front of hot reads with a short TTL.",
  "For failures: every write commits in one transaction together with an outbox row, and a worker publishes from the outbox to a queue, so consumers get at-least-once delivery and dedupe on the event id. If Redis is down we read from the replica and shed load with per-client rate limits instead of letting the primary fall over. Workers that crash mid-job just get the message redelivered after the visibility timeout.",
  "To scale further I'd partition by tenant id with consistent hashing, use jittered TTLs plus request coalescing so a hot key can't stampede the database, and alert on p99 latency, queue depth and replica lag. The main trade-off is eventual consistency: a user might not see their own write for a moment, so I'd route their reads to the primary for a few seconds after they write.",
];
const promptIdFor = (interview: any) => interview?.turns?.filter((t: any) => ["answer", "continue"].includes(t.kind) && t.result).at(-1)?.id ?? "original";
type Rep = { id: string; mode: string; challenge: any };

async function getChallenge(name: string, id: string) {
  return (await api(name, "GET", `challenges/${id}`, { contract: "Challenge", dto: "Challenge" })).json;
}
/** Generation through POST /challenges (or a daily job), streamed like AppModel.generateForPreview. */
async function prepared(name: string, job: any) {
  const started = now();
  const result = await stream(`${name} stream`, `jobs/${job.id}/stream`, "QuestionStreamSnapshot", "QuestionStreamSnapshot");
  let challenge = result.last?.challenge;
  if (!result.terminal) { await waitJob(name, job.id, started); }
  if (!challenge) {
    if (result.terminal && result.last?.status === "completed") finding("bug", `${name} stream`, "Final completed snapshot carried no challenge; app needs an extra fetch", result.requestId);
    challenge = await getChallenge(`${name} fetch`, job.challenge_id ?? job.challengeId ?? job.id);
  }
  run.jobs.push({ name, id: job.id, kind: "generate", status: result.last?.status, ms: Math.round(now() - started) });
  console.log(`  question ${short(challenge?.id)} lifecycle=${challenge?.lifecycle} concept=${challenge?.primaryConceptId} level=${challenge?.engineeringLevel} titleLen=${challenge?.title?.length} promptLen=${challenge?.prompt?.length} minutes=${challenge?.minutes ?? "-"} opener=${challenge?.opener ? "yes" : "no"}`);
  return challenge;
}
async function generate(name: string, body: Record<string, unknown>) {
  const command = uuid();
  const response = await api(name, "POST", "challenges", { body, command, contract: "Generation", dto: "GenerationResponse" });
  if (response.json?.challenge) {
    finding("observation", name, `Generation returned the existing active challenge ${short(response.json.challenge.id)} instead of a job`, response.requestId);
    return { challenge: response.json.challenge, command, job: null };
  }
  check(`${name}: 202 for new job`, response.status === 202, `Expected 202 for a new generation job, got ${response.status}`, "bug", response.requestId);
  return { challenge: await prepared(name, response.json), command, job: response.json };
}
async function start(name: string, id: string) {
  const challenge = (await api(name, "POST", `challenges/${id}/start`, { contract: "Challenge", dto: "Challenge" })).json;
  check(`${name}: in_progress`, challenge.lifecycle === "in_progress", `Start left lifecycle ${challenge.lifecycle}`);
  return challenge;
}
/** One interview command and its stream, then the refresh the app does (InterviewController.recover). */
async function turn(rep: Rep, name: string, kind: "answer" | "clarification" | "hint" | "example" | "continue", text = "") {
  const command = uuid();
  const body = { promptId: promptIdFor(rep.challenge.interview), kind, revision: rep.challenge.session?.revision ?? 0, text, style: "standard", guidanceMode: rep.mode, ...(kind === "answer" ? { saveDraft: true } : {}) };
  const posted = await api(name, "POST", `challenges/${rep.id}/interview`, { body, command, contract: "InterviewState", dto: "InterviewState" });
  check(`${name}: 202`, posted.status === 202, `Interview command answered ${posted.status}`, "bug", posted.requestId);
  const streamed = await stream(`${name} stream`, `challenges/${rep.id}/interview/${command}/stream`, "InterviewStreamSnapshot", "InterviewStreamSnapshot");
  rep.challenge = await getChallenge(`${name} refresh`, rep.id);
  let saved = rep.challenge.interview?.turns?.find((t: any) => t.id === command);
  const begun = now();
  while (saved && ["pending", "running"].includes(saved.status) && now() - begun < STUCK_MS) {
    await sleep(1500);
    rep.challenge = await getChallenge(`${name} wait`, rep.id);
    saved = rep.challenge.interview?.turns?.find((t: any) => t.id === command);
  }
  if (!saved) finding("bug", name, "Turn missing from the challenge's interview after the stream", posted.requestId);
  else if (saved.status !== "completed") finding("bug", name, `Turn ended ${saved.status}: ${saved.error ?? ""}`, posted.requestId);
  else {
    const expected = ["answer", "continue"].includes(kind) ? ["follow_up", "wrap_up"] : ["reply"];
    check(`${name}: outcome`, expected.includes(saved.result?.outcome), `Outcome ${saved.result?.outcome} for a ${kind} turn`);
    if (streamed.last?.text && saved.result?.text && streamed.last.text !== saved.result.text) finding("observation", name, "Final streamed text differs from the saved result text", streamed.requestId);
    if (kind === "answer") check(`${name}: draft cleared`, rep.challenge.session?.answer === "", "Answer turn did not clear the server draft");
  }
  console.log(`  ${kind}: outcome=${saved?.result?.outcome} replyLen=${saved?.result?.text?.length ?? 0} covered=${saved?.result?.covered ?? "-"} step=${saved?.result?.step ?? "-"} wrapUp=${rep.challenge.interview?.wrapUp}`);
  return { command, saved, body, streamed };
}
/** Finish like the app: the draft is uploaded, then completion with the final revision; feedback is a summarize job. */
async function finish(rep: Rep, name: string, finalNote: string) {
  const revision = rep.challenge.session?.revision ?? 0;
  const draft = await api(`${name} draft`, "PUT", `challenges/${rep.id}/draft`, { body: { answer: finalNote, revision }, command: true, contract: "Revision", dto: "RevisionResponse" });
  const command = uuid();
  const begun = now();
  const completed = await api(name, "POST", `challenges/${rep.id}/complete`, { body: { answer: finalNote, revision: draft.json.revision, receipts: [], guidanceMode: rep.mode }, command, contract: "Challenge", dto: "Challenge" });
  check(`${name}: completed`, completed.json.lifecycle === "completed", `Complete left lifecycle ${completed.json.lifecycle}`, "bug", completed.requestId);
  const replay = await api(`${name} replay`, "POST", `challenges/${rep.id}/complete`, { body: { answer: finalNote, revision: draft.json.revision, receipts: [], guidanceMode: rep.mode }, command, contract: "Challenge" });
  check(`${name}: replay idempotent`, replay.json.lifecycle === "completed", "Replayed completion did not return the completed challenge", "bug", replay.requestId);
  const job = await waitJob(`${name} feedback`, command, begun);
  rep.challenge = await getChallenge(`${name} result`, rep.id);
  const reflection = rep.challenge.reflection;
  check(`${name}: reflection`, !!reflection, "No reflection after the summarize job finished");
  console.log(`  feedback job=${job?.status} ticket=${rep.challenge.ticket ?? "-"} summaryLen=${reflection?.summary?.length ?? 0} evidence=${reflection?.evidence?.length ?? 0} verdict=${reflection?.debrief?.verdict ?? "-"} lesson=${reflection?.lesson ? "yes" : "no"} guidance=${reflection?.guidanceMode ?? "-"}`);
  return rep.challenge;
}

// ---------------------------------------------------------------------------------------------------------------
// Voice, as LiveVoice.swift drives it

async function voiceSession(rep: Rep, name: string, speak: boolean) {
  const report: Record<string, unknown> = { name, speak };
  (run.voice[name] as unknown) = report;
  let peer: Peer | null = null;
  try {
    peer = await openPeer(name);
  } catch (error) {
    finding("script", name, "Couldn't create a WebRTC offer with werift: " + (error as Error).message);
    return report;
  }
  const id = uuid();
  try {
    const started = await api(`${name} start`, "POST", `challenges/${rep.id}/voice`, {
      body: { sdp: peer.sdp, revision: rep.challenge.session?.revision ?? 0, guidanceMode: rep.mode, practiceProfile: profile }, command: id,
      contract: "VoiceConnection", dto: "VoiceConnection",
    });
    Object.assign(report, { id, startMs: Math.round(started.ms), sessionSeconds: started.json.sessionSeconds, expiresAt: started.json.expiresAt, answerSdpLength: started.json.sdp?.length });
    check(`${name}: id echoes command`, started.json.id === id, "Voice session id differs from the Idempotency-Key", "bug", started.requestId);
    const closed = { seen: false, usageSeconds: undefined as number | undefined };
    peer.on(event => {
      if (event.type === "session.closed") { closed.seen = true; closed.usageSeconds = event.usage?.seconds; }
      if (event.type === "session.usage.updated") closed.usageSeconds = event.usage?.seconds;
      if (event.type === "error") report.providerErrors = [...(report.providerErrors as string[] ?? []), String(event.error?.code ?? event.error?.type ?? "unknown")];
    });
    const opened = now();
    try { await peer.answer(started.json.sdp); }
    catch (error) { finding("script", name, "werift rejected the provider's SDP answer: " + (error as Error).message); }
    const connected = await peer.waitFor(() => peer!.stats.connectionState === "connected", 10_000);
    if (connected) peer.startSilence();
    const channelOpen = await peer.waitFor(() => peer!.stats.channelState === "open", connected ? 5000 : 1);
    const sessionStarted = await peer.waitFor(() => (peer!.events["session.started"] ?? 0) > 0, channelOpen ? 5000 : 1);
    if (sessionStarted) peer.send({ type: "session.input_audio.mute" });
    Object.assign(report, { connected, channelOpen, sessionStarted, connectMs: Math.round(now() - opened) });
    if (!connected) finding("observation", name, `WebRTC didn't reach connected within 10 s (ice=${peer.stats.iceState}); continuing with the app's event path`);

    if (speak) {
      // Fragments as the app persists provider transcript deltas: ids are provider event ids, sequence is per session.
      const base = Math.round(now() - opened);
      const fragments = [
        { speaker: "assistant", text: "Hey, so walk me through how you'd start on this one." },
        { speaker: "user", text: "Okay so first I'd pin down the scale, I'm thinking a few thousand writes a second and reads that can lag a bit." },
        { speaker: "user", text: "Then an API tier, a queue for the slow work, and workers that are idempotent so retries are safe." },
      ].map((fragment, index) => ({ id: "evt_" + uuid().replace(/-/g, "").slice(0, 20), sequence: index, ...fragment, startMs: base + index * 4000, endMs: base + index * 4000 + 3500 }));
      const first = await api(`${name} events`, "POST", `challenges/${rep.id}/voice/${id}/events`, { body: { fragments: fragments.slice(0, 2), closed: false, finalized: false }, contract: undefined, dto: "VoiceAck" });
      check(`${name}: events accepted`, JSON.stringify(first.json.accepted) === JSON.stringify(fragments.slice(0, 2).map(f => f.id)), "Accepted ids differ from the sent fragments", "bug", first.requestId);
      const second = await api(`${name} events 2`, "POST", `challenges/${rep.id}/voice/${id}/events`, { body: { fragments: fragments.slice(1), closed: false, finalized: false }, dto: "VoiceAck" });
      check(`${name}: duplicate fragment accepted`, (second.json.accepted as string[]).includes(fragments[1].id), "Re-sent fragment was not acknowledged", "bug", second.requestId);
      await api(`${name} conflicting fragment`, "POST", `challenges/${rep.id}/voice/${id}/events`, { body: { fragments: [{ ...fragments[1], text: fragments[1].text + " (edited)" }], closed: false, finalized: false }, expect: [409], quiet: true })
        .catch(error => { if (error instanceof ApiFailure) finding("bug", `${name} conflicting fragment`, `A conflicting transcript fragment was not refused with 409 (got ${error.status})`, error.requestId); });
      const delegation = "dlg_" + uuid().replace(/-/g, "").slice(0, 20);
      const delegated = await api(`${name} delegate`, "POST", `challenges/${rep.id}/voice/${id}/delegate`, { body: { id: delegation }, dto: "VoiceReply" });
      const guidance = String(delegated.json.text ?? "");
      Object.assign(report, { delegateMs: Math.round(delegated.ms), delegateTextLength: guidance.length, delegateTrimmedLength: guidance.trim().replace(/\s+/g, " ").length, delegateWords: guidance.split(/\s+/).filter(Boolean).length, delegateStep: delegated.json.step ?? null });
      const sentences = guidance.split(/(?<=[.?!])\s+/).map(x => x.trim().toLowerCase()).filter(Boolean);
      Object.assign(report, { delegateSentences: sentences.length, delegateUniqueSentenceRatio: sentences.length ? Math.round(new Set(sentences).size / sentences.length * 100) / 100 : null, delegateEndsCleanly: /[.?!]["')]?$/.test(guidance.trim()) });
      if (guidance.length >= 2000) finding("observation", `${name} delegate`, `Spoken guidance is ${guidance.length} chars (${report.delegateWords} words, ${report.delegateSentences} sentences, unique ratio ${report.delegateUniqueSentenceRatio}, ends cleanly: ${report.delegateEndsCleanly}) for one delegation; the schema caps text at 2400`, delegated.requestId);
      if (delegated.ms > 12_000) finding("bug", `${name} delegate`, `Delegation took ${Math.round(delegated.ms)} ms, past the app's 15 s guidance deadline budget`, delegated.requestId);
      const replay = await api(`${name} delegate replay`, "POST", `challenges/${rep.id}/voice/${id}/delegate`, { body: { id: delegation }, dto: "VoiceReply" });
      check(`${name}: delegate replay`, replay.json.text === delegated.json.text, "Replayed delegation returned different guidance", "bug", replay.requestId);
      // Talk for a little while so billing is visibly non-zero; keep it short to stay cheap.
      await sleep(8000);
    } else {
      await sleep(1500);
    }
    if (channelOpen) peer.send({ type: "session.close" });
    const confirmed = channelOpen ? await peer.waitFor(() => closed.seen, 5000) : false;
    const elapsedSeconds = (now() - opened) / 1000;
    const usageSeconds = closed.usageSeconds ?? Math.round(elapsedSeconds * 10) / 10;
    // The app sends finalized only after the provider confirmed the close; a silent session needs it to be waived.
    const finalized = confirmed || !speak;
    if (!confirmed) finding("observation", name, `Provider close not confirmed over the data channel; sending finalized=${finalized}${finalized ? " (simulated confirmation)" : ""}`);
    const close = await api(`${name} close`, "POST", `challenges/${rep.id}/voice/${id}/events`, { body: { fragments: [], closed: true, finalized, usageSeconds }, dto: "VoiceAck" });
    Object.assign(report, { providerConfirmedClose: confirmed, finalized, reportedUsageSeconds: usageSeconds, providerUsageSeconds: closed.usageSeconds ?? null, elapsedSeconds: Math.round(elapsedSeconds), closeStatus: close.status });
    report.closed = true;
  } catch (error) {
    // Like LiveVoice.finalize after a failure: an unconfirmed close, so the reservation never blocks the account.
    if (report.id && !report.closed) await api(`${name} abandon`, "POST", `challenges/${rep.id}/voice/${id}/events`, { body: { fragments: [], closed: true, finalized: false } }).catch(() => null);
    throw error;
  } finally {
    Object.assign(report, { events: { ...peer.events }, marks: { ...peer.marks }, rtp: peer.stats });
    await peer.close();
    save();
  }
  return report;
}

// ---------------------------------------------------------------------------------------------------------------
// The run

const profile = {
  goals: "Pass system design rounds for backend roles within two months.",
  background: "Final-year CS student. Built a couple of Go and TypeScript services, one internship on a payments team.",
  preferences: "Be direct and casual, push me on trade-offs, keep replies short.",
};
const timezone = "Europe/Berlin";
const targetDate = new Date(Date.now() + 45 * 86_400_000).toISOString().slice(0, 10);
const settings = {
  practiceProfile: profile,
  learningPlan: { version: 1, objective: "interview", roleTrack: "backend", weakAreas: ["async", "reliability"], dailyGoalMinutes: 15, targetDate },
  onboardingComplete: true, focus: "System design", difficulty: "medium", engineeringLevel: "junior", timezone,
  dailyMinutes: 19 * 60, reminderEnabled: true, aiMode: "managed", model: "openai/gpt-6-luna", questionFormatting: true,
};
const ids = { challenges: new Set<string>(), voice: new Set<string>(), jobs: new Set<string>(), questions: new Set<string>() };
let account: string | null = null;
let clerkUser: string | null = null;
let entitlement: string | null = null;
let inviteHash: string | null = null;
let deletionRequested = false;

async function setup() {
  const email = `drillbit-e2e-${Date.now()}+clerk_test@example.com`;
  // The development instance has email identifiers turned off; fall back to a username, which it accepts.
  let user = await timed("clerk: create user (email)", () => clerk("POST", "/users", { email_address: [email], skip_password_requirement: true }), r => ({ status: r.status, errors: r.errors }));
  if (user.status === 422 && user.errors?.includes("form_param_unknown"))
    user = await timed("clerk: create user (username)", () => clerk("POST", "/users", { username: `drillbit-e2e-${Date.now()}`, external_id: `drillbit-e2e-${Date.now()}`, skip_password_requirement: true }), r => ({ status: r.status, errors: r.errors }));
  if (user.status !== 200 || !user.json?.id) throw new Error(`Clerk user creation failed (${user.status} ${user.errors ?? ""})`);
  clerkUser = run.clerkUser = user.json.id;
  const session = await timed("clerk: create session", () => clerk("POST", "/sessions", { user_id: clerkUser }), r => ({ status: r.status, errors: r.errors }));
  if (session.status !== 200 || !session.json?.id) throw new Error(`Clerk session creation failed (${session.status} ${session.errors ?? ""})`);
  clerkSession = session.json.id;
  await timed("clerk: mint drillbit token", () => token());

  const first = await api("bootstrap (new account)", "GET", "bootstrap", { contract: "Bootstrap", dto: "Bootstrap" });
  account = run.account = first.json.account.id;
  check("new account is invited", first.json.account.status === "invited", `New account status ${first.json.account.status} (development has no open signup)`);
  await api("practice before invite refused", "POST", "daily-question", { body: {}, expect: [403], quiet: true })
    .then(r => check("invite gate", r.json?.error?.code === "invite_required", `Gate answered ${r.json?.error?.code}`))
    .catch(error => { if (error instanceof ApiFailure) finding("bug", "invite gate", `Expected 403 invite_required, got ${error.status} ${error.code}`, error.requestId); else throw error; });

  const code = randomBytes(24).toString("base64url");
  inviteHash = createHash("sha256").update(code).digest("hex");
  await timed("d1: create invite", () => d1(`INSERT INTO invites(hash,created_at) VALUES(${safe(inviteHash!)},${safe(iso())})`));
  await api("invite: wrong code refused", "POST", "invite", { body: { code: randomBytes(24).toString("base64url") }, expect: [422], quiet: true })
    .catch(error => { if (error instanceof ApiFailure) finding("bug", "invite: wrong code", `Expected 422, got ${error.status}`, error.requestId); else throw error; });
  await api("invite: redeem", "POST", "invite", { body: { code }, contract: "OK", dto: "EmptyResponse" });
  await api("invite: replay by owner", "POST", "invite", { body: { code }, contract: "OK" });

  const free = await api("bootstrap (active, free)", "GET", "bootstrap", { contract: "Bootstrap", dto: "Bootstrap" });
  check("active after invite", free.json.account.status === "active", `Status ${free.json.account.status} after redeeming`);
  check("free before entitlement", free.json.account.plan === "free", `Plan ${free.json.account.plan} before entitlement`);
  run.checks.freeVoice = free.json.capabilities?.voice;
  run.checks.freePractice = free.json.practice;

  const at = iso();
  entitlement = `manual-e2e-20261108-${randomBytes(4).toString("hex")}`;
  await timed("d1: insert manual Pro entitlement", () => d1(`INSERT INTO entitlements(original_transaction_id,account_id,product_id,environment,status,active_until,signed_at,created_at,updated_at) VALUES(${safe(entitlement!)},${safe(account!)},'dawi.drillbit.pro.yearly','Manual','active',NULL,${safe(at)},${safe(at)},${safe(at)})`));
  const pro = await api("bootstrap (pro)", "GET", "bootstrap", { contract: "Bootstrap", dto: "Bootstrap" });
  check("bootstrap reports Pro", pro.json.account.plan === "pro", `Plan ${pro.json.account.plan} after entitlement`);
  check("Pro has no free-rep gate", pro.json.practice?.freeReps === false && pro.json.practice?.available === true, `practice=${JSON.stringify(pro.json.practice)}`);
  check("Pro voice available", pro.json.capabilities?.voice?.available === true && pro.json.capabilities?.voice?.plan === "pro", `voice=${JSON.stringify(pro.json.capabilities?.voice)}`);
  run.checks.proVoiceBefore = pro.json.capabilities?.voice;
  console.log(`  account ${short(account)} plan=${pro.json.account.plan} todayPlan=${pro.json.todayPlan?.state} voice.sessionSeconds=${pro.json.capabilities?.voice?.sessionSeconds}`);
}

async function onboarding() {
  const taxonomy = await api("taxonomy", "GET", "taxonomy", { contract: "Taxonomy", dto: "TaxonomyResponse" });
  console.log(`  concepts=${taxonomy.json.concepts.length}`);
  const preview = await api("settings: personalization preview", "POST", "settings/preview", { body: profile, contract: "PersonalizationPreview", dto: "PersonalizationPreview" });
  console.log(`  previewLen=${preview.json.text?.length}`);
  const saved = await api("settings: finish onboarding", "PUT", "settings", { body: settings, contract: "Settings", dto: "PracticeSettings" });
  check("settings saved", saved.json.onboardingComplete === true && saved.json.timezone === timezone && saved.json.learningPlan?.targetDate === targetDate, "Saved settings differ from what was sent");
  const replay = await api("settings: replay onboarding as unfinished", "PUT", "settings", { body: { ...settings, onboardingComplete: false }, contract: "Settings" });
  check("onboarding never un-finishes", replay.json.onboardingComplete === true, "A replayed setup sent the account back through onboarding");
  await api("settings: past target date refused", "PUT", "settings", { body: { ...settings, learningPlan: { ...settings.learningPlan, targetDate: "2020-01-01" } }, expect: [400], quiet: true })
    .catch(error => { if (error instanceof ApiFailure) finding("bug", "settings: past target date", `Expected 400 invalid_target_date, got ${error.status} ${error.code}`, error.requestId); else throw error; });
  const boot = await api("bootstrap (after onboarding)", "GET", "bootstrap", { contract: "Bootstrap", dto: "Bootstrap" });
  check("onboarding persisted", boot.json.settings.onboardingComplete === true, "Bootstrap settings not onboarded");
  console.log(`  todayPlan=${boot.json.todayPlan?.state} goal=${boot.json.todayPlan?.dailyGoalMinutes}`);
}

async function dailyRep() {
  const daily = await api("daily question", "POST", "daily-question", { body: {}, contract: "DailyQuestion", dto: "DailyQuestionResponse" });
  check("daily question prepares a job", !!daily.json.job, `Daily answered ${daily.json.challenge ? "with a challenge" : "with nothing"} instead of a job`, "bug", daily.requestId);
  const expectedDay = new Intl.DateTimeFormat("en-CA", { timeZone: timezone }).format(new Date());
  check("daily uses account-local day", daily.json.day === expectedDay, `Daily day ${daily.json.day}, expected ${expectedDay}`);
  let challenge = daily.json.challenge;
  if (daily.json.job) { ids.jobs.add(daily.json.job.id); challenge = await prepared("daily question", daily.json.job); }
  if (!challenge) throw new Error("No daily question");
  const again = await api("daily question (second visit)", "POST", "daily-question", { body: {}, contract: "DailyQuestion", dto: "DailyQuestionResponse" });
  check("second visit reuses the question", again.json.challenge?.id === challenge.id && !again.json.job, "Second daily visit didn't return the same question");
  ids.challenges.add(challenge.id);
  if (challenge.questionId) ids.questions.add(challenge.questionId);

  const rep: Rep = { id: challenge.id, mode: "coach_me", challenge: await start("rep A: start", challenge.id) };
  rep.challenge = await getChallenge("rep A: open", rep.id);
  const first = await turn(rep, "rep A: answer 1", "answer", ANSWERS[0]);
  const replay = await api("rep A: answer 1 replay", "POST", `challenges/${rep.id}/interview`, { body: first.body, command: first.command, contract: "InterviewState" });
  check("interview replay is idempotent", replay.json.turns.filter((t: any) => t.id === first.command).length === 1 && replay.json.turns.length === rep.challenge.interview.turns.length, "Replaying an answer command changed the transcript", "bug", replay.requestId);
  await api("rep A: stale promptId refused", "POST", `challenges/${rep.id}/interview`, { body: { ...first.body, promptId: "original", revision: rep.challenge.session.revision }, command: true, expect: [409], quiet: true })
    .catch(error => { if (error instanceof ApiFailure) finding("bug", "rep A: stale promptId", `Expected 409 revision_conflict, got ${error.status} ${error.code}`, error.requestId); else throw error; });
  if (!rep.challenge.interview.wrapUp) await turn(rep, "rep A: clarification", "clarification", "Should I assume a single region, or multi-region from day one?");
  if (!rep.challenge.interview.wrapUp) await turn(rep, "rep A: nudge (hint)", "hint");

  // Explicit help from the practice companion (durable help job, dispatched through the Workflow).
  const helpStarted = now();
  const help = await api("rep A: help (hint)", "POST", `challenges/${rep.id}/help`, { body: { kind: "hint", mode: "coach", question: "", revision: rep.challenge.session.revision }, command: true, contract: "Job", dto: "Job" });
  ids.jobs.add(help.json.id);
  const helpJob = await waitJob("rep A: help", help.json.id, helpStarted);
  rep.challenge = await getChallenge("rep A: help result", rep.id);
  const helpResult = rep.challenge.help?.find((h: any) => h.id === help.json.id);
  check("help result present", helpJob?.status === "completed" && !!helpResult?.body, `Help job ${helpJob?.status}; result ${helpResult ? "has no body" : "missing"}`);
  console.log(`  help bodyLen=${helpResult?.body?.length ?? 0} status=${helpResult?.status}`);

  if (!rep.challenge.interview.wrapUp) await turn(rep, "rep A: answer 2", "answer", ANSWERS[1]);
  if (!rep.challenge.interview.wrapUp) await turn(rep, "rep A: example", "example");
  if (!rep.challenge.interview.wrapUp) await turn(rep, "rep A: answer 3", "answer", ANSWERS[2]);
  else await turn(rep, "rep A: continue", "continue");
  const done = await finish(rep, "rep A: complete", "Summary: outbox + idempotent consumers for durability, cache with jittered TTL, partition by tenant.");
  check("rep A gets ticket 1", done.ticket === 1, `Ticket ${done.ticket}`);
  return done;
}

async function learning(repA: any) {
  const boot = await api("bootstrap (after rep A)", "GET", "bootstrap", { contract: "Bootstrap", dto: "Bootstrap" });
  check("today counts the rep", boot.json.todayPlan?.completedToday === 1 && boot.json.todayPlan?.completedTotal === 1, `todayPlan=${JSON.stringify(boot.json.todayPlan)}`);
  check("no active challenge after finishing", boot.json.challenge === null, `Bootstrap still has active challenge ${short(boot.json.challenge?.id)}`);
  console.log(`  todayPlan=${boot.json.todayPlan?.state} due=${boot.json.todayPlan?.dueRecallCount} nextTicket=${boot.json.todayPlan?.nextTicket}`);

  const deck = await api("recall deck", "GET", "recall", { contract: "RecallDeck", dto: "RecallDeckResponse" });
  const cards = deck.json.cards as any[];
  console.log(`  recall cards=${cards.length} due=${deck.json.dueCount}`);
  check("recall cards from feedback", cards.length > 0 && cards.every(c => c.sourceChallengeId === repA.id), `cards=${cards.length}, sources=${[...new Set(cards.map(c => short(c.sourceChallengeId)))]}`, "observation");
  if (cards.length) {
    const command = uuid();
    const reviewed = await api("recall review (got it)", "POST", `recall/${cards[0].id}/review`, { body: { rating: "got_it", responseMs: 8200 }, command, contract: "RecallReviewResult", dto: "RecallReviewResponse" });
    check("recall schedule advanced", reviewed.json.card.repetitions === cards[0].repetitions + 1 && reviewed.json.card.intervalDays >= 1, `card after review: reps=${reviewed.json.card.repetitions} interval=${reviewed.json.card.intervalDays}`);
    const replay = await api("recall review replay", "POST", `recall/${cards[0].id}/review`, { body: { rating: "got_it", responseMs: 8200 }, command, contract: "RecallReviewResult" });
    check("recall review idempotent", replay.json.card.repetitions === reviewed.json.card.repetitions, "Replayed review advanced the card twice", "bug", replay.requestId);
  }
  const library = await api("library", "GET", "library", { contract: "LibraryPage", dto: "LibraryPage" });
  for (const q of library.json.questions) ids.questions.add(q.id);
  check("library has the question", !repA.questionId || library.json.questions.some((q: any) => q.id === repA.questionId), "Practised question missing from the Library");
  const coverage = await api("library coverage", "GET", "library/coverage", { contract: "Coverage", dto: "CoverageResponse" });
  const covered = (coverage.json.concepts as any[]).filter(c => c.completedAttempts > 0);
  check("coverage counts rep A", covered.some(c => c.conceptId === repA.primaryConceptId), `Covered concepts ${covered.map(c => c.conceptId)} lack ${repA.primaryConceptId}`);
  if (repA.questionId) await api("question detail", "GET", `questions/${repA.questionId}`, { contract: "LibraryDetail", dto: "LibraryDetail" });
  const history = await api("sessions history", "GET", "sessions", { contract: "HistoryPage", dto: "HistoryPage" });
  check("history lists rep A", history.json.sessions.some((s: any) => s.id === repA.id && s.reflection), "Finished rep missing from history");
  await api("memory", "GET", "memory", { contract: "Memory", dto: "MemoryResponse" });
  const queued = await api("queue follow-up for tomorrow", "PUT", `challenges/${repA.id}/next`, { contract: "QueuedNextResult", dto: "QueuedNextResult" });
  check("follow-up queued", queued.json.queuedNext?.sourceId === repA.id, "Queued follow-up not returned");
  const unqueued = await api("unqueue follow-up", "DELETE", `challenges/${repA.id}/next`, { contract: "QueuedNextResult", dto: "QueuedNextResult" });
  check("follow-up unqueued", unqueued.json.queuedNext === null, "Follow-up still queued");
}

async function extrasAndVoice() {
  const preparation = { focus: "System design", kind: "design", difficulty: "medium", engineeringLevel: "junior", guidanceMode: "mock_interview", interviewStyle: "standard", instruction: "" };
  const extraB = await generate("extra question 1", preparation);
  ids.challenges.add(extraB.challenge.id);
  const replay = await api("extra question 1 replay", "POST", "challenges", { body: preparation, command: extraB.command, contract: "Generation" });
  check("generation replay idempotent", replay.json.id === extraB.command || replay.json.challenge?.id === extraB.challenge.id, "Replayed generation command didn't return the same job", "bug", replay.requestId);
  const extraC = await generate("extra question 2 (swap)", { ...preparation, replaceId: extraB.challenge.id });
  ids.challenges.add(extraC.challenge.id);
  check("swap produced a new question", extraC.challenge.id !== extraB.challenge.id && extraC.challenge.lifecycle === "ready", `Swap returned ${short(extraC.challenge.id)} (${extraC.challenge.lifecycle})`);
  const replaced = await getChallenge("swapped-out question", extraB.challenge.id);
  check("swapped-out question retired", !["ready", "in_progress"].includes(replaced.lifecycle), `Swapped-out question is still ${replaced.lifecycle}`);
  console.log(`  swapped-out lifecycle=${replaced.lifecycle}`);

  const rep: Rep = { id: extraC.challenge.id, mode: "mock_interview", challenge: await start("rep C: start", extraC.challenge.id) };
  rep.challenge = await getChallenge("rep C: open", rep.id);
  await turn(rep, "rep C: answer 1", "answer", ANSWERS[0]);

  if (!existsSync(weriftPath)) finding("script", "voice", "werift is not installed under .local/e2e/voice; voice skipped");
  else {
    const before = (await api("bootstrap (before voice)", "GET", "bootstrap", { contract: "Bootstrap", dto: "Bootstrap" })).json.capabilities?.voice;
    run.voice.capabilityBefore = before;
    await voiceSession(rep, "voice 1 (spoken)", true);
    rep.challenge = await getChallenge("rep C: after voice", rep.id);
    const voiceTurn = rep.challenge.interview?.turns?.find((t: any) => t.kind === "voice" && t.voice?.length);
    if ((run.voice["voice 1 (spoken)"] as any)?.id) check("voice transcript in interview", (voiceTurn?.voice?.length ?? 0) === 3, `Voice turn has ${voiceTurn?.voice?.length ?? 0} fragments`);
    const middle = (await api("bootstrap (after voice 1)", "GET", "bootstrap", { contract: "Bootstrap", dto: "Bootstrap" })).json.capabilities?.voice;
    await voiceSession(rep, "voice 2 (silent)", false);
    const after = (await api("bootstrap (after voice 2)", "GET", "bootstrap", { contract: "Bootstrap", dto: "Bootstrap" })).json.capabilities?.voice;
    Object.assign(run.voice, { capabilityAfterFirst: middle, capabilityAfterSecond: after });
    check("voice still available on Pro", after?.available === true, `Voice after two sessions: ${JSON.stringify(after)}`);
    const rows = await d1(`SELECT id,status,usage_seconds,waived,finalized,provider_id IS NOT NULL AS provider FROM voice_sessions WHERE account_id=${safe(account!)} ORDER BY created_at`);
    const usage = await d1(`SELECT day,kind,count FROM usage WHERE account_id=${safe(account!)} AND kind IN ('voice_start','voice_reasoning')`);
    Object.assign(run.voice, { sessions: rows, usage });
    for (const row of rows) ids.voice.add(row.id);
    const [spoken, silent] = rows;
    const starts = usage.find(u => u.kind === "voice_start")?.count;
    if (!(run.voice["voice 1 (spoken)"] as any)?.id || !(run.voice["voice 2 (silent)"] as any)?.id) finding("script", "voice", "A voice session never started, so the billing and waiver checks are skipped");
    else {
      check("spoken session billed", !!spoken && spoken.waived === 0 && spoken.usage_seconds > 0 && spoken.status === "closed", `spoken=${JSON.stringify(spoken)}`);
      check("silent session waived", !!silent && silent.waived === 1, `silent=${JSON.stringify(silent)}`);
      check("waiver refunded its start", starts === 1, `voice_start count ${starts} (expected 1 after one waived start)`);
    }
    console.log(`  voice sessions=${rows.length} spoken.usage=${spoken?.usage_seconds}s waived=${rows.map(r => r.waived).join(",")} voice_start=${starts} sessionSeconds ${before?.sessionSeconds}→${after?.sessionSeconds}`);
  }
  const done = await finish(rep, "rep C: complete", "Mock round wrap: queue plus idempotent workers, outbox for durability.");
  check("rep C gets ticket 2", done.ticket === 2, `Ticket ${done.ticket}`);
}

async function warmUp() {
  const generated = await generate("warm-up question", { focus: "System design", kind: "design", difficulty: "easy", engineeringLevel: "junior", guidanceMode: "learn_together", warmUp: true, instruction: "" });
  const challenge = generated.challenge;
  ids.challenges.add(challenge.id);
  check("warm-up flagged", challenge.warmUp === true, "Warm-up question is not flagged warmUp");
  const rep: Rep = { id: challenge.id, mode: "learn_together", challenge: await start("warm-up: start", challenge.id) };
  rep.challenge = await getChallenge("warm-up: open", rep.id);
  console.log(`  guided path steps=${rep.challenge.path?.length ?? 0}`);
  await turn(rep, "warm-up: answer", "answer", ANSWERS[0]);
  const done = await finish(rep, "warm-up: complete", "");
  check("warm-up has no ticket", done.ticket === undefined || done.ticket === null, `Warm-up got ticket ${done.ticket}`);
  const history = await api("sessions history (after warm-up)", "GET", "sessions", { contract: "HistoryPage", dto: "HistoryPage" });
  check("warm-up excluded from history", !history.json.sessions.some((s: any) => s.id === challenge.id), "Warm-up shows up in session history");
  const deck = await api("recall deck (after warm-up)", "GET", "recall", { contract: "RecallDeck", dto: "RecallDeckResponse" });
  check("warm-up adds no recall", !deck.json.cards.some((c: any) => c.sourceChallengeId === challenge.id), "Warm-up produced Recall cards");
  const boot = await api("bootstrap (end of day)", "GET", "bootstrap", { contract: "Bootstrap", dto: "Bootstrap" });
  check("warm-up not counted today", boot.json.todayPlan?.completedToday === 2, `completedToday=${boot.json.todayPlan?.completedToday} (expected 2 counted reps)`);
  console.log(`  history=${history.json.sessions.length} recall=${deck.json.cards.length} todayPlan=${boot.json.todayPlan?.state}`);
}

async function exportAndWidget() {
  const sessions: any[] = [], questions: any[] = [];
  let cursor: string | null = null, pages = 0, settingsOut: any = null;
  do {
    const page: Call = await api(`account export page ${pages + 1}`, "GET", "account/export" + (cursor ? `?cursor=${encodeURIComponent(cursor)}` : ""), { contract: "AccountExport" });
    sessions.push(...page.json.sessions); questions.push(...page.json.questions);
    settingsOut ??= page.json.settings;
    cursor = page.json.nextCursor; pages++;
  } while (cursor && pages < 10);
  const foreignSessions = sessions.filter(s => !ids.challenges.has(s.id));
  const foreignQuestions = questions.filter(q => !ids.questions.has(q.id) && !sessions.some(s => s.questionId === q.id));
  const completed = sessions.filter(s => s.lifecycle === "completed");
  const text = JSON.stringify({ sessions, questions, settingsOut });
  run.checks.export = { pages, sessions: sessions.length, completed: completed.length, questions: questions.length, lifecycles: sessions.map(s => `${short(s.id)}:${s.lifecycle}${s.warmUp ? ":warmUp" : ""}`), bytes: text.length };
  check("export has no foreign sessions", foreignSessions.length === 0, `Export carries ${foreignSessions.length} sessions this account never created`);
  check("export questions are ours", foreignQuestions.length === 0, `Export carries ${foreignQuestions.length} questions not linked to this account's sessions`, "observation");
  check("export has the attempts", completed.length >= 2 && completed.every(s => s.reflection || s.warmUp), `Export completed=${completed.length}; reflections on ${completed.filter(s => s.reflection).length}`);
  check("export interview transcripts", completed.some(s => (s.interview?.turns?.length ?? 0) >= 4), "Export lacks the interview transcript");
  check("export has the settings", settingsOut?.practiceProfile?.goals === profile.goals, "Export settings don't match");
  check("export has no secrets", !/sk_(test|live)_|Bearer |"token"|ciphertext/i.test(text), "Export text contains secret-looking material");
  console.log(`  export pages=${pages} sessions=${sessions.length} completed=${completed.length} questions=${questions.length} bytes=${text.length}`);

  const device = await api("widget: register device", "POST", "devices", { contract: "Device", dto: "DeviceResponse" });
  const started = now();
  const widget = await fetch(`${BASE}/v1/widget`, { headers: { Authorization: `Bearer ${device.json.token}` } });
  const widgetJson = await widget.json().catch(() => null);
  record({ name: "widget: snapshot with device token", at: iso(), ms: now() - started, ok: widget.status === 200, method: "GET", path: "widget", status: widget.status, requestId: widget.headers.get("x-request-id") });
  conform("widget", widgetJson, "Widget", "WidgetSnapshot", widget.headers.get("x-request-id"));
  await api("widget: remove device", "DELETE", `devices/${device.json.id}`, { contract: "OK" });
}

async function costs() {
  const runs = await d1(`SELECT kind,model,COUNT(*) AS calls,SUM(input_tokens) AS input,SUM(output_tokens) AS output,ROUND(SUM(cost),5) AS cost FROM ai_runs WHERE account_id=${safe(account!)} GROUP BY kind,model ORDER BY kind`);
  const total = runs.reduce((sum, row) => sum + (row.cost ?? 0), 0);
  const voiceSeconds = ((run.voice.sessions as any[]) ?? []).reduce((sum, row) => sum + (row.usage_seconds ?? 0), 0);
  run.cost = { aiRuns: runs, openRouterUsd: Math.round(total * 10000) / 10000, voiceBilledSeconds: voiceSeconds, note: "ai_runs.cost is the OpenRouter-reported cost; live voice is billed by OpenAI per open minute and isn't in ai_runs." };
  const jobs = await d1(`SELECT id FROM jobs WHERE account_id=${safe(account!)}`);
  for (const job of jobs) ids.jobs.add(job.id);
  console.log(`  ai_runs calls=${runs.reduce((n, r) => n + r.calls, 0)} cost=$${(run.cost as any).openRouterUsd} voice=${voiceSeconds}s`);
}

async function deleteAccount() {
  const challengeIds = [...ids.challenges];
  const deleting = await api("account: delete", "DELETE", "account", { command: true, contract: "Deleting" });
  deletionRequested = true;
  check("delete accepted", deleting.status === 202 && deleting.json.status === "deleting", `Delete answered ${deleting.status} ${JSON.stringify(deleting.json)}`);
  // No more API calls with this account: a later authenticated request would recreate an account for the subject.
  const began = now();
  let remaining: any[] = [];
  while (now() - began < 360_000) {
    remaining = await d1(`SELECT status FROM accounts WHERE id=${safe(account!)}`);
    if (!remaining.length) break;
    await sleep(5000);
  }
  const deletionMs = Math.round(now() - began);
  record({ name: "account: deletion job finished", at: iso(), ms: deletionMs, ok: !remaining.length, data: { remaining } });
  check("account row deleted", !remaining.length, `Account still ${remaining[0]?.status} after ${deletionMs} ms`);
  const user = await clerk("GET", `/users/${clerkUser}`);
  run.cleanup.clerkUserAfterDeletion = user.status;
  check("Clerk user deleted by the Worker", user.status === 404, `Clerk user lookup answered ${user.status} after deletion`);
  await verifyGone(challengeIds);
}

async function verifyGone(challengeIds: string[]) {
  const tables = await d1("SELECT name,sql FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' AND name NOT LIKE '_cf_%'");
  const has = (sql: string, column: string) => new RegExp(`\\b${column}\\b`).test(sql ?? "");
  const list = (values: Iterable<string>) => [...values].map(safe).join(",") || "''";
  const parts: string[] = [`SELECT 'accounts' AS t,COUNT(*) AS n FROM accounts WHERE id=${safe(account!)}`, `SELECT 'invites(redeemed_by)',COUNT(*) FROM invites WHERE redeemed_by=${safe(account!)}`];
  for (const { name, sql } of tables) {
    if (name === "accounts" || !/^[a-z_0-9]+$/.test(name)) continue;
    if (has(sql, "account_id")) parts.push(`SELECT '${name}(account_id)',COUNT(*) FROM ${name} WHERE account_id=${safe(account!)}`);
    if (has(sql, "challenge_id")) parts.push(`SELECT '${name}(challenge_id)',COUNT(*) FROM ${name} WHERE challenge_id IN (${list(challengeIds)})`);
    if (has(sql, "source_challenge_id")) parts.push(`SELECT '${name}(source_challenge_id)',COUNT(*) FROM ${name} WHERE source_challenge_id IN (${list(challengeIds)})`);
    if (has(sql, "session_id")) parts.push(`SELECT '${name}(session_id)',COUNT(*) FROM ${name} WHERE session_id IN (${list(ids.voice)})`);
    if (has(sql, "job_id")) parts.push(`SELECT '${name}(job_id)',COUNT(*) FROM ${name} WHERE job_id IN (${list(ids.jobs)})`);
  }
  for (const name of ["help_results", "challenges", "jobs", "questions"]) {
    if (tables.some(t => t.name === name)) parts.push(`SELECT '${name}(id)',COUNT(*) FROM ${name} WHERE id IN (${list(name === "challenges" ? challengeIds : name === "questions" ? ids.questions : ids.jobs)})`);
  }
  if (entitlement) parts.push(`SELECT 'entitlements(manual row)',COUNT(*) FROM entitlements WHERE original_transaction_id=${safe(entitlement)}`);
  // D1 caps compound SELECTs, so every count is its own statement, sent in small batches.
  const statements = parts.map(part => part.replace(/^SELECT ('[^']*')(?: AS t)?,COUNT\(\*\)(?: AS n)?/, "SELECT $1 AS t,COUNT(*) AS n"));
  const rows: any[] = [];
  for (let at = 0; at < statements.length; at += 25) rows.push(...await d1(statements.slice(at, at + 25).join("; ")));
  const leftovers = rows.filter(row => Number(row.n) > 0);
  run.cleanup.residualRows = Object.fromEntries(rows.map(row => [row.t, row.n]));
  record({ name: "d1: verify account-owned rows gone", at: iso(), ms: 0, ok: leftovers.length === 0, data: { checked: rows.length, leftovers } });
  check("no account-owned rows left", leftovers.length === 0, `Rows left after deletion: ${leftovers.map(r => `${r.t}=${r.n}`).join(", ")}`);
}

/** Always runs: whatever the Worker didn't remove is removed here, after being reported. */
async function cleanup() {
  const notes: Record<string, unknown> = {};
  try {
    if (account) {
      const left = await d1(`SELECT status FROM accounts WHERE id=${safe(account)}`);
      if (left.length) {
        if (deletionRequested) finding("bug", "cleanup", "Account row survived DELETE /v1/account; removed by the script");
        await d1(`DELETE FROM invites WHERE redeemed_by=${safe(account)}`);
        await d1(`DELETE FROM accounts WHERE id=${safe(account)}`);
        notes.accountRemovedByScript = true;
      }
    }
    if (inviteHash) {
      const invite = await d1(`SELECT redeemed_by FROM invites WHERE hash=${safe(inviteHash)}`);
      if (invite.length) { await d1(`DELETE FROM invites WHERE hash=${safe(inviteHash)}`); notes.inviteRemovedByScript = true; }
    }
    if (entitlement) {
      const row = await d1(`SELECT account_id FROM entitlements WHERE original_transaction_id=${safe(entitlement)}`);
      if (row.length) { await d1(`DELETE FROM entitlements WHERE original_transaction_id=${safe(entitlement)}`); notes.entitlementRemovedByScript = true; }
      else notes.entitlementGone = true;
    }
  } catch (error) { notes.d1Error = (error as Error).message; finding("script", "cleanup", "D1 cleanup failed: " + (error as Error).message); }
  if (clerkUser) {
    const user = await clerk("GET", `/users/${clerkUser}`).catch(() => ({ status: 0 }));
    if (user.status === 200) {
      const removed = await clerk("DELETE", `/users/${clerkUser}`);
      notes.clerkUserRemovedByScript = removed.status;
      if (deletionRequested) finding("bug", "cleanup", "Clerk user survived account deletion; removed by the script");
    } else notes.clerkUserStatus = user.status;
  }
  Object.assign(run.cleanup, notes);
  console.log(`cleanup ${JSON.stringify(notes)}`);
}

async function sentry() {
  try {
    const process = Bun.spawn(["sentry", "issue", "list", "t23/drillbit-api", "--query", "environment:development firstSeen:-2h"], { stdout: "pipe", stderr: "pipe" });
    const [out, err] = await Promise.all([new Response(process.stdout).text(), new Response(process.stderr).text()]);
    await process.exited;
    run.sentry = { exit: process.exitCode, output: (out || err).slice(0, 6000) };
  } catch (error) { run.sentry = { error: (error as Error).message }; }
}

let repA: any = null;
try {
  await setup();
  await onboarding();
  repA = await dailyRep();
  for (const [name, work] of [["learning", () => learning(repA)], ["extras + voice", extrasAndVoice], ["warm-up", warmUp], ["export + widget", exportAndWidget]] as const) {
    try { console.log(`— ${name}`); await work(); }
    catch (error) {
      finding(error instanceof ApiFailure ? "bug" : "script", name, `Phase aborted: ${(error as Error).message}`, error instanceof ApiFailure ? error.requestId : undefined);
      // Leave nothing active that would block the next phase.
      const boot = await api(`${name}: recovery bootstrap`, "GET", "bootstrap").catch(() => null);
      const active = boot?.json?.challenge;
      if (active) await api(`${name}: skip leftover`, "POST", `challenges/${active.id}/skip`).catch(() => null);
    }
  }
  await costs();
  console.log("— deletion");
  await deleteAccount();
} catch (error) {
  finding(error instanceof ApiFailure ? "bug" : "script", "run", `Run aborted: ${(error as Error).stack?.split("\n").slice(0, 3).join(" | ")}`, error instanceof ApiFailure ? error.requestId : undefined);
  if (account && !deletionRequested) {
    try { await costs(); await deleteAccount(); } catch (inner) { finding("script", "deletion", "Deletion after failure failed: " + (inner as Error).message); }
  }
} finally {
  await cleanup();
  await sentry();
  run.finishedAt = iso();
  (run.checks as any).tokenMints = tokenMints;
  save();
  const failed = run.steps.filter(step => !step.ok).length;
  console.log(`\n${run.steps.length} steps, ${failed} failed, ${run.findings.length} findings → ${outFile}`);
}
