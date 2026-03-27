import { getDatabase } from "@/lib/storage/database";
import {
  getDefaultSeedModelId,
  SEEDED_MODELS,
} from "@/constants/models";
import { notifyChallengeRefresh } from "@/lib/challenge-refresh";
import { notifyMemoryRefresh } from "@/lib/memory-refresh";
import { notifyModelsRefresh } from "@/lib/models-refresh";
import { notifySettingsRefresh } from "@/lib/settings-refresh";
import { syncWidgetState } from "@/lib/widgets/sync";
import {
  fromChallengeRow,
  fromChallengeSessionRow,
  fromChallengeSummaryRow,
  fromModelRow,
  fromSettingsRow,
  toChallengeRow,
  toChallengeSessionRow,
  toChallengeSummaryRow,
  toModelRow,
  toSettingsRow,
} from "@/lib/storage/mappers";
import type {
  BlockedChallengeRecord,
  ChallengeCadenceHours,
  ChallengeRecord,
  ChallengeSessionRecord,
  ChallengeSummaryRecord,
  MemoryChallengeSummaryRow,
  MemoryOverview,
  MemoryTopicRollup,
  ModelRecord,
  UserSettingsRecord,
} from "@/lib/storage/types";
import {
  isValidChallengeCadenceHours,
  isValidFirstChallengeTimeMinutes,
} from "@/lib/storage/types";
import { getNextScheduledChallengeDate } from "@/lib/time";
import type { ChallengeDifficulty, ChallengeMode } from "@/lib/widgets/types";

type ModelQueryOptions = {
  includeDisabled?: boolean;
};

function createNowIso() {
  return new Date().toISOString();
}

function createBlockedChallengeSummary(record: ChallengeRecord) {
  const difficulty = record.difficulty ? `${record.difficulty} ` : "";

  return `Do not repeat a ${difficulty}${record.topic} challenge about ${record.title.toLowerCase()} where the user must ${record.teaser.charAt(0).toLowerCase()}${record.teaser.slice(1)}.`.replace(
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
        id, title, teaser, topic, difficulty, lifecycle, skip_reason,
        created_at, started_at, completed_at, skipped_at, expires_at, source_model, source_prompt_version
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        title = excluded.title,
        teaser = excluded.teaser,
        topic = excluded.topic,
        difficulty = excluded.difficulty,
        lifecycle = excluded.lifecycle,
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

  notifyChallengeRefresh();
  void syncWidgetState();

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

export async function getCurrentActiveChallenge(nowIso: string = createNowIso()) {
  await pruneExpiredUnstartedChallenges(nowIso);

  const db = await getDatabase();
  const inProgressRows = await db.getAllAsync<ReturnType<typeof toChallengeRow>>(
    `
      SELECT *
      FROM challenges
      WHERE lifecycle = 'in_progress'
      ORDER BY COALESCE(started_at, created_at) DESC
      LIMIT 1
    `,
  );

  if (inProgressRows[0]) {
    return fromChallengeRow(inProgressRows[0]);
  }

  const readyRows = await db.getAllAsync<ReturnType<typeof toChallengeRow>>(
    `
      SELECT *
      FROM challenges
      WHERE lifecycle = 'ready'
        AND (expires_at IS NULL OR expires_at > ?)
      ORDER BY created_at DESC
      LIMIT 1
    `,
    nowIso,
  );

  return readyRows[0] ? fromChallengeRow(readyRows[0]) : null;
}

export async function pruneExpiredUnstartedChallenges(
  nowIso: string = createNowIso(),
) {
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

export async function clearUnstartedReadyChallenges() {
  const db = await getDatabase();

  await db.runAsync(
    `
      DELETE FROM challenge_sessions
      WHERE challenge_id IN (
        SELECT id
        FROM challenges
        WHERE lifecycle = 'ready'
          AND started_at IS NULL
      )
    `,
  );

  const result = await db.runAsync(
    `
      DELETE FROM challenges
      WHERE lifecycle = 'ready'
        AND started_at IS NULL
    `,
  );

  return result.changes;
}

export function getChallengeExpirationIso(settings: UserSettingsRecord, from: Date = new Date()) {
  const nextScheduledAt = getNextScheduledChallengeDate({
    from,
    firstChallengeTimeMinutes: settings.firstChallengeTimeMinutes ?? 9 * 60,
    challengeCadenceHours: settings.challengeCadenceHours ?? 24,
  });

  return nextScheduledAt.toISOString();
}

export async function pruneSkippedChallenges(
  retentionDays: number = 30,
  now: Date = new Date(),
) {
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

  notifyMemoryRefresh();
  void syncWidgetState();

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

export async function listCompletedChallengesMissingSummary(limit: number = 10) {
  const db = await getDatabase();
  const rows = await db.getAllAsync<ReturnType<typeof toChallengeRow>>(
    `
      SELECT c.*
      FROM challenges c
      LEFT JOIN challenge_summaries s ON s.challenge_id = c.id
      WHERE c.lifecycle = 'completed'
        AND s.challenge_id IS NULL
      ORDER BY COALESCE(c.completed_at, c.created_at) DESC
      LIMIT ?
    `,
    limit,
  );

  return rows.map(fromChallengeRow);
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

function getTopPatternValues(
  summaries: ChallengeSummaryRecord[],
  key: "strengths" | "weaknesses",
  limit: number,
) {
  const counts = new Map<string, number>();

  for (const summary of summaries) {
    for (const value of summary[key]) {
      counts.set(value, (counts.get(value) ?? 0) + 1);
    }
  }

  return [...counts.entries()]
    .sort((left, right) => right[1] - left[1] || left[0].localeCompare(right[0]))
    .slice(0, limit)
    .map(([value]) => value);
}

function getAverageCompletionScore(summaries: ChallengeSummaryRecord[]) {
  const scored = summaries.filter(
    (summary): summary is ChallengeSummaryRecord & { completionScore: number } =>
      typeof summary.completionScore === "number",
  );

  if (scored.length === 0) {
    return undefined;
  }

  const total = scored.reduce((sum, summary) => sum + summary.completionScore, 0);
  return total / scored.length;
}

function normalizeChallengeDifficulty(
  value: string | null | undefined,
): ChallengeDifficulty | undefined {
  if (value === "easy" || value === "medium" || value === "hard") {
    return value;
  }

  return undefined;
}

async function getChallengeSummaryCount() {
  const db = await getDatabase();
  const rows = await db.getAllAsync<{ total: number }>(
    "SELECT COUNT(*) AS total FROM challenge_summaries",
  );

  return rows[0]?.total ?? 0;
}

export async function listMemoryChallengeSummaries(
  limit: number = 12,
): Promise<MemoryChallengeSummaryRow[]> {
  const db = await getDatabase();
  const rows = await db.getAllAsync<{
    id: string;
    challenge_id: string;
    short_summary: string;
    short_feedback: string;
    strengths_json: string;
    weaknesses_json: string;
    tags_json: string;
    completion_score: number | null;
    generated_at: string;
    challenge_title: string;
    challenge_topic: string;
    challenge_difficulty: string | null;
  }>(
    `
      SELECT
        s.id,
        s.challenge_id,
        s.short_summary,
        s.short_feedback,
        s.strengths_json,
        s.weaknesses_json,
        s.tags_json,
        s.completion_score,
        s.generated_at,
        c.title AS challenge_title,
        c.topic AS challenge_topic,
        c.difficulty AS challenge_difficulty
      FROM challenge_summaries s
      INNER JOIN challenges c ON c.id = s.challenge_id
      ORDER BY s.generated_at DESC
      LIMIT ?
    `,
    limit,
  );

  return rows.map((row) => {
    const summary = fromChallengeSummaryRow({
      id: row.id,
      challenge_id: row.challenge_id,
      short_summary: row.short_summary,
      short_feedback: row.short_feedback,
      strengths_json: row.strengths_json,
      weaknesses_json: row.weaknesses_json,
      tags_json: row.tags_json,
      completion_score: row.completion_score,
      generated_at: row.generated_at,
    });

    return {
      ...summary,
      challengeTitle: row.challenge_title,
      challengeTopic: row.challenge_topic,
      challengeDifficulty: normalizeChallengeDifficulty(row.challenge_difficulty),
    };
  });
}

export async function getMemoryOverview(): Promise<MemoryOverview> {
  const memorySummaries = await listMemoryChallengeSummaries(60);
  const totalCompleted = await getChallengeSummaryCount();
  const recentSessions = memorySummaries.slice(0, 10);

  const topicMap = new Map<string, ChallengeSummaryRecord[]>();
  for (const session of memorySummaries) {
    const entries = topicMap.get(session.challengeTopic) ?? [];
    entries.push(session);
    topicMap.set(session.challengeTopic, entries);
  }

  const topicRollups: MemoryTopicRollup[] = [...topicMap.entries()]
    .map(([topic, topicSummaries]) => ({
      topic,
      count: topicSummaries.length,
      averageCompletionScore: getAverageCompletionScore(topicSummaries),
      topStrengths: getTopPatternValues(topicSummaries, "strengths", 2),
      topWeaknesses: getTopPatternValues(topicSummaries, "weaknesses", 2),
    }))
    .sort((left, right) => right.count - left.count || left.topic.localeCompare(right.topic));

  return {
    totalCompleted,
    averageCompletionScore: getAverageCompletionScore(memorySummaries),
    strongestPatterns: getTopPatternValues(memorySummaries, "strengths", 4),
    weakestPatterns: getTopPatternValues(memorySummaries, "weaknesses", 4),
    recentSessions,
    topicRollups,
  };
}

export async function upsertChallengeSession(
  record: ChallengeSessionRecord,
  options?: { broadcast?: boolean },
) {
  const db = await getDatabase();
  const row = toChallengeSessionRow(record);

  await db.runAsync(
    `
      INSERT INTO challenge_sessions (
        challenge_id, selected_mode, notes_draft, assistant_draft, conversation_history_json, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?)
      ON CONFLICT(challenge_id) DO UPDATE SET
        selected_mode = excluded.selected_mode,
        notes_draft = excluded.notes_draft,
        assistant_draft = excluded.assistant_draft,
        conversation_history_json = excluded.conversation_history_json,
        updated_at = excluded.updated_at
    `,
    row.challenge_id,
    row.selected_mode,
    row.notes_draft,
    row.assistant_draft ?? null,
    row.conversation_history_json,
    row.updated_at,
  );

  if (options?.broadcast !== false) {
    notifyChallengeRefresh();
    void syncWidgetState();
  }

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
        id, focus_prompt, preferred_difficulty, preferred_mode, notifications_enabled, selected_model_id,
        challenge_cadence_hours, first_challenge_time_minutes, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        focus_prompt = excluded.focus_prompt,
        preferred_difficulty = excluded.preferred_difficulty,
        preferred_mode = excluded.preferred_mode,
        notifications_enabled = excluded.notifications_enabled,
        selected_model_id = excluded.selected_model_id,
        challenge_cadence_hours = excluded.challenge_cadence_hours,
        first_challenge_time_minutes = excluded.first_challenge_time_minutes,
        updated_at = excluded.updated_at
    `,
    row.id,
    row.focus_prompt,
    row.preferred_difficulty,
    row.preferred_mode,
    row.notifications_enabled,
    row.selected_model_id,
    row.challenge_cadence_hours,
    row.first_challenge_time_minutes,
    row.updated_at,
  );

  notifySettingsRefresh();
  void syncWidgetState();

  return record;
}

export async function getSettings() {
  const db = await getDatabase();
  const rows = await db.getAllAsync<ReturnType<typeof toSettingsRow>>(
    "SELECT * FROM settings WHERE id = 'default' LIMIT 1",
  );

  return rows[0] ? fromSettingsRow(rows[0]) : null;
}

export async function upsertModel(record: ModelRecord) {
  const db = await getDatabase();
  const row = toModelRow(record);

  await db.runAsync(
    `
      INSERT INTO models (
        id, provider, remote_id, label, is_enabled, is_custom, created_at, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        provider = excluded.provider,
        remote_id = excluded.remote_id,
        label = excluded.label,
        is_enabled = excluded.is_enabled,
        is_custom = excluded.is_custom,
        updated_at = excluded.updated_at
    `,
    row.id,
    row.provider,
    row.remote_id,
    row.label,
    row.is_enabled,
    row.is_custom,
    row.created_at,
    row.updated_at,
  );

  notifyModelsRefresh();
  void syncWidgetState();

  return record;
}

export async function listModels(options: ModelQueryOptions = {}) {
  const db = await getDatabase();
  const includeDisabled = options.includeDisabled ?? true;
  const rows = includeDisabled
    ? await db.getAllAsync<ReturnType<typeof toModelRow>>(
        "SELECT * FROM models ORDER BY is_enabled DESC, provider ASC, is_custom DESC, label ASC",
      )
    : await db.getAllAsync<ReturnType<typeof toModelRow>>(
        "SELECT * FROM models WHERE is_enabled = 1 ORDER BY provider ASC, is_custom DESC, label ASC",
      );

  return rows.map(fromModelRow);
}

export async function getModelById(id: string) {
  const db = await getDatabase();
  const rows = await db.getAllAsync<ReturnType<typeof toModelRow>>(
    "SELECT * FROM models WHERE id = ? LIMIT 1",
    id,
  );

  return rows[0] ? fromModelRow(rows[0]) : null;
}

export async function ensureDefaultModels() {
  const existing = await listModels({ includeDisabled: true });
  const existingById = new Set(existing.map((model) => model.id));
  const modelsToSeed = [...SEEDED_MODELS];

  for (const model of modelsToSeed) {
    if (existingById.has(model.id)) {
      continue;
    }

    await upsertModel(model);
  }

  return listModels();
}

export function createDefaultSettings(
  overrides: Partial<UserSettingsRecord> = {},
): UserSettingsRecord {
  const defaultSeedModelId = getDefaultSeedModelId();

  return {
    id: "default",
    focusPrompt: "",
    preferredDifficulty: "medium",
    preferredMode: "solo",
    notificationsEnabled: false,
    selectedModelId: defaultSeedModelId,
    challengeCadenceHours: 24,
    firstChallengeTimeMinutes: 9 * 60,
    updatedAt: createNowIso(),
    ...overrides,
  };
}

export function normalizeChallengeCadenceHours(
  value: number,
): ChallengeCadenceHours {
  if (!isValidChallengeCadenceHours(value)) {
    throw new Error(
      `Invalid challenge cadence: ${value}. Cadence must divide evenly into 24 hours.`,
    );
  }

  return value;
}

export function normalizeFirstChallengeTimeMinutes(value: number) {
  if (!isValidFirstChallengeTimeMinutes(value)) {
    throw new Error(
      `Invalid first challenge time: ${value}. Expected minutes from 0 to 1439.`,
    );
  }

  return value;
}

export async function ensureDefaultSettings() {
  await ensureDefaultModels();

  const existing = await getSettings();
  if (existing) {
    if (existing.selectedModelId) {
      return existing;
    }

    const defaultSeedModelId = getDefaultSeedModelId();

    const nextSettings: UserSettingsRecord = {
      ...existing,
      selectedModelId: defaultSeedModelId,
      updatedAt: createNowIso(),
    };

    await upsertSettings(nextSettings);
    return nextSettings;
  }

  const defaults = createDefaultSettings();
  await upsertSettings(defaults);
  return defaults;
}

export async function refreshReadyChallengeExpirations(settings: UserSettingsRecord) {
  const db = await getDatabase();
  const nextExpiresAt = getChallengeExpirationIso(settings);

  const result = await db.runAsync(
    `
      UPDATE challenges
      SET expires_at = ?
      WHERE lifecycle = 'ready'
    `,
    nextExpiresAt,
  );

  return result.changes;
}

export async function getSelectedModel() {
  const settings = await ensureDefaultSettings();

  if (!settings.selectedModelId) {
    return null;
  }

  const selectedModel = await getModelById(settings.selectedModelId);
  if (!selectedModel?.isEnabled) {
    return null;
  }

  return selectedModel;
}

export async function selectModel(modelId: string) {
  const model = await getModelById(modelId);
  if (!model || !model.isEnabled) {
    return null;
  }

  const settings = await ensureDefaultSettings();
  const nextSettings: UserSettingsRecord = {
    ...settings,
    selectedModelId: model.id,
    updatedAt: createNowIso(),
  };

  await upsertSettings(nextSettings);
  return model;
}

export async function setModelEnabled(modelId: string, isEnabled: boolean) {
  const model = await getModelById(modelId);
  if (!model) {
    return null;
  }

  await upsertModel({
    ...model,
    isEnabled,
    updatedAt: createNowIso(),
  });

  if (!isEnabled) {
    const settings = await ensureDefaultSettings();
    if (settings.selectedModelId === modelId) {
      const fallbackModels = await listModels({ includeDisabled: false });
      const fallbackModel = fallbackModels.find(
        (fallbackCandidate) => fallbackCandidate.id !== modelId,
      );

      await upsertSettings({
        ...settings,
        selectedModelId: fallbackModel?.id,
        updatedAt: createNowIso(),
      });
    }
  }

  return getModelById(modelId);
}

export async function getActiveModelCatalog() {
  await ensureDefaultModels();
  const [models, settings] = await Promise.all([
    listModels({ includeDisabled: false }),
    ensureDefaultSettings(),
  ]);

  return {
    models,
    selectedModelId: settings.selectedModelId,
  };
}

export async function markChallengeInProgress(
  challengeId: string,
  mode: ChallengeMode,
) {
  const challenge = await getChallengeById(challengeId);
  if (!challenge) {
    return null;
  }

  const nextRecord: ChallengeRecord = {
    ...challenge,
    lifecycle: "in_progress",
    startedAt: challenge.startedAt ?? createNowIso(),
  };

  await upsertChallenge(nextRecord);

  return nextRecord;
}

export async function completeChallenge(challengeId: string) {
  const challenge = await getChallengeById(challengeId);
  if (!challenge) {
    return null;
  }

  const now = createNowIso();
  const nextRecord: ChallengeRecord = {
    ...challenge,
    lifecycle: "completed",
    startedAt: challenge.startedAt ?? now,
    completedAt: now,
  };

  await upsertChallenge(nextRecord);
  return nextRecord;
}

export async function skipChallenge(challengeId: string) {
  const challenge = await getChallengeById(challengeId);
  if (!challenge) {
    return null;
  }

  const now = createNowIso();
  const nextRecord: ChallengeRecord = {
    ...challenge,
    lifecycle: "skipped",
    skippedAt: now,
    skipReason: "not_interested",
  };

  await upsertChallenge(nextRecord);
  return nextRecord;
}
