-- Sign-in subjects (SHA-256 of the Clerk user id) whose account was just deleted. Session tokens outlive the
-- deletion by up to a minute; without this, a request in that window would create a fresh empty account for a person
-- who asked to be forgotten. Rows expire after ten minutes and the cron removes them.
CREATE TABLE deleted_subjects (subject_hash TEXT PRIMARY KEY, until TEXT NOT NULL);
