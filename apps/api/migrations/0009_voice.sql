CREATE TABLE voice_sessions (
 id TEXT PRIMARY KEY REFERENCES interview_turns(id) ON DELETE CASCADE,
 account_id TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
 challenge_id TEXT NOT NULL REFERENCES challenges(id) ON DELETE CASCADE,
 provider_id TEXT,
 status TEXT NOT NULL DEFAULT 'connecting',
 created_at TEXT NOT NULL,
 expires_at TEXT NOT NULL,
 usage_seconds REAL,
 finalized INTEGER NOT NULL DEFAULT 0
);
CREATE UNIQUE INDEX one_voice_session ON voice_sessions(account_id) WHERE status IN ('connecting','active');
CREATE TABLE voice_fragments (
 session_id TEXT NOT NULL REFERENCES voice_sessions(id) ON DELETE CASCADE,
 id TEXT NOT NULL,
 sequence INTEGER NOT NULL,
 speaker TEXT NOT NULL CHECK(speaker IN ('user','assistant')),
 text TEXT NOT NULL,
 start_ms INTEGER NOT NULL,
 end_ms INTEGER NOT NULL,
 PRIMARY KEY(session_id,id),
 UNIQUE(session_id,sequence)
);
CREATE TABLE voice_delegations (
 session_id TEXT NOT NULL REFERENCES voice_sessions(id) ON DELETE CASCADE,
 id TEXT NOT NULL,
 status TEXT NOT NULL DEFAULT 'running',
 result TEXT,
 PRIMARY KEY(session_id,id)
);
