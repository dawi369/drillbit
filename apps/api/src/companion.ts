import { z } from "zod";
import { Fault, timestamp } from "./domain";
import { hash, type Env } from "./platform";

import {
  companionUpdateSchema,
  receiptSchema,
  receiptsSchema,
} from "./companion-contract";
type Row = {
  revision: number;
  mode: string;
  mode_epoch: number;
  paused: number;
  selected_focus: string | null;
  decisions: string;
  automatic_count: number;
  last_automatic_at: string | null;
  interaction_cycle: number;
};
export const normalizeAnswer = (answer: string) =>
  answer.trim().replace(/\s+/gu, " ");
export async function contextFor(env: Env, account: string, id: string) {
  const owner = await env.DB.prepare(
    "SELECT id FROM challenges WHERE id=? AND account_id=?",
  )
    .bind(id, account)
    .first();
  if (!owner) throw new Fault("not_found", 404, "Practice not found.");
  await env.DB.prepare(
    "INSERT OR IGNORE INTO companion_context(challenge_id) VALUES(?)",
  )
    .bind(id)
    .run();
  let row = (await env.DB.prepare(
    "SELECT * FROM companion_context WHERE challenge_id=?",
  )
    .bind(id)
    .first<Row>())!;
  const session = await env.DB.prepare(
    "SELECT answer FROM sessions WHERE challenge_id=?",
  )
    .bind(id)
    .first<{ answer: string }>();
  const digest = await hash(normalizeAnswer(session?.answer ?? ""));
  await env.DB.prepare(
    "UPDATE companion_context SET answer_digest=?,interaction_cycle=interaction_cycle+1 WHERE challenge_id=? AND answer_digest!=?",
  )
    .bind(digest, id, digest)
    .run();
  row = (await env.DB.prepare(
    "SELECT * FROM companion_context WHERE challenge_id=?",
  )
    .bind(id)
    .first<Row>())!;
  const decisions = JSON.parse(row.decisions) as { id: string; text: string }[];
  const cycle = await hash(
    JSON.stringify([digest, row.interaction_cycle, decisions.at(-1)?.id ?? ""]),
  );
  const checked = await env.DB.prepare(
    "SELECT trigger FROM companion_requests WHERE challenge_id=? AND cycle=? AND trigger IN ('change','pause','guided_entry')",
  )
    .bind(id, cycle)
    .all<{ trigger: string }>();
  return {
    cycleConsumed: checked.results.length > 0,
    guidedStarted: checked.results.some((r) => r.trigger === "guided_entry"),
    revision: row.revision,
    mode: row.mode,
    modeEpoch: row.mode_epoch,
    paused: !!row.paused,
    selectedFocus: row.selected_focus,
    decisions,
    automaticCount: row.automatic_count,
    lastAutomaticAt: row.last_automatic_at,
    digest,
    cycle,
  };
}
export async function updateContext(
  env: Env,
  account: string,
  id: string,
  command: string,
  raw: unknown,
) {
  const input = companionUpdateSchema.parse(raw),
    current = await contextFor(env, account, id);
  const serialized = JSON.stringify(input);
  const old = await env.DB.prepare(
    "SELECT challenge_id,input FROM companion_commands WHERE id=?",
  )
    .bind(command)
    .first<{ challenge_id: string; input: string }>();
  if (old) {
    if (old.challenge_id !== id || old.input !== serialized)
      throw new Fault(
        "command_conflict",
        409,
        "This command was already used.",
      );
    return contextFor(env, account, id);
  }
  if (input.revision !== current.revision)
    throw new Fault(
      "context_conflict",
      409,
      "Practice context changed. Refresh before continuing.",
    );
  if (
    (input.operation === "mode" && !input.mode) ||
    (input.operation === "pause" && input.paused === undefined) ||
    (["focus", "discussion"].includes(input.operation) && !input.text)
  )
    throw new Fault(
      "invalid_context",
      400,
      "The context change is incomplete.",
    );
  const mode = input.operation === "mode" ? input.mode! : current.mode;
  const decisions =
    input.operation === "discussion"
      ? [...current.decisions, { id: command, text: input.text! }].slice(-12)
      : current.decisions;
  const writes = await env.DB.batch([
    env.DB.prepare(
      "INSERT OR IGNORE INTO companion_commands(id,challenge_id,input) SELECT ?,?,? WHERE EXISTS(SELECT 1 FROM companion_context x JOIN challenges c ON c.id=x.challenge_id WHERE x.challenge_id=? AND x.revision=? AND c.lifecycle IN ('ready','in_progress')) RETURNING id",
    ).bind(command, id, serialized, id, input.revision),
    env.DB.prepare(
      "UPDATE companion_context SET revision=revision+1,mode=?,mode_epoch=mode_epoch+?,paused=?,selected_focus=?,decisions=? WHERE challenge_id=? AND revision=? AND EXISTS(SELECT 1 FROM companion_commands WHERE id=? AND input=?)",
    ).bind(
      mode,
      mode !== current.mode ? 1 : 0,
      input.operation === "pause"
        ? input.paused
          ? 1
          : 0
        : input.operation === "mode"
          ? 0
          : current.paused
            ? 1
            : 0,
      input.operation === "focus" ? input.text! : current.selectedFocus,
      JSON.stringify(decisions),
      id,
      input.revision,
      command,
      serialized,
    ),
  ]);
  if (!writes[0].results.length) {
    const replay = await env.DB.prepare(
      "SELECT challenge_id,input FROM companion_commands WHERE id=?",
    )
      .bind(command)
      .first<{ challenge_id: string; input: string }>();
    if (!replay)
      throw new Fault(
        "context_conflict",
        409,
        "This practice changed or finished.",
      );
    if (replay.challenge_id !== id || replay.input !== serialized)
      throw new Fault(
        "command_conflict",
        409,
        "This command was already used.",
      );
  }
  return contextFor(env, account, id);
}
export function receiptStatements(
  env: Env,
  id: string,
  receipts: z.infer<typeof receiptSchema>[],
  command: string | null = null,
) {
  return receipts.map((r) =>
    env.DB.prepare(
      "INSERT OR IGNORE INTO companion_receipts(id,challenge_id,help_id,disposition,created_at) SELECT ?,?,?,?,? WHERE EXISTS(SELECT 1 FROM challenges WHERE id=? AND lifecycle IN ('ready','in_progress')) AND EXISTS(SELECT 1 FROM jobs WHERE id=? AND challenge_id=? AND kind='help') AND (? IS NULL OR EXISTS(SELECT 1 FROM sessions WHERE challenge_id=? AND command_id=?))",
    ).bind(
      r.id,
      id,
      r.helpId,
      r.disposition,
      timestamp(),
      id,
      r.helpId,
      id,
      command,
      id,
      command,
    ),
  );
}
export async function receive(
  env: Env,
  account: string,
  id: string,
  raw: unknown,
) {
  await contextFor(env, account, id);
  const { receipts } = receiptsSchema.parse(raw);
  // A UUID replay may not silently refer to another receipt.
  for (const r of receipts) {
    const old = await env.DB.prepare(
      "SELECT challenge_id,help_id,disposition FROM companion_receipts WHERE id=?",
    )
      .bind(r.id)
      .first<{ challenge_id: string; help_id: string; disposition: string }>();
    if (
      old &&
      (old.challenge_id !== id ||
        old.help_id !== r.helpId ||
        old.disposition !== r.disposition)
    )
      throw new Fault("command_conflict", 409, "Receipt command conflict.");
  }
  if (receipts.length) await env.DB.batch(receiptStatements(env, id, receipts));
  return { ok: true };
}
