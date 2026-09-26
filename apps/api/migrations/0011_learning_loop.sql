CREATE TABLE recall_cards (
  id TEXT PRIMARY KEY,
  account_id TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  source_challenge_id TEXT NOT NULL REFERENCES challenges(id) ON DELETE CASCADE,
  concept_id TEXT NOT NULL,
  question TEXT NOT NULL,
  answer TEXT NOT NULL,
  due_at TEXT NOT NULL,
  interval_days INTEGER NOT NULL DEFAULT 0,
  repetitions INTEGER NOT NULL DEFAULT 0,
  lapses INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  UNIQUE(account_id, source_challenge_id, concept_id)
);
CREATE INDEX recall_due ON recall_cards(account_id, due_at, id);

CREATE TABLE recall_reviews (
  id TEXT PRIMARY KEY,
  account_id TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  card_id TEXT NOT NULL REFERENCES recall_cards(id) ON DELETE CASCADE,
  rating TEXT NOT NULL CHECK(rating IN ('again','got_it')),
  response_ms INTEGER,
  reviewed_at TEXT NOT NULL
);
CREATE INDEX recall_review_history ON recall_reviews(account_id, reviewed_at DESC);

CREATE TABLE retry_sources (
  challenge_id TEXT PRIMARY KEY REFERENCES challenges(id) ON DELETE CASCADE,
  source_challenge_id TEXT NOT NULL REFERENCES challenges(id) ON DELETE CASCADE,
  source_turn_id TEXT NOT NULL
);
