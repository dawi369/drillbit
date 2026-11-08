-- Deleted questions also keep their waived silent looks, so deleting can't hand back free looks.
ALTER TABLE spent_voice ADD COLUMN waived INTEGER NOT NULL DEFAULT 0;
DROP VIEW counted_voice;
CREATE VIEW counted_voice AS
 SELECT id, account_id, created_at, CASE WHEN usage_seconds > 0 THEN usage_seconds ELSE MAX(0, (julianday(expires_at) - julianday(created_at)) * 86400 - 30) END AS seconds
 FROM voice_sessions WHERE provider_id IS NOT NULL AND waived = 0
 UNION ALL SELECT id, account_id, created_at, seconds FROM spent_voice WHERE waived = 0;
