-- One row each time the native paywall is shown: who, where, when. Nothing else, and it goes with the account.
CREATE TABLE paywall_views (
 account_id TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
 placement TEXT NOT NULL CHECK(placement IN ('practice_rep','voice_session','knowledge_map','first_rep')),
 created_at TEXT NOT NULL
);
CREATE INDEX paywall_views_account ON paywall_views(account_id, created_at);
CREATE INDEX paywall_views_recent ON paywall_views(created_at);
