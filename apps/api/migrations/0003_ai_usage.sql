CREATE TABLE ai_runs (id TEXT PRIMARY KEY, account_id TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE, kind TEXT NOT NULL, model TEXT NOT NULL, prompt_version TEXT NOT NULL, input_tokens INTEGER, output_tokens INTEGER, cost REAL, created_at TEXT NOT NULL);
CREATE INDEX ai_runs_account ON ai_runs(account_id,created_at DESC);
