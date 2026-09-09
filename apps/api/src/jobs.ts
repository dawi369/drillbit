import { interviewSchemaFor, normalizeInterviewResult, interviewWrapUp } from "./interview";
import { interventionFor } from "./companion-contract";
import {
  WorkflowEntrypoint,
  type WorkflowEvent,
  type WorkflowStep,
} from "cloudflare:workers";
import {
  questionGenerationSchema,
  helpSchemaFor,
  MODEL_ID,
  normalizeSettings,
  exampleSchema,
  reflectionOutputSchema,
  parseJSON,
  timestamp,
  nextDaily,
  settingsSchema,
  type Settings,
} from "./domain";
import { structured } from "./ai";
import { activeChallenge, detail, dispatch, type Job } from "./store";
import type { Env } from "./platform";
export async function runJob(env: Env, id: string) {
  const job = await env.DB.prepare("SELECT * FROM jobs WHERE id=?")
    .bind(id)
    .first<Job>();
  if (!job || job.status === "completed" || job.status === "cancelled") return;
  const account = await env.DB.prepare(
    "SELECT status,subject FROM accounts WHERE id=?",
  )
    .bind(job.account_id)
    .first<{ status: string; subject: string }>();
  if (!account) return;
  if (job.kind === "delete_account") {
    if (!env.CLERK_SECRET_KEY)
      throw new Error("Clerk deletion is not configured");
    const result = await fetch(
      `https://api.clerk.com/v1/users/${encodeURIComponent(account.subject)}`,
      {
        method: "DELETE",
        headers: { Authorization: `Bearer ${env.CLERK_SECRET_KEY}` },
      },
    );
    if (!result.ok && result.status !== 404)
      throw new Error("Clerk deletion failed");
    await env.DB.batch([
      env.DB.prepare("DELETE FROM invites WHERE redeemed_by=?").bind(
        job.account_id,
      ),
      env.DB.prepare("DELETE FROM accounts WHERE id=?").bind(job.account_id),
    ]);
    return;
  }
  if (account.status !== "active") return;
  await env.DB.prepare(
    "UPDATE jobs SET status='running',error=NULL,updated_at=? WHERE id=? AND status NOT IN ('completed','cancelled')",
  )
    .bind(timestamp(), id)
    .run();
  const input = parseJSON<{
    settings: Settings;
    availableAt?: string;
    replaceId?: string;
    kind?: string;
    action?: { kind: string };
    context?: unknown;
    instruction?: string;
    interviewStyle?: string;
    turnId?: string;
    followUp?: unknown;
  }>(job.input);
  input.settings = normalizeSettings(input.settings);
  const now = timestamp();
  let data: unknown;
  if (job.kind === "generate") {
    const recent = await env.DB.prepare(
      "SELECT c.data,r.data AS reflection FROM challenges c LEFT JOIN reflections r ON r.challenge_id=c.id WHERE c.account_id=? AND c.lifecycle IN ('completed','skipped') ORDER BY c.created_at DESC LIMIT 20",
    )
      .bind(job.account_id)
      .all();
    data = await structured(
      env,
      job.account_id,
      input.settings,
      "generate",
      {
        settings: input.settings,
        kind: input.kind ?? "auto",
        instruction: input.instruction,
        followUp: input.followUp,
        recent: recent.results,
      },
      questionGenerationSchema,
    );
    const generated = data as import("zod").z.infer<
      typeof questionGenerationSchema
    >;
    // Derive the private checklist from visible requirements rather than trusting a second generated rubric.
    data = {
      ...generated,
      evaluationCriteria: [generated.prompt, ...generated.constraints],
      prompt: generated.constraints.length
        ? generated.prompt +
          "\n\nConstraints\n" +
          generated.constraints.map((value) => "• " + value).join("\n")
        : generated.prompt,
    };
    const lifecycle =
      input.availableAt && input.availableAt > now ? "prepared" : "ready";
    // An in-progress session always wins. A concurrent generation may become an unused prepared candidate.
    const active = await activeChallenge(env, job.account_id);
    const state = active && !input.replaceId ? "prepared" : lifecycle;
    await env.DB.batch([
      env.DB.prepare(
        "UPDATE challenges SET lifecycle='expired' WHERE id=? AND account_id=? AND lifecycle='ready' AND EXISTS(SELECT 1 FROM jobs WHERE id=? AND status='running') AND EXISTS(SELECT 1 FROM sessions WHERE challenge_id=? AND answer='')",
      ).bind(input.replaceId ?? "", job.account_id, id, input.replaceId ?? ""),
      env.DB.prepare(
        `INSERT OR IGNORE INTO challenges(id,account_id,lifecycle,data,created_at,available_at) SELECT ?,?,?,?,?,? WHERE EXISTS(SELECT 1 FROM jobs WHERE id=? AND status='running') AND EXISTS(SELECT 1 FROM accounts WHERE id=? AND status='active')`,
      ).bind(
        id,
        job.account_id,
        state,
        JSON.stringify({
          ...(data as object),
          model: MODEL_ID,
          promptVersion: "practice-v2",
          difficulty: input.settings.difficulty,
          engineeringLevel: input.settings.engineeringLevel,
          interviewStyle: input.interviewStyle ?? "standard",
        }),
        now,
        input.availableAt ?? now,
        id,
        job.account_id,
      ),
      env.DB.prepare(
        "INSERT OR IGNORE INTO sessions(challenge_id,updated_at) SELECT id,? FROM challenges WHERE id=?",
      ).bind(now, id),
      env.DB.prepare(
        "UPDATE jobs SET status='completed',updated_at=? WHERE id=? AND status='running'",
      ).bind(now, id),
    ]);
    return;
  }
  if (!job.challenge_id) return;
  if (job.kind === "interview") {
    const output = interviewWrapUp(input.context, input.action?.kind ?? "answer") ?? normalizeInterviewResult(await structured(env,job.account_id,input.settings,"interview",{...input.context as object, action: input.action},interviewSchemaFor(input.action?.kind ?? "answer")));
    const isAnswer = ["answer","continue"].includes(input.action?.kind ?? "");
    if ((isAnswer && output.outcome === "reply") || (!isAnswer && output.outcome !== "reply")) throw new Error("Invalid interview outcome");
    await env.DB.batch([
      env.DB.prepare("UPDATE interview_turns SET result=? WHERE id=? AND job_id=? AND result IS NULL AND EXISTS(SELECT 1 FROM jobs j JOIN challenges c ON c.id=j.challenge_id JOIN accounts a ON a.id=j.account_id WHERE j.id=? AND j.status='running' AND c.lifecycle='in_progress' AND a.status='active')").bind(JSON.stringify(output),input.turnId,id,id),
      env.DB.prepare("UPDATE jobs SET status='completed',updated_at=? WHERE id=? AND status='running' AND EXISTS(SELECT 1 FROM interview_turns WHERE job_id=? AND result IS NOT NULL)").bind(timestamp(),id,id),
    ]);
    return;
  }
  if (job.kind === "help") {
    const current = await detail(env, job.account_id, job.challenge_id);
    if (!["ready", "in_progress"].includes(current.lifecycle)) {
      await env.DB.prepare(
        "UPDATE jobs SET status='cancelled' WHERE id=? AND status='running'",
      )
        .bind(id)
        .run();
      return;
    }
    const output = await structured(
      env,
      job.account_id,
      input.settings,
      input.action!.kind,
      { ...(input.context as object), action: input.action },
      ["nudge", "guide"].includes(input.action!.kind)
        ? interventionFor(input.action!.kind)
        : helpSchemaFor(input.action!.kind),
    );
    if (input.action!.kind !== "draft") output.suggestedAnswer = null;
    if (
      "outcome" in output &&
      (output.outcome === "no_intervention" || !output.body.trim())
    ) {
      output.outcome = "no_intervention";
      output.body = "";
      Object.assign(output, { suggestedFocus: null, plan: [] });
    }
    await env.DB.batch([
      env.DB.prepare(
        "INSERT OR IGNORE INTO help_results(id,data) SELECT ?,? WHERE EXISTS(SELECT 1 FROM jobs j JOIN challenges c ON c.id=j.challenge_id JOIN accounts a ON a.id=j.account_id WHERE j.id=? AND j.status='running' AND c.lifecycle IN ('ready','in_progress') AND a.status='active')",
      ).bind(id, JSON.stringify(output), id),
      env.DB.prepare(
        "UPDATE jobs SET status='completed',updated_at=? WHERE id=? AND status='running' AND EXISTS(SELECT 1 FROM help_results WHERE id=?)",
      ).bind(timestamp(), id, id),
    ]);
    return;
  }
  const frozen =
    job.kind === "summarize"
      ? await env.DB.prepare(
          "SELECT data FROM completion_context WHERE challenge_id=?",
        )
          .bind(job.challenge_id)
          .first<{ data: string }>()
      : null;
  const context = frozen
    ? JSON.parse(frozen.data)
    : await detail(env, job.account_id, job.challenge_id);
  if (job.kind === "summarize")
    data = await structured(
      env,
      job.account_id,
      input.settings,
      "summarize",
      context,
      reflectionOutputSchema,
    );
  else if (job.kind === "reveal")
    data = await structured(
      env,
      job.account_id,
      input.settings,
      "reveal",
      context,
      exampleSchema,
    );
  else throw new Error("Unknown job kind");
  const table = job.kind === "summarize" ? "reflections" : "examples";
  await env.DB.batch([
    env.DB.prepare(
      `INSERT INTO ${table}(challenge_id,data,created_at) SELECT ?,?,? WHERE EXISTS(SELECT 1 FROM jobs WHERE id=? AND status='running') AND EXISTS(SELECT 1 FROM accounts WHERE id=? AND status='active') ON CONFLICT(challenge_id) DO UPDATE SET data=excluded.data,created_at=excluded.created_at`,
    ).bind(job.challenge_id, JSON.stringify(data), now, id, job.account_id),
    env.DB.prepare(
      "UPDATE jobs SET status='completed',updated_at=? WHERE id=? AND status='running'",
    ).bind(now, id),
  ]);
}
export class PracticeWorkflow extends WorkflowEntrypoint<
  Env,
  { jobId: string }
> {
  async run(event: WorkflowEvent<{ jobId: string }>, step: WorkflowStep) {
    try {
      const kind = await this.env.DB.prepare("SELECT kind FROM jobs WHERE id=?")
        .bind(event.payload.jobId)
        .first<{ kind: string }>();
      await step.do(
        "execute",
        {
          retries: {
            limit: ["help", "interview"].includes(kind?.kind ?? "") ? 0 : 2,
            delay: "10 seconds",
            backoff: "exponential",
          },
          timeout: "90 seconds",
        },
        () => runJob(this.env, event.payload.jobId),
      );
    } catch {
      await this.env.DB.prepare(
        "UPDATE jobs SET status='failed',error='The operation could not finish. Retry when connected.',updated_at=? WHERE id=? AND status NOT IN ('completed','cancelled')",
      )
        .bind(timestamp(), event.payload.jobId)
        .run();
    }
  }
}
export async function reconcile(env: Env) {
  const now = timestamp(),
    soon = new Date(Date.now() + 15 * 60000).toISOString(),
    activeSince = new Date(Date.now() - 7 * 86400000).toISOString();
  await env.DB.prepare(
    "UPDATE challenges SET lifecycle='expired' WHERE lifecycle='prepared' AND available_at<?",
  )
    .bind(new Date(Date.now() - 86400000).toISOString())
    .run();
  // Recover dispatch failures. Stable workflow IDs prevent duplicate execution.
  const pending = await env.DB.prepare(
    "SELECT id FROM jobs WHERE status='pending' ORDER BY created_at LIMIT 30",
  ).all<{ id: string }>();
  for (const row of pending.results) await dispatch(env, row.id);
  await env.DB.prepare(
    "UPDATE requests SET status='interrupted' WHERE status='running' AND updated_at<?",
  )
    .bind(new Date(Date.now() - 120000).toISOString())
    .run();
  const candidates = await env.DB.prepare(
    "SELECT id,account_id,available_at FROM challenges WHERE lifecycle='prepared' AND available_at<=? ORDER BY available_at DESC LIMIT 30",
  )
    .bind(now)
    .all<{ id: string; account_id: string; available_at: string }>();
  for (const c of candidates.results) {
    await env.DB.batch([
      env.DB.prepare(
        "UPDATE challenges SET lifecycle='expired' WHERE account_id=? AND lifecycle='ready' AND created_at<? AND EXISTS(SELECT 1 FROM challenges WHERE id=? AND lifecycle='prepared')",
      ).bind(
        c.account_id,
        new Date(new Date(c.available_at).getTime() - 15 * 60000).toISOString(),
        c.id,
      ),
      env.DB.prepare(
        "UPDATE challenges SET lifecycle='ready' WHERE id=? AND lifecycle='prepared' AND NOT EXISTS(SELECT 1 FROM challenges WHERE account_id=? AND lifecycle IN ('ready','in_progress'))",
      ).bind(c.id, c.account_id),
    ]);
  }
  const due = await env.DB.prepare(
    "SELECT s.account_id,s.data,s.next_due FROM settings s JOIN accounts a ON a.id=s.account_id WHERE s.next_due<=? AND a.status='active' AND a.last_seen>=? LIMIT 30",
  )
    .bind(soon, activeSince)
    .all<{ account_id: string; data: string; next_due: string }>();
  for (const row of due.results) {
    const settings = normalizeSettings(parseJSON(row.data));
    const next = nextDaily(
      settings,
      new Date(Math.max(Date.now(), new Date(row.next_due).getTime() + 1000)),
    );
    const id = crypto.randomUUID();
    const active = await activeChallenge(env, row.account_id);
    await env.DB.batch([
      env.DB.prepare(
        "UPDATE settings SET next_due=? WHERE account_id=? AND next_due=?",
      ).bind(next, row.account_id, row.next_due),
      env.DB.prepare(
        `INSERT OR IGNORE INTO jobs(id,account_id,kind,input,created_at,updated_at) SELECT ?,?,'generate',?,?,? WHERE ?!='in_progress' AND NOT EXISTS(SELECT 1 FROM jobs WHERE account_id=? AND kind='generate' AND status IN ('pending','running'))`,
      ).bind(
        id,
        row.account_id,
        JSON.stringify({ settings, availableAt: row.next_due }),
        now,
        now,
        active?.lifecycle ?? "",
        row.account_id,
      ),
    ]);
    await dispatch(env, id);
  }
}
