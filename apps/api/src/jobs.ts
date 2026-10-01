import {
    WorkflowEntrypoint,
    type WorkflowEvent,
    type WorkflowStep,
} from "cloudflare:workers";
import { z } from "zod";
import { partialJSONString, streamedInterview, streamedStructured, structured } from "./ai";
import { interventionFor } from "./companion-contract";
import {
    exampleSchema,
    helpSchemaFor,
    managedModel,
    normalizeSettings,
    parseJSON,
    questionGenerationSchema,
    reflectionOutputFor,
    reflectionOutputSchema,
    roundMinutes,
    roundTiming,
    timestamp,
    type Settings,
} from "./domain";
import { generationRequest } from "./generation";
import { historicalSnapshot } from "./history";
import { interviewSchemaFor } from "./interview";
import { groundReflection } from "./learning";
import { selectConcept } from "./library";
import type { Env } from "./platform";
import { plainQuestion } from "./prompts/formatting";
import { guidanceMode } from "./prompts/teaching";
import { activeChallenge, COUNTED, detail, dispatch, type Job } from "./store";
import { concepts } from "./taxonomy";
export async function runJob(env: Env, id: string) {
  const job = await env.DB.prepare("SELECT j.*,a.status AS account_status,a.subject AS account_subject FROM jobs j JOIN accounts a ON a.id=j.account_id WHERE j.id=?")
    .bind(id).first<Job & {account_status: string; account_subject: string; created_at: string}>();
  if (!job || job.status === "completed" || job.status === "cancelled") return;
  if (job.kind === "generate" && JSON.parse(job.input).availableAt) {
    await env.DB.prepare("UPDATE jobs SET status='cancelled' WHERE id=? AND status IN ('pending','running')").bind(id).run();
    return;
  }
  const account = {status: job.account_status, subject: job.account_subject};
  const queuedAt = Date.parse(job.created_at);
  if (Number.isFinite(queuedAt)) console.info(JSON.stringify({event: "inference_job_start", kind: job.kind, queuedMs: Math.max(0, Date.now() - queuedAt)}));
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
    guidanceMode?: string;
    turnId?: string;
    primaryConceptId?: string;
    followUp?: unknown;
    warmUp?: boolean;
  }>(job.input);
  input.settings = normalizeSettings(input.settings);
  const now = timestamp();
  let data: unknown;
  if (job.kind === "generate") {
    const followUp = input.followUp as {reflection?: {evidence?: {conceptId: string; signal: string}[]}; question?: {primaryConceptId?: string}} | undefined;
    const focus = followUp?.reflection?.evidence?.find(e => e.signal === "needs_practice")?.conceptId
      ?? followUp?.question?.primaryConceptId;
    const selectionAndPool = Promise.all([
      selectConcept(env,job.account_id,input.settings,input.primaryConceptId ?? focus),
      !input.instruction && !input.followUp && !input.warmUp ? env.DB.prepare("SELECT * FROM questions WHERE account_id=? AND eligible=1 AND json_extract(data,'$.engineeringLevel')=? AND (? IS NULL OR json_extract(data,'$.primaryConceptId')=?) ORDER BY eligibility_updated_at,id LIMIT 1").bind(job.account_id,input.settings.engineeringLevel!,input.primaryConceptId??null,input.primaryConceptId??null).first<{id:string;data:string}>() : null,
      env.DB.prepare(
        "SELECT c.data,c.lifecycle,c.completed_at,r.data AS reflection FROM challenges c LEFT JOIN reflections r ON r.challenge_id=c.id WHERE c.account_id=? AND c.lifecycle IN ('completed','skipped') AND " + COUNTED + " ORDER BY c.created_at DESC LIMIT 20",
      ).bind(job.account_id).all(),
    ]);
    const [selection, restored, recent] = await selectionAndPool;
    const { context: generationContext, schema: generationOutputSchema } = generationRequest(input, selection,
      await historicalSnapshot(env, job.account_id, "", [selection.primaryConceptId]));
    data = restored ? JSON.parse(restored.data) : await streamedStructured(
      env,
      job.account_id,
      input.settings,
      "generate",
      generationContext,
      generationOutputSchema,
      // The preview shows the question as it is written; the row is keyed by job like interview text.
      raw => {
        const title = partialJSONString(raw, "title");
        if (!title) return null;
        return env.DB.prepare("INSERT INTO interview_streams(job_id,text) SELECT ?,? WHERE EXISTS(SELECT 1 FROM jobs WHERE id=? AND status='running') ON CONFLICT(job_id) DO UPDATE SET text=excluded.text")
          .bind(id, JSON.stringify({ title, prompt: partialJSONString(raw, "prompt") }), id).run();
      },
    );
    const generated = data as import("zod").z.infer<
      typeof questionGenerationSchema
    >;
    if (!restored) {
      if(generated.primaryConceptId!==selection.primaryConceptId)throw new Error("question_concept_mismatch");

    }
    const questionID=restored?.id??id;
    // Derive the private checklist from visible requirements rather than trusting a second generated rubric.
    data = {
      ...generated,
      title: plainQuestion(generated.title),
      minutes: roundMinutes({ ...generated, engineeringLevel: input.settings.engineeringLevel }),
      questionId: questionID,
      topic: "System design",
      secondaryConceptIds: generated.tagEvidence.filter(e=>e.conceptId!==generated.primaryConceptId).map(e=>e.conceptId),
      conceptIds: [generated.primaryConceptId,...generated.tagEvidence.filter(e=>e.conceptId!==generated.primaryConceptId).map(e=>e.conceptId)],
      scenario: generated.scenario.trim().replace(/\s+/g," "),
      scenarioKey: generated.scenario.trim().replace(/\s+/g," ").toLowerCase(),
      taxonomyVersion: 1,
      selectionReason: restored ? "A question you added back to your pool." : selection.reason,
      selectionSnapshot: { ...selection, requestedLevel: input.settings.engineeringLevel, learningPlanVersion: input.settings.learningPlan?.version, instruction: input.instruction??"", recent: recent.results.slice(0,10).map(r=>{const q=JSON.parse(r.data as string);return {title:q.title,primaryConceptId:q.primaryConceptId,scenario:q.scenario};}) },
      evaluationCriteria: [generated.prompt, ...generated.constraints],
      prompt: !restored && generated.constraints.length
        ? generated.prompt +
          "\n\nConstraints\n" +
          generated.constraints.map((value) => "• " + value).join("\n")
        : generated.prompt,
    };
    if(!restored && await env.DB.prepare("SELECT id FROM questions WHERE account_id=? AND json_extract(data,'$.prompt')=? LIMIT 1").bind(job.account_id,(data as {prompt:string}).prompt).first())throw new Error("duplicate_question");
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
          model: managedModel("generate"),
          promptVersion: "practice-v2",
          difficulty: input.settings.difficulty,
          engineeringLevel: input.settings.engineeringLevel,
          interviewStyle: input.interviewStyle ?? "standard",
          guidanceMode: guidanceMode(input.guidanceMode),
          ...(input.warmUp ? { warmUp: true } : {}),
        }),
        now,
        input.availableAt ?? now,
        id,
        job.account_id,
      ),
      // A warm-up never joins the question pool or Library.
      ...(input.warmUp ? [] : [
        env.DB.prepare("INSERT OR IGNORE INTO questions(id,account_id,data,created_at,eligibility_updated_at) SELECT ?,account_id,data,created_at,created_at FROM challenges WHERE id=?").bind(questionID,id),
        env.DB.prepare("INSERT OR IGNORE INTO question_attempts(challenge_id,question_id) SELECT id,? FROM challenges WHERE id=?").bind(questionID,id),
        env.DB.prepare("UPDATE questions SET eligible=0,eligibility_revision=eligibility_revision+1 WHERE id=? AND EXISTS(SELECT 1 FROM question_attempts WHERE challenge_id=?)").bind(questionID,id),
      ]),
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
    const output = await streamedInterview(env,job.account_id,input.settings,{...input.context as object, action: input.action},interviewSchemaFor(input.action?.kind ?? "answer"), async text => {
      const saved = await env.DB.prepare("INSERT INTO interview_streams(job_id,text) SELECT ?,? WHERE EXISTS(SELECT 1 FROM jobs j JOIN challenges c ON c.id=j.challenge_id JOIN accounts a ON a.id=j.account_id WHERE j.id=? AND j.status='running' AND c.lifecycle='in_progress' AND a.status='active') ON CONFLICT(job_id) DO UPDATE SET text=excluded.text").bind(id,text,id).run();
      if (!saved.meta.changes) throw new Error("interview_cancelled");
    });
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
      { ...(input.context as object), practiceProfile: input.settings.practiceProfile, action: input.action },
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
  const context = { ...(frozen
    ? JSON.parse(frozen.data)
    : await detail(env, job.account_id, job.challenge_id)), practiceProfile: input.settings.practiceProfile };
  // The ending follows the style the session was run in; the frozen context keeps the challenge data under `question`.
  const round = context.question ?? context;
  const mode = guidanceMode(round.guidanceMode ?? context.interview?.guidanceMode);
  if (job.kind === "summarize")
    data = await structured(
      env,
      job.account_id,
      input.settings,
      "summarize",
      { ...context, guidanceMode: mode, ...(mode === "mock_interview" ? { timing: roundTiming(round, context.createdAt ?? timestamp(), Date.parse(context.completedAt ?? "") || Date.now()) } : {}) },
      reflectionOutputFor(mode),
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
  if (job.kind === "summarize") data = { ...groundReflection(data, context), guidanceMode: mode };
  const table = job.kind === "summarize" ? "reflections" : "examples";
  const warmUp = job.kind === "summarize" && !!(await env.DB.prepare("SELECT 1 FROM challenges c WHERE c.id=? AND NOT " + COUNTED).bind(job.challenge_id).first());
  const recallWrites = job.kind === "summarize" && !warmUp
    ? ((data as z.infer<typeof reflectionOutputSchema>).evidence ?? []).map((e, index) => {
        const reflection = data as z.infer<typeof reflectionOutputSchema>;
        const label = concepts.find(concept => concept.id === e.conceptId)?.label ?? e.conceptId;
        // The written card applies the quote to this question's own facts; the templates are the fallback.
        const question = e.recall?.prompt ?? (index === 0 && e.signal === "needs_practice" ? reflection.nextExercise
          : e.signal === "needs_practice" ? `What would you change about your ${label.toLowerCase()} decision?`
          : `Why did your ${label.toLowerCase()} decision work?`);
        const answer = e.recall?.answer ?? (e.signal === "needs_practice"
          ? `${e.observation} Next time: ${reflection.improve || reflection.takeaway}`
          : `${e.observation} Your evidence: “${e.quote}”`);
        const due = e.signal === "needs_practice" ? now : new Date(Date.parse(now) + 3 * 86400000).toISOString();
        return env.DB.prepare(`INSERT INTO recall_cards(id,account_id,source_challenge_id,concept_id,question,answer,due_at,created_at,updated_at)
          SELECT ?,?,?,?,?,?,?,?,? WHERE EXISTS(SELECT 1 FROM jobs WHERE id=? AND status='running')
          ON CONFLICT(account_id,source_challenge_id,concept_id) DO UPDATE SET question=excluded.question,answer=excluded.answer,due_at=MIN(recall_cards.due_at,excluded.due_at),updated_at=excluded.updated_at`)
          .bind(`${job.challenge_id}:${e.conceptId}`,job.account_id,job.challenge_id,e.conceptId,question,answer,due,now,now,id);
      })
    : [];
  await env.DB.batch([
    env.DB.prepare(
      `INSERT INTO ${table}(challenge_id,data,created_at) SELECT ?,?,? WHERE EXISTS(SELECT 1 FROM jobs WHERE id=? AND status='running') AND EXISTS(SELECT 1 FROM accounts WHERE id=? AND status='active') ON CONFLICT(challenge_id) DO UPDATE SET data=excluded.data,created_at=excluded.created_at`,
    ).bind(job.challenge_id, JSON.stringify(data), now, id, job.account_id),
    ...recallWrites,
    env.DB.prepare(
      "UPDATE jobs SET status='completed',updated_at=? WHERE id=? AND status='running'",
    ).bind(now, id),
  ]);
}
export async function runJobSafely(env: Env, id: string) {
  try {
    await runJob(env, id);
  } catch {
    await env.DB.prepare(
      "UPDATE jobs SET status='failed',error='The operation could not finish. Retry when connected.',updated_at=? WHERE id=? AND status NOT IN ('completed','cancelled')",
    ).bind(timestamp(), id).run();
  }
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
  if ((await env.DB.prepare("SELECT enabled FROM practice_epoch WHERE id=1").first<{enabled:number}>())?.enabled === 0) return;
  // Retire queued legacy timer-driven generation. Cron still recovers user-started jobs.
  await env.DB.prepare("UPDATE jobs SET status='cancelled' WHERE kind='generate' AND status='pending' AND json_extract(input,'$.availableAt') IS NOT NULL").run();
  // Inline interactive work normally finishes in seconds. If an isolate is
  // terminated mid-request, return the durable command to the Workflow-backed
  // recovery path after a conservative timeout.
  await env.DB.prepare("UPDATE jobs SET status='pending',updated_at=? WHERE kind IN ('interview','generate') AND status='running' AND updated_at<?")
    .bind(timestamp(), new Date(Date.now() - 120000).toISOString()).run();
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
}
