CREATE TABLE interview_turns (
 id TEXT PRIMARY KEY REFERENCES jobs(id) ON DELETE CASCADE,
 challenge_id TEXT NOT NULL REFERENCES challenges(id) ON DELETE CASCADE,
 ordinal INTEGER NOT NULL,
 kind TEXT NOT NULL,
 prompt TEXT NOT NULL,
 text TEXT NOT NULL,
 result TEXT,
 job_id TEXT NOT NULL REFERENCES jobs(id),
 created_at TEXT NOT NULL,
 UNIQUE(challenge_id,ordinal)
);
CREATE UNIQUE INDEX one_interview_request ON jobs(account_id) WHERE kind='interview' AND status IN ('pending','running');
