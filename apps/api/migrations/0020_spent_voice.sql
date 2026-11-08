-- Voice time on challenges that were later deleted. voice_sessions cascade with their challenge, so without this,
-- deleting a question from Library would hand back Pro's daily and weekly minutes and a free account's voice mock.
-- Cleared only with the account (or the developer practice reset).
CREATE TABLE spent_voice (id TEXT PRIMARY KEY, account_id TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE, created_at TEXT NOT NULL, seconds REAL NOT NULL);
CREATE INDEX spent_voice_account ON spent_voice(account_id, created_at);
-- Every counted voice session, kept or deleted. A session that never reported counts its whole cap; waived ones are free.
CREATE VIEW counted_voice AS
 SELECT id, account_id, created_at, CASE WHEN usage_seconds > 0 THEN usage_seconds ELSE MAX(0, (julianday(expires_at) - julianday(created_at)) * 86400 - 30) END AS seconds
 FROM voice_sessions WHERE provider_id IS NOT NULL AND waived = 0
 UNION ALL SELECT id, account_id, created_at, seconds FROM spent_voice;
