import { contextFor, receiptStatements } from "./companion";
import { receiptSchema } from "./companion-contract";
import type { z } from "zod";
import {
  Fault,
  settingsSchema,
  normalizeSettings,
  timestamp,
  uuid,
  nextDaily,
  parseJSON,
  type Settings,
} from "./domain";
import type { Env } from "./platform";
export type Account = { id: string; subject: string; status: string };
export type ChallengeRow = {
  id: string;
  account_id: string;
  lifecycle: string;
  data: string;
  created_at: string;
  available_at: string;
  completed_at: string | null;
  command_id: string | null;
};
export type Job = {
  id: string;
  account_id: string;
  challenge_id: string | null;
  kind: string;
  status: string;
  input: string;
  error: string | null;
};
export async function accountFor(env: Env, subject: string): Promise<Account> {
  const id = uuid(),
    now = timestamp();
  await env.DB.prepare(
    "INSERT INTO accounts(id,subject,last_seen,created_at) VALUES(?,?,?,?) ON CONFLICT(subject) DO UPDATE SET last_seen=excluded.last_seen",
  )
    .bind(id, subject, now, now)
    .run();
  const account = await env.DB.prepare(
    "SELECT id,subject,status FROM accounts WHERE subject=?",
  )
    .bind(subject)
    .first<Account>();
  if (!account || account.status === "deleting")
    throw new Fault(
      "account_unavailable",
      403,
      "This account is being deleted.",
    );
  const defaults = settingsSchema.parse({});
  await env.DB.prepare(
    "INSERT OR IGNORE INTO settings(account_id,data,next_due) VALUES(?,?,?)",
  )
    .bind(account.id, JSON.stringify(defaults), nextDaily(defaults))
    .run();
  return account;
}
export async function settingsFor(env: Env, id: string) {
  const row = await env.DB.prepare(
    "SELECT data FROM settings WHERE account_id=?",
  )
    .bind(id)
    .first<{ data: string }>();
  return normalizeSettings(row ? parseJSON(row.data) : {});
}
export async function ownedChallenge(env: Env, account: string, id: string) {
  const row = await env.DB.prepare(
    "SELECT * FROM challenges WHERE id=? AND account_id=?",
  )
    .bind(id, account)
    .first<ChallengeRow>();
  if (!row)
    throw new Fault("not_found", 404, "This session is no longer available.");
  return row;
}
export async function activeChallenge(env: Env, account: string) {
  return env.DB.prepare(
    "SELECT * FROM challenges WHERE account_id=? AND lifecycle IN ('ready','in_progress') LIMIT 1",
  )
    .bind(account)
    .first<ChallengeRow>();
}
export async function detail(env: Env, account: string, id: string) {
  const row = await ownedChallenge(env, account, id);
  const [session, turns, reflection, example, coachRequest, help, adoptions] =
    await Promise.all([
      env.DB.prepare(
        "SELECT answer,revision,updated_at FROM sessions WHERE challenge_id=?",
      )
        .bind(id)
        .first(),
      env.DB.prepare(
        "SELECT id,role,text,state,answer_revision,created_at FROM turns WHERE challenge_id=? ORDER BY created_at,id",
      )
        .bind(id)
        .all(),
      env.DB.prepare("SELECT data FROM reflections WHERE challenge_id=?")
        .bind(id)
        .first<{ data: string }>(),
      env.DB.prepare("SELECT data FROM examples WHERE challenge_id=?")
        .bind(id)
        .first<{ data: string }>(),
      env.DB.prepare(
        "SELECT id,status FROM requests WHERE challenge_id=? ORDER BY created_at DESC LIMIT 1",
      )
        .bind(id)
        .first(),
      env.DB.prepare(
        "SELECT j.id,j.status,json_extract(j.input,'$.action.kind') AS kind,json_extract(j.input,'$.action.revision') AS revision,json_extract(j.input,'$.action.capture') AS capture,(SELECT json_group_array(disposition) FROM companion_receipts r WHERE r.help_id=j.id) AS deliveries,h.data FROM jobs j LEFT JOIN help_results h ON h.id=j.id WHERE j.challenge_id=? AND j.kind='help' ORDER BY j.created_at,j.id",
      )
        .bind(id)
        .all(),
      env.DB.prepare(
        "SELECT id,source_id,operation,revision FROM draft_events WHERE challenge_id=? ORDER BY created_at,id",
      )
        .bind(id)
        .all(),
    ]);
  return {
    ...present(row),
    companion: await contextFor(env, account, id),
    automaticCompanion: env.COMPANION_AUTO_ENABLED === "true",
    help: help.results.map((h: any) => ({
      id: h.id,
      status: h.status,
      kind: h.kind,
      revision: h.revision,
      capture: h.capture ? JSON.parse(h.capture) : null,
      deliveries: JSON.parse(h.deliveries ?? "[]"),
      ...(h.data ? JSON.parse(h.data) : {}),
    })),
    adoptions: adoptions.results,

    coachRequest,
    session,
    turns: turns.results,
    reflection: reflection ? parseJSON(reflection.data) : null,
    example: example ? parseJSON(example.data) : null,
  };
}
export function present(row: ChallengeRow) {
  const { evaluationCriteria, ambiguityPolicy, targetSkill, ...content } =
    parseJSON<Record<string, unknown>>(row.data);
  return {
    id: row.id,
    lifecycle: row.lifecycle,
    ...content,
    createdAt: row.created_at,
    completedAt: row.completed_at,
  };
}
export async function createJob(
  env: Env,
  account: string,
  id: string,
  kind: string,
  challengeId: string | null,
  input: unknown,
) {
  const existing = await env.DB.prepare("SELECT * FROM jobs WHERE id=?")
    .bind(id)
    .first<Job>();
  if (existing) {
    if (
      existing.account_id !== account ||
      existing.kind !== kind ||
      existing.challenge_id !== challengeId
    )
      throw new Fault(
        "command_conflict",
        409,
        "This command was used for another operation.",
      );
    return existing;
  }
  const now = timestamp();
  await env.DB.prepare(
    "INSERT OR IGNORE INTO jobs(id,account_id,challenge_id,kind,input,created_at,updated_at) VALUES(?,?,?,?,?,?,?)",
  )
    .bind(id, account, challengeId, kind, JSON.stringify(input), now, now)
    .run();
  if (
    kind === "generate" &&
    !(await env.DB.prepare("SELECT id FROM jobs WHERE id=?").bind(id).first())
  )
    return env.DB.prepare(
      "SELECT * FROM jobs WHERE account_id=? AND kind='generate' AND status IN ('pending','running') LIMIT 1",
    )
      .bind(account)
      .first<Job>();
  await dispatch(env, id);
  return env.DB.prepare("SELECT * FROM jobs WHERE id=?").bind(id).first<Job>();
}
export async function dispatch(env: Env, id: string) {
  try {
    await env.JOBS.create({ id, params: { jobId: id } });
  } catch {
    console.warn(JSON.stringify({ event: "job_dispatch_deferred", jobId: id }));
  }
}
export async function complete(
  env: Env,
  account: string,
  id: string,
  command: string,
  answer: string,
  revision: number,
  settings: Settings,
  receipts: z.infer<typeof receiptSchema>[] = [],
) {
  const challenge = await ownedChallenge(env, account, id);
  if (challenge.lifecycle === "completed" && challenge.command_id === command)
    return;
  if (!answer.trim())
    throw new Fault("empty_answer", 400, "Write an answer before finishing.");
  const now = timestamp();
  await env.DB.batch([
    env.DB.prepare(
      `UPDATE sessions SET answer=?,revision=revision+1,command_id=?,updated_at=? WHERE challenge_id=? AND revision=? AND EXISTS(SELECT 1 FROM challenges WHERE id=? AND account_id=? AND lifecycle IN ('ready','in_progress'))`,
    ).bind(answer, command, now, id, revision, id, account),
    ...receiptStatements(env, id, receipts, command),
    env.DB.prepare(
      `UPDATE challenges SET lifecycle='completed',completed_at=?,command_id=? WHERE id=? AND account_id=? AND lifecycle IN ('ready','in_progress') AND EXISTS(SELECT 1 FROM sessions WHERE challenge_id=? AND command_id=?)`,
    ).bind(now, command, id, account, id, command),
    env.DB.prepare(
      `INSERT OR IGNORE INTO jobs(id,account_id,challenge_id,kind,input,created_at,updated_at) SELECT ?,account_id,id,'summarize',?,?,? FROM challenges WHERE id=? AND command_id=? AND lifecycle='completed'`,
    ).bind(command, JSON.stringify({ settings }), now, now, id, command),
    env.DB.prepare(
      "UPDATE jobs SET status='cancelled',updated_at=? WHERE challenge_id=? AND kind IN ('help','reveal') AND status IN ('pending','running') AND EXISTS(SELECT 1 FROM challenges WHERE id=? AND command_id=? AND lifecycle='completed')",
    ).bind(now, id, id, command),
    env.DB.prepare(
      "UPDATE requests SET status='cancelled',updated_at=? WHERE challenge_id=? AND status='running' AND EXISTS(SELECT 1 FROM challenges WHERE id=? AND command_id=? AND lifecycle='completed')",
    ).bind(now, id, id, command),
    env.DB.prepare(
      `INSERT OR IGNORE INTO completion_context(challenge_id,data)
      SELECT c.id,json_object(
        'question',json(c.data),
        'session',json_object('answer',s.answer,'revision',s.revision),
        'help',json((SELECT json_group_array(json_object('id',j.id,'kind',json_extract(j.input,'$.action.kind'),'status',j.status,'body',json_extract(h.data,'$.body'),'suggestedAnswer',json_extract(h.data,'$.suggestedAnswer'))) FROM jobs j LEFT JOIN help_results h ON h.id=j.id WHERE j.challenge_id=c.id AND j.kind='help')),
        'turns',json((SELECT json_group_array(json_object('role',t.role,'text',t.text)) FROM turns t WHERE t.challenge_id=c.id)),
        'adoptions',json((SELECT json_group_array(json_object('id',d.id,'sourceId',d.source_id,'operation',d.operation,'revision',d.revision)) FROM draft_events d WHERE d.challenge_id=c.id)),
        'deliveryReceipts',json((SELECT json_group_array(json_object('helpId',r.help_id,'disposition',r.disposition)) FROM companion_receipts r WHERE r.challenge_id=c.id)),
        'exampleViewed',EXISTS(SELECT 1 FROM examples e WHERE e.challenge_id=c.id)
      ) FROM challenges c JOIN sessions s ON s.challenge_id=c.id WHERE c.id=? AND c.command_id=? AND c.lifecycle='completed'`,
    ).bind(id, command),
  ]);
  const result = await ownedChallenge(env, account, id);
  if (result.command_id !== command)
    throw new Fault(
      "revision_conflict",
      409,
      "Your answer changed on another device. Both drafts have been preserved.",
    );
  await dispatch(env, command);
}
