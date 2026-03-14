import { getDatabase } from "@/lib/storage/database";
import {
  fromChallengeRow,
  fromChallengeSessionRow,
  fromChallengeSummaryRow,
  fromSettingsRow,
  toChallengeRow,
  toChallengeSessionRow,
  toChallengeSummaryRow,
  toSettingsRow,
} from "@/lib/storage/mappers";
import type {
  BlockedChallengeRecord,
  ChallengeCadenceHours,
  ChallengeRecord,
  ChallengeSessionRecord,
  ChallengeSummaryRecord,
  UserSettingsRecord,
} from "@/lib/storage/types";
import {
  isValidChallengeCadenceHours,
  isValidFirstChallengeTimeMinutes,
} from "@/lib/storage/types";
import type { ChallengeLifecycle, ChallengeMode } from "@/lib/widgets/types";

type ChallengeQueryOptions = {
  lifecycle?: ChallengeLifecycle;
  limit?: number;
};

function createNowIso() {
  return new Date().toISOString();
}

function createBlockedChallengeSummary(record: ChallengeRecord) {
  const difficulty = record.difficulty ? `${record.difficulty} ` : "";
  const modeClause = record.mode ? ` intended for ${record.mode} mode` : "";

  return `Do not repeat a ${difficulty}${record.topic} challenge about ${record.title.toLowerCase()} where the user must ${record.teaser.charAt(0).toLowerCase()}${record.teaser.slice(1)}${modeClause}.`.replace(
    /\s+/g,
    " ",
  );
}

async function upsertBlockedChallenge(record: BlockedChallengeRecord) {
  const db = await getDatabase();

  await db.runAsync(
    `
      INSERT INTO blocked_challenges (challenge_id, summary, blocked_at, source_lifecycle)
      VALUES (?, ?, ?, ?)
      ON CONFLICT(challenge_id) DO UPDATE SET
        summary = excluded.summary,
        blocked_at = excluded.blocked_at,
        source_lifecycle = excluded.source_lifecycle
    `,
    record.challengeId,
    record.summary,
    record.blockedAt,
    record.sourceLifecycle,
  );
}

export async function upsertChallenge(record: ChallengeRecord) {
  const db = await getDatabase();
  const row = toChallengeRow(record);

  await db.runAsync(
    `
      INSERT INTO challenges (
        id, title, teaser, topic, difficulty, lifecycle, mode, skip_reason,
        created_at, started_at, completed_at, skipped_at, expires_at, source_model, source_prompt_version
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        title = excluded.title,
        teaser = excluded.teaser,
        topic = excluded.topic,
        difficulty = excluded.difficulty,
        lifecycle = excluded.lifecycle,
        mode = excluded.mode,
        skip_reason = excluded.skip_reason,
        created_at = excluded.created_at,
        started_at = excluded.started_at,
        completed_at = excluded.completed_at,
        skipped_at = excluded.skipped_at,
        expires_at = excluded.expires_at,
        source_model = excluded.source_model,
        source_prompt_version = excluded.source_prompt_version
    `,
    row.id,
    row.title,
    row.teaser,
    row.topic,
    row.difficulty,
    row.lifecycle,
    row.mode,
    row.skip_reason,
    row.created_at,
    row.started_at,
    row.completed_at,
    row.skipped_at,
    row.expires_at,
    row.source_model,
    row.source_prompt_version,
  );

  if (record.lifecycle === "completed" || record.lifecycle === "skipped") {
    await upsertBlockedChallenge({
      challengeId: record.id,
      summary: createBlockedChallengeSummary(record),
      blockedAt: record.completedAt ?? record.skippedAt ?? record.createdAt,
      sourceLifecycle: record.lifecycle,
    });
  }

  return record;
}

export async function getChallengeById(id: string) {
  const db = await getDatabase();
  const rows = await db.getAllAsync<ReturnType<typeof toChallengeRow>>(
    "SELECT * FROM challenges WHERE id = ? LIMIT 1",
    id,
  );

  return rows[0] ? fromChallengeRow(rows[0]) : null;
}

export async function listChallenges(options: ChallengeQueryOptions = {}) {
  const db = await getDatabase();
  const limit = options.limit ?? 50;

  const rows = options.lifecycle
    ? await db.getAllAsync<ReturnType<typeof toChallengeRow>>(
        "SELECT * FROM challenges WHERE lifecycle = ? ORDER BY created_at DESC LIMIT ?",
        options.lifecycle,
        limit,
      )
    : await db.getAllAsync<ReturnType<typeof toChallengeRow>>(
        "SELECT * FROM challenges ORDER BY created_at DESC LIMIT ?",
        limit,
      );

  return rows.map(fromChallengeRow);
}

export async function listBlockedChallenges(limit: number = 365) {
  const db = await getDatabase();
  const rows = await db.getAllAsync<{
    challenge_id: string;
    summary: string;
    blocked_at: string;
    source_lifecycle: "completed" | "skipped";
  }>(
    `
      SELECT challenge_id, summary, blocked_at, source_lifecycle
      FROM blocked_challenges
      ORDER BY blocked_at DESC
      LIMIT ?
    `,
    limit,
  );

  return rows.map((row) => ({
    challengeId: row.challenge_id,
    summary: row.summary,
    blockedAt: row.blocked_at,
    sourceLifecycle: row.source_lifecycle,
  }));
}

export async function getMostRecentResolvedChallenge() {
  const db = await getDatabase();
  const rows = await db.getAllAsync<ReturnType<typeof toChallengeRow>>(
    `
      SELECT *
      FROM challenges
      WHERE lifecycle IN ('completed', 'skipped')
      ORDER BY COALESCE(completed_at, skipped_at, created_at) DESC
      LIMIT 1
    `,
  );

  return rows[0] ? fromChallengeRow(rows[0]) : null;
}

export async function pruneExpiredUnstartedChallenges(nowIso: string = createNowIso()) {
  const db = await getDatabase();

  const result = await db.runAsync(
    `
      DELETE FROM challenges
      WHERE lifecycle = 'ready'
        AND started_at IS NULL
        AND expires_at IS NOT NULL
        AND expires_at <= ?
    `,
    nowIso,
  );

  return result.changes;
}

export async function pruneSkippedChallenges(retentionDays: number = 30, now: Date = new Date()) {
  const db = await getDatabase();
  const cutoff = new Date(now);

  cutoff.setDate(cutoff.getDate() - retentionDays);

  const result = await db.runAsync(
    `
      DELETE FROM challenges
      WHERE lifecycle = 'skipped'
        AND skipped_at IS NOT NULL
        AND skipped_at <= ?
    `,
    cutoff.toISOString(),
  );

  return result.changes;
}

export async function upsertChallengeSummary(record: ChallengeSummaryRecord) {
  const db = await getDatabase();
  const row = toChallengeSummaryRow(record);

  await db.runAsync(
    `
      INSERT INTO challenge_summaries (
        id, challenge_id, short_summary, short_feedback, strengths_json,
        weaknesses_json, tags_json, completion_score, generated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        challenge_id = excluded.challenge_id,
        short_summary = excluded.short_summary,
        short_feedback = excluded.short_feedback,
        strengths_json = excluded.strengths_json,
        weaknesses_json = excluded.weaknesses_json,
        tags_json = excluded.tags_json,
        completion_score = excluded.completion_score,
        generated_at = excluded.generated_at
    `,
    row.id,
    row.challenge_id,
    row.short_summary,
    row.short_feedback,
    row.strengths_json,
    row.weaknesses_json,
    row.tags_json,
    row.completion_score,
    row.generated_at,
  );

  return record;
}

export async function listChallengeSummaries(limit: number = 20) {
  const db = await getDatabase();
  const rows = await db.getAllAsync<ReturnType<typeof toChallengeSummaryRow>>(
    "SELECT * FROM challenge_summaries ORDER BY generated_at DESC LIMIT ?",
    limit,
  );

  return rows.map(fromChallengeSummaryRow);
}

export async function listSummariesByTopic(topic: string, limit: number = 10) {
  const db = await getDatabase();
  const rows = await db.getAllAsync<ReturnType<typeof toChallengeSummaryRow>>(
    `
      SELECT s.*
      FROM challenge_summaries s
      INNER JOIN challenges c ON c.id = s.challenge_id
      WHERE c.topic = ?
      ORDER BY s.generated_at DESC
      LIMIT ?
    `,
    topic,
    limit,
  );

  return rows.map(fromChallengeSummaryRow);
}

export async function upsertChallengeSession(record: ChallengeSessionRecord) {
  const db = await getDatabase();
  const row = toChallengeSessionRow(record);

  await db.runAsync(
    `
      INSERT INTO challenge_sessions (
        challenge_id, selected_mode, notes_draft, conversation_summary, updated_at
      ) VALUES (?, ?, ?, ?, ?)
      ON CONFLICT(challenge_id) DO UPDATE SET
        selected_mode = excluded.selected_mode,
        notes_draft = excluded.notes_draft,
        conversation_summary = excluded.conversation_summary,
        updated_at = excluded.updated_at
    `,
    row.challenge_id,
    row.selected_mode,
    row.notes_draft,
    row.conversation_summary,
    row.updated_at,
  );

  return record;
}

export async function getChallengeSession(challengeId: string) {
  const db = await getDatabase();
  const rows = await db.getAllAsync<ReturnType<typeof toChallengeSessionRow>>(
    "SELECT * FROM challenge_sessions WHERE challenge_id = ? LIMIT 1",
    challengeId,
  );

  return rows[0] ? fromChallengeSessionRow(rows[0]) : null;
}

export async function upsertSettings(record: UserSettingsRecord) {
  const db = await getDatabase();
  const row = toSettingsRow(record);

  await db.runAsync(
    `
      INSERT INTO settings (
        id, focus_prompt, preferred_difficulty, preferred_mode, default_model,
        challenge_cadence_hours, first_challenge_time_minutes, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        focus_prompt = excluded.focus_prompt,
        preferred_difficulty = excluded.preferred_difficulty,
        preferred_mode = excluded.preferred_mode,
        default_model = excluded.default_model,
        challenge_cadence_hours = excluded.challenge_cadence_hours,
        first_challenge_time_minutes = excluded.first_challenge_time_minutes,
        updated_at = excluded.updated_at
    `,
    row.id,
    row.focus_prompt,
    row.preferred_difficulty,
    row.preferred_mode,
    row.default_model,
    row.challenge_cadence_hours,
    row.first_challenge_time_minutes,
    row.updated_at,
  );

  return record;
}

export async function getSettings() {
  const db = await getDatabase();
  const rows = await db.getAllAsync<ReturnType<typeof toSettingsRow>>(
    "SELECT * FROM settings WHERE id = 'default' LIMIT 1",
  );

  return rows[0] ? fromSettingsRow(rows[0]) : null;
}

export function createDefaultSettings(overrides: Partial<UserSettingsRecord> = {}): UserSettingsRecord {
  return {
    id: "default",
    focusPrompt:
      "System design and architecture interview prep with strong trade-off analysis and minimal CRUD-style prompts.",
    preferredDifficulty: "medium",
    preferredMode: "coach",
    defaultModel: process.env.DEFAULT_MODEL,
    challengeCadenceHours: 24,
    firstChallengeTimeMinutes: 9 * 60,
    updatedAt: createNowIso(),
    ...overrides,
  };
}

export function normalizeChallengeCadenceHours(value: number): ChallengeCadenceHours {
  if (!isValidChallengeCadenceHours(value)) {
    throw new Error(`Invalid challenge cadence: ${value}. Cadence must divide evenly into 24 hours.`);
  }

  return value;
}

export function normalizeFirstChallengeTimeMinutes(value: number) {
  if (!isValidFirstChallengeTimeMinutes(value)) {
    throw new Error(`Invalid first challenge time: ${value}. Expected minutes from 0 to 1439.`);
  }

  return value;
}

export async function ensureDefaultSettings() {
  const existing = await getSettings();
  if (existing) {
    return existing;
  }

  const defaults = createDefaultSettings();
  await upsertSettings(defaults);
  return defaults;
}

export async function markChallengeInProgress(challengeId: string, mode: ChallengeMode) {
  const challenge = await getChallengeById(challengeId);
  if (!challenge) {
    return null;
  }

  const nextRecord: ChallengeRecord = {
    ...challenge,
    lifecycle: "in_progress",
    mode,
    startedAt: challenge.startedAt ?? createNowIso(),
  };

  await upsertChallenge(nextRecord);
  return nextRecord;
}
