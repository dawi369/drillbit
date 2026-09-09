CREATE TABLE help_results (id TEXT PRIMARY KEY REFERENCES jobs(id) ON DELETE CASCADE, data TEXT NOT NULL);
CREATE UNIQUE INDEX one_help ON jobs(account_id) WHERE kind='help' AND status IN ('pending','running');
CREATE TABLE draft_events (id TEXT PRIMARY KEY, challenge_id TEXT NOT NULL REFERENCES challenges(id) ON DELETE CASCADE, source_id TEXT NOT NULL, operation TEXT NOT NULL, previous_answer TEXT NOT NULL, applied_answer TEXT NOT NULL, revision INTEGER NOT NULL, created_at TEXT NOT NULL);
CREATE INDEX draft_event_history ON draft_events(challenge_id,created_at);
UPDATE settings SET data=json_set(data,'$.model','google/gemini-3.1-flash-lite');
CREATE TABLE completion_context (challenge_id TEXT PRIMARY KEY REFERENCES challenges(id) ON DELETE CASCADE, data TEXT NOT NULL);
