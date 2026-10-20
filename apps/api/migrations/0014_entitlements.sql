CREATE TABLE entitlements (
 original_transaction_id TEXT PRIMARY KEY,
 account_id TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
 product_id TEXT NOT NULL,
 environment TEXT NOT NULL,
 status TEXT NOT NULL CHECK(status IN ('active','grace','expired','revoked')),
 active_until TEXT,
 signed_at TEXT NOT NULL,
 created_at TEXT NOT NULL,
 updated_at TEXT NOT NULL
);
CREATE INDEX entitlements_account ON entitlements(account_id);
