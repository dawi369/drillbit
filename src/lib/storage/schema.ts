export const DATABASE_NAME = "drillbit.db";

export const CREATE_CHALLENGES_TABLE_SQL = `
  CREATE TABLE IF NOT EXISTS challenges (
    id TEXT PRIMARY KEY NOT NULL,
    title TEXT NOT NULL,
    teaser TEXT NOT NULL,
    topic TEXT NOT NULL,
    difficulty TEXT,
    lifecycle TEXT NOT NULL,
    skip_reason TEXT,
    created_at TEXT NOT NULL,
    started_at TEXT,
    completed_at TEXT,
    skipped_at TEXT,
    expires_at TEXT,
    source_model TEXT,
    source_prompt_version TEXT
  );
`;

export const CREATE_CHALLENGE_SUMMARIES_TABLE_SQL = `
  CREATE TABLE IF NOT EXISTS challenge_summaries (
    id TEXT PRIMARY KEY NOT NULL,
    challenge_id TEXT NOT NULL,
    short_summary TEXT NOT NULL,
    short_feedback TEXT NOT NULL,
    strengths_json TEXT NOT NULL,
    weaknesses_json TEXT NOT NULL,
    tags_json TEXT NOT NULL,
    completion_score REAL,
    generated_at TEXT NOT NULL,
    FOREIGN KEY (challenge_id) REFERENCES challenges (id) ON DELETE CASCADE
  );
`;

export const CREATE_CHALLENGE_SESSIONS_TABLE_SQL = `
  CREATE TABLE IF NOT EXISTS challenge_sessions (
    challenge_id TEXT PRIMARY KEY NOT NULL,
    selected_mode TEXT,
    notes_draft TEXT,
    conversation_summary TEXT,
    conversation_history_json TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    FOREIGN KEY (challenge_id) REFERENCES challenges (id) ON DELETE CASCADE
  );
`;

export const CREATE_SETTINGS_TABLE_SQL = `
  CREATE TABLE IF NOT EXISTS settings (
    id TEXT PRIMARY KEY NOT NULL,
    focus_prompt TEXT NOT NULL,
    preferred_difficulty TEXT,
    preferred_mode TEXT,
    selected_model_id TEXT,
    challenge_cadence_hours INTEGER,
    first_challenge_time_minutes INTEGER,
    updated_at TEXT NOT NULL
  );
`;

export const CREATE_MODELS_TABLE_SQL = `
  CREATE TABLE IF NOT EXISTS models (
    id TEXT PRIMARY KEY NOT NULL,
    provider TEXT NOT NULL,
    remote_id TEXT NOT NULL,
    label TEXT NOT NULL,
    is_enabled INTEGER NOT NULL,
    is_custom INTEGER NOT NULL,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
  );
`;

export const CREATE_BLOCKED_CHALLENGES_TABLE_SQL = `
  CREATE TABLE IF NOT EXISTS blocked_challenges (
    challenge_id TEXT PRIMARY KEY NOT NULL,
    summary TEXT NOT NULL,
    blocked_at TEXT NOT NULL,
    source_lifecycle TEXT NOT NULL
  );
`;

export const CREATE_INDEXES_SQL = [
  "CREATE INDEX IF NOT EXISTS idx_challenges_lifecycle ON challenges (lifecycle);",
  "CREATE INDEX IF NOT EXISTS idx_challenges_topic ON challenges (topic);",
  "CREATE INDEX IF NOT EXISTS idx_challenge_summaries_challenge_id ON challenge_summaries (challenge_id);",
  "CREATE INDEX IF NOT EXISTS idx_blocked_challenges_lifecycle ON blocked_challenges (source_lifecycle);",
  "CREATE INDEX IF NOT EXISTS idx_models_provider ON models (provider);",
  "CREATE INDEX IF NOT EXISTS idx_models_enabled ON models (is_enabled);",
];

export const CREATE_ALL_TABLES_SQL = [
  CREATE_CHALLENGES_TABLE_SQL,
  CREATE_CHALLENGE_SUMMARIES_TABLE_SQL,
  CREATE_CHALLENGE_SESSIONS_TABLE_SQL,
  CREATE_SETTINGS_TABLE_SQL,
  CREATE_MODELS_TABLE_SQL,
  CREATE_BLOCKED_CHALLENGES_TABLE_SQL,
  ...CREATE_INDEXES_SQL,
];
