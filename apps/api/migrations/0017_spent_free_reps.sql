-- Free reps spent on challenges that were later deleted. Lifetime free reps count these too, so deleting a
-- finished rep never hands it back. Cleared only with the account (or the developer practice reset).
CREATE TABLE spent_free_reps (account_id TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE, stamp TEXT NOT NULL, PRIMARY KEY (account_id, stamp));
