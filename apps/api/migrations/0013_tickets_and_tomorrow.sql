-- A ticket is the account's highest ticket plus one: deleting a session can leave a gap but never a duplicate.
UPDATE challenges SET data=json_set(data,'$.ticket',numbered.ticket)
FROM (SELECT id,ROW_NUMBER() OVER (PARTITION BY account_id ORDER BY completed_at,id) AS ticket FROM challenges
  WHERE lifecycle='completed' AND COALESCE(json_extract(data,'$.warmUp'),0)=0) AS numbered
WHERE challenges.id=numbered.id AND json_extract(challenges.data,'$.ticket') IS NULL;

-- One completed session per account can shape the next automatic daily question.
CREATE TABLE queued_follow_ups (
  account_id TEXT PRIMARY KEY REFERENCES accounts(id) ON DELETE CASCADE,
  source_challenge_id TEXT NOT NULL REFERENCES challenges(id) ON DELETE CASCADE,
  created_at TEXT NOT NULL
);
