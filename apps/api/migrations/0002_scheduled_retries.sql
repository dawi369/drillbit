DROP INDEX IF EXISTS one_scheduled_job;
CREATE UNIQUE INDEX one_scheduled_job ON jobs(account_id,json_extract(input,'$.availableAt')) WHERE kind='generate' AND status NOT IN ('cancelled','failed') AND json_extract(input,'$.availableAt') IS NOT NULL;
