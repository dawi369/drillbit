-- A voice session closed cleanly before the user said anything doesn't count against any allowance.
ALTER TABLE voice_sessions ADD COLUMN waived INTEGER NOT NULL DEFAULT 0;
