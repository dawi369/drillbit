CREATE TABLE practice_epoch (id INTEGER PRIMARY KEY CHECK(id=1), value TEXT NOT NULL, enabled INTEGER NOT NULL DEFAULT 1);
INSERT OR IGNORE INTO practice_epoch (id,value) VALUES(1,'library-v1');
CREATE TABLE questions (id TEXT PRIMARY KEY, account_id TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE, data TEXT NOT NULL, created_at TEXT NOT NULL, eligible INTEGER NOT NULL DEFAULT 0, eligibility_revision INTEGER NOT NULL DEFAULT 0, eligibility_command TEXT, eligibility_updated_at TEXT NOT NULL);
CREATE INDEX question_account ON questions(account_id,created_at,id);
CREATE TABLE question_attempts (challenge_id TEXT PRIMARY KEY REFERENCES challenges(id) ON DELETE CASCADE, question_id TEXT NOT NULL REFERENCES questions(id) ON DELETE CASCADE);
CREATE INDEX question_attempt_lookup ON question_attempts(question_id,challenge_id);
CREATE TABLE library_commands (account_id TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE, command TEXT NOT NULL, question_id TEXT NOT NULL REFERENCES questions(id) ON DELETE CASCADE, revision INTEGER NOT NULL, eligible INTEGER NOT NULL, PRIMARY KEY(account_id,command));
