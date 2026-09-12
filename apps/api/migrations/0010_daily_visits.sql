CREATE TABLE daily_visits (
 account_id TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
 local_day TEXT NOT NULL,
 created_at TEXT NOT NULL,
 PRIMARY KEY(account_id,local_day)
);
