import type {
  ChallengeCadenceHours,
  ChallengeRecord,
  ChallengeSessionRecord,
  ChallengeSummaryRecord,
  UserSettingsRecord,
} from "@/lib/storage/types";
import type {
  ChallengeDifficulty,
  ChallengeLifecycle,
  ChallengeMode,
  ChallengeSkipReason,
} from "@/lib/widgets/types";

type Nullable<T> = T | null;

type ChallengeRow = {
  id: string;
  dedupe_key: string;
  title: string;
  teaser: string;
  topic: string;
  difficulty: Nullable<ChallengeDifficulty>;
  lifecycle: ChallengeLifecycle;
  mode: Nullable<ChallengeMode>;
  skip_reason: Nullable<ChallengeSkipReason>;
  created_at: string;
  started_at: Nullable<string>;
  completed_at: Nullable<string>;
  skipped_at: Nullable<string>;
  expires_at: Nullable<string>;
  source_model: Nullable<string>;
  source_prompt_version: Nullable<string>;
};

type ChallengeSummaryRow = {
  id: string;
  challenge_id: string;
  short_summary: string;
  short_feedback: string;
  strengths_json: string;
  weaknesses_json: string;
  tags_json: string;
  completion_score: Nullable<number>;
  generated_at: string;
};

type ChallengeSessionRow = {
  challenge_id: string;
  selected_mode: Nullable<ChallengeMode>;
  notes_draft: Nullable<string>;
  conversation_summary: Nullable<string>;
  updated_at: string;
};

type SettingsRow = {
  id: "default";
  focus_prompt: string;
  preferred_difficulty: Nullable<ChallengeDifficulty>;
  preferred_mode: Nullable<ChallengeMode>;
  default_model: Nullable<string>;
  challenge_cadence_hours: Nullable<ChallengeCadenceHours>;
  first_challenge_time_minutes: Nullable<number>;
  updated_at: string;
};

function undefinedIfNull<T>(value: Nullable<T>) {
  return value ?? undefined;
}

export function serializeJsonArray(values: string[]) {
  return JSON.stringify(values);
}

export function parseJsonArray(value: string) {
  const parsed = JSON.parse(value) as unknown;
  return Array.isArray(parsed) ? parsed.filter((item): item is string => typeof item === "string") : [];
}

export function toChallengeRow(record: ChallengeRecord): ChallengeRow {
  return {
    id: record.id,
    dedupe_key: record.dedupeKey,
    title: record.title,
    teaser: record.teaser,
    topic: record.topic,
    difficulty: record.difficulty ?? null,
    lifecycle: record.lifecycle,
    mode: record.mode ?? null,
    skip_reason: record.skipReason ?? null,
    created_at: record.createdAt,
    started_at: record.startedAt ?? null,
    completed_at: record.completedAt ?? null,
    skipped_at: record.skippedAt ?? null,
    expires_at: record.expiresAt ?? null,
    source_model: record.sourceModel ?? null,
    source_prompt_version: record.sourcePromptVersion ?? null,
  };
}

export function fromChallengeRow(row: ChallengeRow): ChallengeRecord {
  return {
    id: row.id,
    dedupeKey: row.dedupe_key,
    title: row.title,
    teaser: row.teaser,
    topic: row.topic,
    difficulty: undefinedIfNull(row.difficulty),
    lifecycle: row.lifecycle,
    mode: undefinedIfNull(row.mode),
    skipReason: undefinedIfNull(row.skip_reason),
    createdAt: row.created_at,
    startedAt: undefinedIfNull(row.started_at),
    completedAt: undefinedIfNull(row.completed_at),
    skippedAt: undefinedIfNull(row.skipped_at),
    expiresAt: undefinedIfNull(row.expires_at),
    sourceModel: undefinedIfNull(row.source_model),
    sourcePromptVersion: undefinedIfNull(row.source_prompt_version),
  };
}

export function toChallengeSummaryRow(record: ChallengeSummaryRecord): ChallengeSummaryRow {
  return {
    id: record.id,
    challenge_id: record.challengeId,
    short_summary: record.shortSummary,
    short_feedback: record.shortFeedback,
    strengths_json: serializeJsonArray(record.strengths),
    weaknesses_json: serializeJsonArray(record.weaknesses),
    tags_json: serializeJsonArray(record.tags),
    completion_score: record.completionScore ?? null,
    generated_at: record.generatedAt,
  };
}

export function fromChallengeSummaryRow(row: ChallengeSummaryRow): ChallengeSummaryRecord {
  return {
    id: row.id,
    challengeId: row.challenge_id,
    shortSummary: row.short_summary,
    shortFeedback: row.short_feedback,
    strengths: parseJsonArray(row.strengths_json),
    weaknesses: parseJsonArray(row.weaknesses_json),
    tags: parseJsonArray(row.tags_json),
    completionScore: undefinedIfNull(row.completion_score),
    generatedAt: row.generated_at,
  };
}

export function toChallengeSessionRow(record: ChallengeSessionRecord): ChallengeSessionRow {
  return {
    challenge_id: record.challengeId,
    selected_mode: record.selectedMode ?? null,
    notes_draft: record.notesDraft ?? null,
    conversation_summary: record.conversationSummary ?? null,
    updated_at: record.updatedAt,
  };
}

export function fromChallengeSessionRow(row: ChallengeSessionRow): ChallengeSessionRecord {
  return {
    challengeId: row.challenge_id,
    selectedMode: undefinedIfNull(row.selected_mode),
    notesDraft: undefinedIfNull(row.notes_draft),
    conversationSummary: undefinedIfNull(row.conversation_summary),
    updatedAt: row.updated_at,
  };
}

export function toSettingsRow(record: UserSettingsRecord): SettingsRow {
  return {
    id: record.id,
    focus_prompt: record.focusPrompt,
    preferred_difficulty: record.preferredDifficulty ?? null,
    preferred_mode: record.preferredMode ?? null,
    default_model: record.defaultModel ?? null,
    challenge_cadence_hours: record.challengeCadenceHours ?? null,
    first_challenge_time_minutes: record.firstChallengeTimeMinutes ?? null,
    updated_at: record.updatedAt,
  };
}

export function fromSettingsRow(row: SettingsRow): UserSettingsRecord {
  return {
    id: row.id,
    focusPrompt: row.focus_prompt,
    preferredDifficulty: undefinedIfNull(row.preferred_difficulty),
    preferredMode: undefinedIfNull(row.preferred_mode),
    defaultModel: undefinedIfNull(row.default_model),
    challengeCadenceHours: undefinedIfNull(row.challenge_cadence_hours),
    firstChallengeTimeMinutes: undefinedIfNull(row.first_challenge_time_minutes),
    updatedAt: row.updated_at,
  };
}
