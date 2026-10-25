-- Developer-only: act as Free or Pro regardless of billing and the practice gate. Ignored unless the account is
-- listed in DEVELOPER_ACCOUNTS, so a stale value can never change a real customer's plan.
ALTER TABLE accounts ADD COLUMN plan_override TEXT CHECK(plan_override IN ('free','pro'));
