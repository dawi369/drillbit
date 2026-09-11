import { z } from "zod";
import { historicalSnapshot } from "./history";
import { INTERVIEW_PROMPT_VERSION } from "./prompts/interviewer";
import { Fault, timestamp } from "./domain";
import { consumeUsage, type Env } from "./platform";
import { ownedChallenge, settingsFor, dispatch, type Job } from "./store";

export const interviewStyleSchema = z.enum(["quick", "standard", "in_depth"]);
export const interviewInputSchema = z.object({
  kind: z.enum(["answer", "clarification", "hint", "example", "continue"]),
  promptId: z.string().min(1).max(100).default("original"),
  revision: z.number().int().nonnegative(),
  saveDraft: z.boolean().optional().describe("For answers, atomically submit current text against revision without a preceding draft upload."),
  text: z.string().trim().max(20000).default(""),
  style: interviewStyleSchema.describe("Legacy styles remain accepted; new turns currently use Standard only.").optional(),
});
export const interviewResultSchema = z.object({
  outcome: z.enum(["follow_up", "reply", "wrap_up"]),
  text: z.string().trim().min(1).max(2400),
});
export function interviewSchemaFor(kind: string) {
  return interviewResultSchema.extend({ outcome: ["answer", "continue"].includes(kind) ? z.literal("follow_up") : z.literal("reply") });
}
export function interviewWrapUp(_context: unknown, _kind: string) { return null; }
export function normalizeInterviewResult(output: z.infer<typeof interviewResultSchema>) { return output; }
export async function interviewFor(env: Env, account: string, id: string) {
  const challenge = await ownedChallenge(env, account, id);
  const data = JSON.parse(challenge.data);
  const rows = await env.DB.prepare(`SELECT t.*,j.status,j.error,s.text AS partial FROM interview_turns t JOIN jobs j ON j.id=t.job_id LEFT JOIN interview_streams s ON s.job_id=j.id WHERE t.challenge_id=? ORDER BY t.ordinal`).bind(id).all<any>();
  const turns = rows.results.map(t => ({ id: t.id, ordinal: t.ordinal, kind: t.kind, prompt: t.prompt, text: t.text, createdAt: t.created_at, jobId: t.job_id, status: t.status, error: t.error, partial: t.partial, result: t.result ? JSON.parse(t.result) : null }));
  const last = turns.filter(t => ["answer", "continue"].includes(t.kind) && t.result).at(-1);
  return { style: interviewStyleSchema.catch("standard").parse(data.interviewStyle),
    prompt: last?.result?.outcome === "follow_up" ? last.result.text : last?.prompt ?? data.prompt,
    wrapUp: last?.result?.outcome === "wrap_up", turns };
}
export async function requestInterview(env: Env, account: string, id: string, command: string, raw: unknown) {
  const input = interviewInputSchema.parse(raw);
  const challenge = await ownedChallenge(env, account, id);
  const replay = await env.DB.prepare("SELECT * FROM jobs WHERE id=?").bind(command).first<Job>();
  if (replay) {
    if (replay.account_id !== account || replay.challenge_id !== id || replay.kind !== "interview" || JSON.stringify(JSON.parse(replay.input).action) !== JSON.stringify(input)) throw new Fault("command_reused", 409, "This command belongs to another request.");
    await dispatch(env, command);
    return interviewFor(env, account, id);
  }
  if (challenge.lifecycle !== "in_progress") throw new Fault("inactive", 409, "Start the interview before sharing.");
  const context = await interviewFor(env, account, id);
  const promptId = context.turns.filter(t => ["answer","continue"].includes(t.kind) && t.result).at(-1)?.id ?? "original";
  if (input.promptId !== promptId) throw new Fault("revision_conflict",409,"The interviewer has moved on. Review the current question first.");
  if (context.turns.some(t => ["pending", "running", "failed"].includes(t.status))) throw new Fault("interview_pending", 409, "Recover the interviewer's response before continuing.");
  if (context.turns.length >= 40) throw new Fault("interview_limit", 429, "This interview has reached its limit. Finish to review your work.");
  if (input.kind === "answer" && !input.text) throw new Fault("empty_answer", 400, "Write an answer before sharing.");
  if (input.kind === "clarification" && !input.text) throw new Fault("empty_question", 400, "What would you like to ask?");
  if (input.kind === "continue" && !context.wrapUp) throw new Fault("not_wrapping_up", 409, "Answer the current question first.");
  const session = await env.DB.prepare("SELECT answer,revision FROM sessions WHERE challenge_id=?").bind(id).first<{answer:string; revision:number}>();
  if (!session || session.revision !== input.revision || (input.kind === "answer" && !input.saveDraft && session.answer.trim() !== input.text)) throw new Fault("revision_conflict", 409, "Sync your current answer before sharing.");
  await consumeUsage(env, account, "interview", 50);
  const now = timestamp();
  context.style = "standard";
  const [settings, history] = await Promise.all([settingsFor(env, account), historicalSnapshot(env, account, id)]);
  const payload = JSON.stringify({ settings, action: input, turnId: command, context: { promptVersion: INTERVIEW_PROMPT_VERSION, historicalSnapshot: history, question: { ...JSON.parse(challenge.data), interviewStyle: context.style }, interview: context } });
  await env.DB.batch([
    env.DB.prepare(`INSERT OR IGNORE INTO jobs(id,account_id,challenge_id,kind,input,created_at,updated_at) SELECT ?,?,?,'interview',?,?,? WHERE EXISTS(SELECT 1 FROM sessions s JOIN challenges c ON c.id=s.challenge_id WHERE c.id=? AND c.account_id=? AND c.lifecycle='in_progress' AND s.revision=?) AND NOT EXISTS(SELECT 1 FROM jobs WHERE account_id=? AND kind='interview' AND status IN ('pending','running'))`).bind(command,account,id,payload,now,now,id,account,input.revision,account),
    env.DB.prepare(`INSERT INTO interview_turns(id,challenge_id,ordinal,kind,prompt,text,job_id,created_at) SELECT ?,?,COALESCE((SELECT MAX(ordinal)+1 FROM interview_turns WHERE challenge_id=?),0),?,?,?,?,? WHERE EXISTS(SELECT 1 FROM jobs WHERE id=?)`).bind(command,id,id,input.kind,context.prompt,input.text,command,now,command),
    env.DB.prepare(`UPDATE challenges SET data=json_set(data,'$.interviewStyle',?) WHERE id=? AND account_id=? AND EXISTS(SELECT 1 FROM interview_turns WHERE id=?)`).bind(context.style,id,account,command),
    env.DB.prepare(`UPDATE sessions SET answer=CASE WHEN ?='answer' THEN '' ELSE answer END,revision=revision+1,command_id=?,updated_at=? WHERE challenge_id=? AND revision=? AND EXISTS(SELECT 1 FROM interview_turns WHERE id=?)`).bind(input.kind,command,now,id,input.revision,command),
  ]);
  if (!(await env.DB.prepare("SELECT id FROM interview_turns WHERE id=?").bind(command).first())) throw new Fault("revision_conflict",409,"The interview changed. Refresh before continuing.");
  await dispatch(env, command);
  return interviewFor(env, account, id);
}
export async function retryInterview(env: Env, account: string, id: string, turn: string, command: string) {
  const c = await ownedChallenge(env, account, id);
  if (c.lifecycle !== "in_progress") throw new Fault("inactive",409,"This interview is finished.");
  const reused = await env.DB.prepare("SELECT * FROM jobs WHERE id=?").bind(command).first<Job>();
  if (reused && (reused.account_id !== account || reused.challenge_id !== id || reused.kind !== "interview" || JSON.parse(reused.input).turnId !== turn)) throw new Fault("command_reused",409,"This command belongs to another request.");
  const row = await env.DB.prepare("SELECT j.* FROM interview_turns t JOIN jobs j ON j.id=t.job_id WHERE t.id=? AND t.challenge_id=?").bind(turn,id).first<Job>();
  if (!row) throw new Fault("not_found",404,"Response not found.");
  if (row.id === command) return interviewFor(env,account,id);
  if (row.status !== "failed") throw new Fault("not_failed",409,"This response is not waiting for a retry.");
  await consumeUsage(env,account,"interview",50);
  const now = timestamp();
  await env.DB.batch([
    env.DB.prepare(`INSERT OR IGNORE INTO jobs(id,account_id,challenge_id,kind,input,created_at,updated_at) SELECT ?,account_id,challenge_id,'interview',input,?,? FROM jobs WHERE id=? AND status='failed' AND EXISTS(SELECT 1 FROM interview_turns WHERE id=? AND job_id=?) AND EXISTS(SELECT 1 FROM challenges WHERE id=? AND lifecycle='in_progress') AND NOT EXISTS(SELECT 1 FROM jobs WHERE account_id=? AND kind='interview' AND status IN ('pending','running'))`).bind(command,now,now,row.id,turn,row.id,id,account),
    env.DB.prepare("UPDATE interview_turns SET job_id=? WHERE id=? AND challenge_id=? AND job_id=? AND EXISTS(SELECT 1 FROM jobs WHERE id=? AND account_id=? AND challenge_id=? AND json_extract(input,'$.turnId')=?)").bind(command,turn,id,row.id,command,account,id,turn),
  ]);
  await dispatch(env,command);
  return interviewFor(env,account,id);
}

export async function interviewStreamSnapshot(env: Env, account: string, id: string, turn: string) {
  const row = await env.DB.prepare("SELECT j.status, s.text, t.result FROM interview_turns t JOIN challenges c ON c.id=t.challenge_id JOIN jobs j ON j.id=t.job_id LEFT JOIN interview_streams s ON s.job_id=j.id WHERE t.id=? AND t.challenge_id=? AND c.account_id=?").bind(turn,id,account).first<{status:string;text:string|null;result:string|null}>();
  if (!row) throw new Fault("not_found",404,"Interview turn not found.");
  return { status: row.status, text: row.result ? JSON.parse(row.result).text : row.text ?? "" };
}
