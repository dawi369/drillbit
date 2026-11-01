-- Voice notes from Settings to the developer. The audio stays here (never sent to an AI provider) and goes with the account.
CREATE TABLE voice_notes (
 id TEXT PRIMARY KEY,
 account_id TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
 audio BLOB NOT NULL,
 duration_seconds REAL NOT NULL,
 app_version TEXT,
 created_at TEXT NOT NULL
);
CREATE INDEX voice_notes_recent ON voice_notes(created_at);
CREATE INDEX voice_notes_account ON voice_notes(account_id, created_at);
