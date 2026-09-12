import { learningEvidence } from "./learning";
import { Fault, timestamp } from "./domain";
import { concepts, eligibilityInput } from "./taxonomy";
import { detail, type ChallengeRow, present } from "./store";
import type { Env } from "./platform";
export type Question = {
  id: string;
  account_id: string;
  data: string;
  created_at: string;
  eligible: number;
  eligibility_revision: number;
  eligibility_updated_at: string;
};
export async function ownedQuestion(env: Env, account: string, id: string) {
  const q = await env.DB.prepare(
    "SELECT * FROM questions WHERE id=? AND account_id=?",
  )
    .bind(id, account)
    .first<Question>();
  if (!q)
    throw new Fault("not_found", 404, "This question is no longer available.");
  return q;
}
export const questionProjection = (q: Question) => {
  const {
    evaluationCriteria,
    ambiguityPolicy,
    targetSkill,
    tagEvidence,
    selectionSnapshot,
    ...data
  } = JSON.parse(q.data);
  return {
    ...data,
    id: q.id,
    createdAt: q.created_at,
    eligible: !!q.eligible,
    eligibilityRevision: q.eligibility_revision,
  };
};
export async function libraryPage(
  env: Env,
  account: string,
  query: URLSearchParams,
) {
  const clauses = ["q.account_id=?"],
    args: unknown[] = [account];
  if (query.get("skipped") === "true")
    clauses.push(
      "q.eligible=0 AND (SELECT c.lifecycle FROM question_attempts x JOIN challenges c ON c.id=x.challenge_id WHERE x.question_id=q.id ORDER BY c.created_at DESC,c.id DESC LIMIT 1)='skipped'",
    );
  else
    clauses.push(
      "EXISTS(SELECT 1 FROM question_attempts x JOIN challenges c ON c.id=x.challenge_id WHERE x.question_id=q.id AND c.lifecycle='completed')",
    );
  const search = (query.get("q") ?? "").trim().toLowerCase().slice(0, 160);
  if (search) {
    clauses.push(
      "(instr(lower(json_extract(q.data,'$.title') || ' ' || json_extract(q.data,'$.prompt') || ' ' || json_extract(q.data,'$.scenario')),?)>0 OR EXISTS(SELECT 1 FROM json_each(json_extract(q.data,'$.conceptIds')) t WHERE instr(?,t.value)>0))",
    );
    args.push(
      search,
      concepts
        .filter((c) =>
          [c.label, ...c.aliases].some((x) => x.toLowerCase().includes(search)),
        )
        .map((c) => c.id)
        .join(","),
    );
  }
  const tags = (query.get("concepts") ?? "").split(",").filter(Boolean);
  if (tags.length) {
    clauses.push(
      `EXISTS(SELECT 1 FROM json_each(json_extract(q.data,'$.conceptIds')) t WHERE t.value IN (${tags.map(() => "?").join(",")}))`,
    );
    args.push(...tags);
  }
  if (query.get("level")) {
    clauses.push("json_extract(q.data,'$.engineeringLevel')=?");
    args.push(query.get("level"));
  }
  if (query.get("since")) {
    clauses.push(
      "EXISTS(SELECT 1 FROM question_attempts x JOIN challenges c ON c.id=x.challenge_id WHERE x.question_id=q.id AND c.completed_at>=?)",
    );
    args.push(query.get("since"));
  }
  let cursor: { at: string; id: string } | undefined;
  if (query.get("cursor"))
    try {
      cursor = JSON.parse(atob(query.get("cursor")!));
      if (typeof cursor?.at !== "string" || typeof cursor?.id !== "string")
        throw Error();
    } catch {
      throw new Fault("invalid_cursor", 400, "Invalid library cursor.");
    }
  const base = `SELECT q.*,COALESCE((SELECT MAX(COALESCE(c.completed_at,c.created_at)) FROM question_attempts x JOIN challenges c ON c.id=x.challenge_id WHERE x.question_id=q.id),q.created_at) activity,(SELECT COUNT(*) FROM question_attempts x JOIN challenges c ON c.id=x.challenge_id WHERE x.question_id=q.id AND c.lifecycle='completed') attemptCount FROM questions q WHERE ${clauses.join(" AND ")}`;
  const rows = await env.DB.prepare(
    `SELECT * FROM (${base}) WHERE (? IS NULL OR activity<? OR (activity=? AND id<?)) ORDER BY activity DESC,id DESC LIMIT 26`,
  )
    .bind(
      ...args,
      cursor?.at ?? null,
      cursor?.at ?? null,
      cursor?.at ?? null,
      cursor?.id ?? null,
    )
    .all<Question & { activity: string; attemptCount: number }>();
  const page = rows.results.slice(0, 25),
    last = page.at(-1);
  return {
    questions: page.map((q) => ({
      ...questionProjection(q),
      lastActivity: q.activity,
      attemptCount: q.attemptCount,
    })),
    nextCursor:
      rows.results.length > 25 && last
        ? btoa(JSON.stringify({ at: last.activity, id: last.id }))
        : null,
  };
}
export async function questionDetail(
  env: Env,
  account: string,
  id: string,
  cursor?: string,
) {
  const q = await ownedQuestion(env, account, id);
  let after = "9999",
    afterID = "~";
  if (cursor)
    try {
      const c = JSON.parse(atob(cursor));
      if (typeof c.at !== "string" || typeof c.id !== "string") throw Error();
      after = c.at;
      afterID = c.id;
    } catch {
      throw new Fault("invalid_cursor", 400, "Invalid attempt cursor.");
    }
  const rows = await env.DB.prepare(
    "SELECT c.* FROM challenges c JOIN question_attempts x ON x.challenge_id=c.id WHERE x.question_id=? AND c.account_id=? AND (c.created_at<? OR (c.created_at=? AND c.id<?)) ORDER BY c.created_at DESC,c.id DESC LIMIT 26",
  )
    .bind(id, account, after, after, afterID)
    .all<ChallengeRow>();
  const page = rows.results.slice(0, 25),
    last = page.at(-1);
  return {
    question: questionProjection(q),
    attempts: page.map(present),
    nextCursor:
      rows.results.length > 25 && last
        ? btoa(JSON.stringify({ at: last.created_at, id: last.id }))
        : null,
  };
}
export async function setEligibility(
  env: Env,
  account: string,
  id: string,
  command: string,
  raw: unknown,
) {
  await ownedQuestion(env, account, id);
  const input = eligibilityInput.parse(raw);
  const old = await env.DB.prepare(
    "SELECT * FROM library_commands WHERE account_id=? AND command=?",
  )
    .bind(account, command)
    .first<{ question_id: string; revision: number; eligible: number }>();
  if (old) {
    if (
      old.question_id !== id ||
      old.revision !== input.revision ||
      !!old.eligible !== input.eligible
    )
      throw new Fault(
        "command_conflict",
        409,
        "This command has already been used.",
      );
    return questionProjection(await ownedQuestion(env, account, id));
  }
  await env.DB.batch([
    env.DB.prepare(
      "INSERT OR IGNORE INTO library_commands(account_id,command,question_id,revision,eligible) SELECT ?,?,?,?,? WHERE EXISTS(SELECT 1 FROM questions WHERE id=? AND account_id=? AND eligibility_revision=? AND NOT EXISTS(SELECT 1 FROM question_attempts x JOIN challenges c ON c.id=x.challenge_id WHERE x.question_id=questions.id AND c.lifecycle IN ('ready','in_progress')))",
    ).bind(
      account,
      command,
      id,
      input.revision,
      +input.eligible,
      id,
      account,
      input.revision,
    ),
    env.DB.prepare(
      "UPDATE questions SET eligible=?,eligibility_revision=eligibility_revision+1,eligibility_command=?,eligibility_updated_at=? WHERE id=? AND account_id=? AND eligibility_revision=? AND EXISTS(SELECT 1 FROM library_commands WHERE account_id=? AND command=? AND question_id=? AND revision=? AND eligible=?)",
    ).bind(
      +input.eligible,
      command,
      timestamp(),
      id,
      account,
      input.revision,
      account,
      command,
      id,
      input.revision,
      +input.eligible,
    ),
  ]);
  const accepted = await env.DB.prepare(
    "SELECT question_id,revision,eligible FROM library_commands WHERE account_id=? AND command=?",
  )
    .bind(account, command)
    .first<{question_id:string;revision:number;eligible:number}>();
  if (!accepted)
    throw new Fault(
      "revision_conflict",
      409,
      "This question changed on another device. Refresh and try again.",
    );
  if(accepted.question_id!==id||accepted.revision!==input.revision||!!accepted.eligible!==input.eligible)throw new Fault("command_conflict",409,"This command has already been used.");
  return questionProjection(await ownedQuestion(env, account, id));
}
export async function startQuestion(
  env: Env,
  account: string,
  id: string,
  command: string,
) {
  const q = await ownedQuestion(env, account, id);
  const existing = await env.DB.prepare(
    "SELECT x.question_id FROM challenges c JOIN question_attempts x ON x.challenge_id=c.id WHERE c.id=? AND c.account_id=?",
  )
    .bind(command, account)
    .first<{ question_id: string }>();
  if (existing) {
    if (existing.question_id !== id)
      throw new Fault(
        "command_conflict",
        409,
        "This command has already been used.",
      );
    return detail(env, account, command);
  }
  const now = timestamp();
  await env.DB.batch([
    env.DB.prepare(
      "INSERT OR IGNORE INTO challenges(id,account_id,lifecycle,data,created_at,available_at) SELECT ?,?,'in_progress',?,?,? WHERE NOT EXISTS(SELECT 1 FROM challenges WHERE account_id=? AND lifecycle IN ('ready','in_progress'))",
    ).bind(command, account, q.data, now, now, account),
    env.DB.prepare(
      "INSERT OR IGNORE INTO question_attempts SELECT ?,? WHERE EXISTS(SELECT 1 FROM challenges WHERE id=? AND account_id=?)",
    ).bind(command, id, command, account),
    env.DB.prepare(
      "INSERT OR IGNORE INTO sessions(challenge_id,updated_at) SELECT id,? FROM challenges WHERE id=? AND account_id=?",
    ).bind(now, command, account),
    env.DB.prepare(
      "UPDATE questions SET eligible=0,eligibility_revision=eligibility_revision+1,eligibility_command=? WHERE id=? AND account_id=? AND COALESCE(eligibility_command,'')!=? AND EXISTS(SELECT 1 FROM question_attempts WHERE challenge_id=? AND question_id=?)",
    ).bind(command,id,account,command,command,id),
  ]);
  if (
    !(await env.DB.prepare(
      "SELECT id FROM challenges WHERE id=? AND account_id=?",
    )
      .bind(command, account)
      .first())
  )
    throw new Fault(
      "active_attempt",
      409,
      "Finish or skip your current question before starting another.",
    );
  const linked = await env.DB.prepare(
    "SELECT question_id FROM question_attempts WHERE challenge_id=?",
  )
    .bind(command)
    .first<{ question_id: string }>();
  if (linked?.question_id !== id)
    throw new Fault(
      "command_conflict",
      409,
      "This command has already been used.",
    );
  return detail(env, account, command);
}
export async function selectConcept(
  env: Env,
  account: string,
  level: string,
  explicit?: string,
) {
  const rows = await env.DB.prepare(
    "SELECT json_extract(q.data,'$.primaryConceptId') id,COUNT(*) count,MAX(c.completed_at) last FROM questions q JOIN question_attempts x ON x.question_id=q.id JOIN challenges c ON c.id=x.challenge_id WHERE q.account_id=? AND c.lifecycle='completed' AND json_extract(q.data,'$.engineeringLevel')=? GROUP BY 1",
  )
    .bind(account, level)
    .all<{ id: string; count: number; last: string }>();
  const recent = await env.DB.prepare(
    "SELECT json_extract(data,'$.primaryConceptId') id FROM questions WHERE account_id=? ORDER BY created_at DESC,id DESC LIMIT 2",
  )
    .bind(account)
    .all<{ id: string }>();
  const candidates = concepts
    .filter((c) => !recent.results.some((r) => r.id === c.id))
    .map((c) => ({ id: c.id, ...rows.results.find((r) => r.id === c.id) }))
    .sort(
      (a, b) =>
        (a.count ?? 0) - (b.count ?? 0) ||
        (a.last ?? "").localeCompare(b.last ?? "") ||
        a.id.localeCompare(b.id),
    );
  const completed = rows.results.reduce((total, row) => total + row.count, 0);
  const evidence = await learningEvidence(env, account, level);
  const recentIDs = new Set(recent.results.map(r => r.id));
  const latest = new Map<string, typeof evidence>();
  for (const item of evidence) {
    const entries = latest.get(item.conceptId);
    if (!entries) latest.set(item.conceptId, [item]);
    else if (entries[0].sessionId === item.sessionId) entries.push(item);
  }
  const gap = [...latest.values()].flat().find(e => e.signal === "needs_practice" && !recentIDs.has(e.conceptId)
    && rows.results.some(r => r.id === e.conceptId));
  const revisit = [...rows.results].filter(r => !recentIDs.has(r.id)
    && Date.now() - Date.parse(r.last) >= 14 * 86400000)
    .sort((a,b) => a.last.localeCompare(b.last) || a.id.localeCompare(b.id))[0];
  const selected = completed % 3 === 1 && gap ? gap.conceptId
    : completed % 3 === 2 && revisit ? revisit.id : candidates[0]!.id;
  return {
    primaryConceptId: explicit ?? selected,
    reason: explicit ? "Your selected practice area."
      : completed % 3 === 1 && gap ? "Revisit an area highlighted in previous feedback."
      : completed % 3 === 2 && revisit ? "Revisit a concept you have not practised recently."
      : "An area with less completed practice at this level.",
    version: 2,
  };
}
export async function coverage(env: Env, account: string) {
  return (
    await env.DB.prepare(
      "SELECT t.value conceptId,COUNT(*) completedAttempts,COUNT(DISTINCT q.id) distinctQuestions,MAX(c.completed_at) lastPractised FROM questions q JOIN question_attempts x ON x.question_id=q.id JOIN challenges c ON c.id=x.challenge_id JOIN json_each(json_extract(q.data,'$.conceptIds')) t WHERE q.account_id=? AND c.lifecycle='completed' GROUP BY t.value",
    )
      .bind(account)
      .all()
  ).results;
}
