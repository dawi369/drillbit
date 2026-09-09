import { contextFor } from "./companion";
import { Fault, helpInputSchema, adoptionSchema, timestamp } from "./domain";
import {
  detail,
  dispatch,
  ownedChallenge,
  settingsFor,
  type Job,
} from "./store";
import { consumeUsage, type Env } from "./platform";

export async function requestHelp(
  env: Env,
  account: string,
  challengeId: string,
  command: string,
  body: unknown,
) {
  const action = helpInputSchema.parse(body);
  const existing = await env.DB.prepare("SELECT * FROM jobs WHERE id=?")
    .bind(command)
    .first<Job>();
  if (existing) {
    if (
      existing.account_id !== account ||
      existing.challenge_id !== challengeId ||
      existing.kind !== "help" ||
      JSON.stringify(JSON.parse(existing.input).action) !==
        JSON.stringify(action)
    )
      throw new Fault(
        "command_conflict",
        409,
        "This request belongs to another action.",
      );
    return existing;
  }
  const context = await detail(env, account, challengeId);
  if (!["ready", "in_progress"].includes(context.lifecycle))
    throw new Fault(
      "session_closed",
      409,
      "This practice is already finished.",
    );
  if (context.session?.revision !== action.revision)
    throw new Fault(
      "revision_conflict",
      409,
      "Sync your answer before requesting help.",
    );
  if (
    action.mode !== "guided" &&
    [
      "outline",
      "example",
      "draft",
      "guide",
      "starting_point",
      "alternative",
    ].includes(action.kind)
  )
    throw new Fault("guided_required", 400, "Choose Guided for this help.");
  if (
    ["check", "draft"].includes(action.kind) &&
    !String(context.session?.answer ?? "").trim()
  )
    throw new Fault("empty_answer", 400, "Write a little first.");
  if (action.kind === "question" && !action.question)
    throw new Fault("empty_question", 400, "Ask a question first.");
  const companion = await contextFor(env, account, challengeId);
  const capture = action.capture;
  const automatic =
    capture?.trigger === "change" || capture?.trigger === "pause";
  if (["nudge", "guide"].includes(action.kind) && !capture)
    throw new Fault("capture_required", 400, "Companion context is required.");
  if (capture) {
    if (
      companion.mode !== action.mode ||
      companion.revision !== capture.contextRevision ||
      companion.modeEpoch !== capture.modeEpoch ||
      companion.digest !== capture.digest ||
      companion.cycle !== capture.cycle
    )
      throw new Fault(
        "context_conflict",
        409,
        "The answer or assistance mode changed.",
      );
    if (
      automatic &&
      (env.COMPANION_AUTO_ENABLED !== "true" || companion.paused)
    )
      throw new Fault("automatic_disabled", 409, "Automatic help is paused.");
    if (
      automatic &&
      (companion.automaticCount >= 6 ||
        (companion.lastAutomaticAt &&
          Date.now() - Date.parse(companion.lastAutomaticAt) < 45000))
    )
      throw new Fault(
        "automatic_limit",
        409,
        "Automatic help is resting. You can still ask for help.",
      );
  }
  await consumeUsage(env, account, "help", 50);
  // Store only the relevant, bounded assistance history. Never send previous adopted answer copies.
  const snapshot = {
    question: JSON.parse(
      (await ownedChallenge(env, account, challengeId)).data,
    ),
    session: context.session,
    companion: {
      ...companion,
      suggestedFocus: context.help.at(-1)?.suggestedFocus ?? null,
      plan: context.help.at(-1)?.plan ?? [],
    },
    help: context.help
      .filter((h) => h.body)
      .slice(-3)
      .map((h) => ({
        id: h.id,
        kind: h.kind,
        body: String(h.body).slice(0, 1200),
        deliveries: h.deliveries,
      })),
  };
  const now = timestamp();
  let inserted: Job | null;
  if (capture) {
    const rows = await env.DB.batch([
      env.DB.prepare(
        `INSERT OR IGNORE INTO jobs(id,account_id,challenge_id,kind,input,created_at,updated_at)
        SELECT ?,?,?,'help',?,?,? WHERE EXISTS(SELECT 1 FROM challenges c JOIN sessions s ON s.challenge_id=c.id JOIN companion_context x ON x.challenge_id=c.id
        WHERE c.id=? AND c.account_id=? AND c.lifecycle IN ('ready','in_progress') AND s.revision=? AND x.revision=? AND x.mode_epoch=? AND x.mode=?
        AND (?=0 OR (x.paused=0 AND x.automatic_count<6 AND (x.last_automatic_at IS NULL OR x.last_automatic_at<=?))))
        AND (?=0 OR NOT EXISTS(SELECT 1 FROM companion_requests WHERE challenge_id=? AND cycle=? AND trigger IN ('change','pause','guided_entry')))
        AND (?!='guided_entry' OR NOT EXISTS(SELECT 1 FROM companion_requests WHERE challenge_id=? AND cycle=? AND trigger='guided_entry')) RETURNING *`,
      ).bind(
        command,
        account,
        challengeId,
        JSON.stringify({
          settings: await settingsFor(env, account),
          action,
          context: snapshot,
        }),
        now,
        now,
        challengeId,
        account,
        action.revision,
        capture.contextRevision,
        capture.modeEpoch,
        action.mode,
        automatic ? 1 : 0,
        new Date(Date.now() - 45000).toISOString(),
        automatic ? 1 : 0,
        challengeId,
        capture.cycle,
        capture.trigger,
        challengeId,
        capture.cycle,
      ),
      env.DB.prepare(
        "INSERT INTO companion_requests(id,challenge_id,trigger,cycle,snapshot) SELECT ?,?,?,?,? WHERE EXISTS(SELECT 1 FROM jobs WHERE id=?)",
      ).bind(
        command,
        challengeId,
        capture.trigger,
        capture.cycle,
        JSON.stringify(capture),
        command,
      ),
      env.DB.prepare(
        "UPDATE companion_context SET automatic_count=automatic_count+1,last_automatic_at=? WHERE challenge_id=? AND ?=1 AND EXISTS(SELECT 1 FROM companion_requests WHERE id=?)",
      ).bind(now, challengeId, automatic ? 1 : 0, command),
    ]);
    inserted = (rows[0].results[0] as unknown as Job) ?? null;
  } else {
    inserted = await env.DB.prepare(
      "INSERT OR IGNORE INTO jobs(id,account_id,challenge_id,kind,input,created_at,updated_at) SELECT ?,?,?,'help',?,?,? WHERE EXISTS(SELECT 1 FROM challenges c JOIN sessions s ON s.challenge_id=c.id WHERE c.id=? AND c.account_id=? AND c.lifecycle IN ('ready','in_progress') AND s.revision=?) RETURNING *",
    )
      .bind(
        command,
        account,
        challengeId,
        JSON.stringify({
          settings: await settingsFor(env, account),
          action,
          context: snapshot,
        }),
        now,
        now,
        challengeId,
        account,
        action.revision,
      )
      .first<Job>();
  }
  if (!inserted)
    throw new Fault(
      "help_conflict",
      409,
      "Help is already running, or your answer changed. Refresh and try again.",
    );
  await dispatch(env, command);
  return inserted;
}

export async function adopt(
  env: Env,
  account: string,
  challengeId: string,
  command: string,
  body: unknown,
) {
  const input = adoptionSchema.parse(body);
  await ownedChallenge(env, account, challengeId);
  const replay = await env.DB.prepare("SELECT * FROM draft_events WHERE id=?")
    .bind(command)
    .first<{
      challenge_id: string;
      source_id: string;
      operation: string;
      revision: number;
    }>();
  if (replay) {
    if (
      replay.challenge_id !== challengeId ||
      replay.source_id !== input.sourceId ||
      replay.operation !== input.operation ||
      replay.revision !== input.revision + 1
    )
      throw new Fault(
        "command_conflict",
        409,
        "This command was already used.",
      );
    return detail(env, account, challengeId);
  }
  let suggestion: string;
  if (input.operation === "undo") {
    const event = await env.DB.prepare(
      "SELECT previous_answer,revision FROM draft_events WHERE id=? AND challenge_id=? AND operation!='undo'",
    )
      .bind(input.sourceId, challengeId)
      .first<{ previous_answer: string; revision: number }>();
    if (!event || event.revision !== input.revision)
      throw new Fault(
        "revision_conflict",
        409,
        "Your answer changed after that insertion. Your current draft is safe.",
      );
    suggestion = event.previous_answer;
  } else {
    const source = await env.DB.prepare(
      "SELECT h.data,json_extract(j.input,'$.action.kind') AS kind FROM help_results h JOIN jobs j ON j.id=h.id WHERE j.id=? AND j.account_id=? AND j.challenge_id=? AND j.status='completed'",
    )
      .bind(input.sourceId, account, challengeId)
      .first<{ data: string; kind: string }>();
    const output = source ? JSON.parse(source.data) : null;
    suggestion =
      source && ["outline", "example", "starting_point"].includes(source.kind)
        ? output.body
        : output?.suggestedAnswer;
    if (typeof suggestion !== "string" || !suggestion.trim())
      throw new Fault(
        "invalid_source",
        400,
        "This help has no draft to insert.",
      );
  }
  const session = await env.DB.prepare(
    "SELECT answer,revision FROM sessions WHERE challenge_id=?",
  )
    .bind(challengeId)
    .first<{ answer: string; revision: number }>();
  if (!session || session.revision !== input.revision)
    throw new Fault(
      "revision_conflict",
      409,
      "Your answer changed. Review the latest draft before inserting.",
    );
  const answer =
    input.operation === "append"
      ? [session.answer, suggestion].filter(Boolean).join("\n\n")
      : suggestion;
  if (answer.length > 24000)
    throw new Fault(
      "answer_too_long",
      400,
      "This would exceed the answer limit.",
    );
  const now = timestamp();
  const writes = await env.DB.batch([
    env.DB.prepare(
      "INSERT INTO draft_events(id,challenge_id,source_id,operation,previous_answer,applied_answer,revision,created_at) SELECT ?,?,?,?,?,?,revision+1,? FROM sessions WHERE challenge_id=? AND revision=? AND EXISTS(SELECT 1 FROM challenges WHERE id=? AND account_id=? AND lifecycle IN ('ready','in_progress')) RETURNING id",
    ).bind(
      command,
      challengeId,
      input.sourceId,
      input.operation,
      session.answer,
      answer,
      now,
      challengeId,
      input.revision,
      challengeId,
      account,
    ),
    env.DB.prepare(
      "UPDATE sessions SET answer=?,revision=revision+1,command_id=?,updated_at=? WHERE challenge_id=? AND revision=? AND EXISTS(SELECT 1 FROM draft_events WHERE id=?)",
    ).bind(answer, command, now, challengeId, input.revision, command),
    env.DB.prepare(
      "UPDATE challenges SET lifecycle='in_progress' WHERE id=? AND lifecycle='ready' AND EXISTS(SELECT 1 FROM draft_events WHERE id=?)",
    ).bind(challengeId, command),
  ]);
  if (!writes[0].results.length)
    throw new Fault(
      "revision_conflict",
      409,
      "Your answer changed. Nothing was inserted.",
    );
  return detail(env, account, challengeId);
}
