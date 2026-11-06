# Apple review: operations

What App Review gets, what to check before submitting, and what to do while it's in review or after a rejection. Checked on 6 November 2026 against production; re-run the checks below before you submit.

## State on 6 November

- **Build to submit:** 1.0 (20), uploaded 6 November (layered icon). App Store Connect still selects 16 until [`computer-use.md`](../computer-use.md) step 1 is done.
- **Production** (`https://api.drillbit.t23.dev`): `/health`, `/privacy` and `/support` return 200; `/apple/notifications` exists (400 on an empty POST). Sentry has no open issues for `drillbit-api` or `drillbit-ios`.
- **Live proof:** after the owner's reset, production wrote 3 questions (OpenRouter) and opened a voice session that reached OpenAI. Account deletion ran end to end (Clerk user and all D1 rows gone) about 3 minutes after it was queued.
- **AI credit:** the OpenRouter account had $20.34 left. The development and production keys share it.

## What a reviewer gets

- **Sign-up:** the production backend with open signup and Sign in with Apple. There's no invite code and no demo account, and "Sign-in required" in App Store Connect stays unchecked.
- **First run:** Welcome, a one-minute setup, sign-in, then the AI permission sheet ("Bit runs on outside AI", naming OpenRouter and OpenAI). It appears before the first question is written. Settings → AI and your data shows the same text.
- **Free:** 3 questions in total and one voice mock of up to 10 minutes. The first silent voice session is free, and voice hangs up after a quiet minute until they speak.
- **Pro:** reached from Settings → See Pro, after the 3 free questions, or from the Bit tab. Every Pro screen shows price, period and auto-renewal, plus Terms, Privacy and Restore.
- **Purchases:** made in Sandbox. Production accepts Sandbox receipts on purpose (no `APPLE_ENVIRONMENT` set), so Pro unlocks as soon as the server confirms. Apple's server notifications go to `/apple/notifications`.
- **Deletion:** Settings → Delete account. A job deletes the Clerk user and every row of theirs; the 5-minute cron runs it.

## Before you press Submit for Review

1. Physical-device acceptance: [readiness §7](app-store-readiness.md#7-physical-device-acceptance-you-about-45-minutes-required-before-submitting).
2. [`computer-use.md`](../computer-use.md) is done: build 20 selected; listing, screenshots, review notes and subscription review images are current.
3. Credit:
   - Top up OpenRouter so review and launch can't run it dry; $20 is thin.
   - Check the production key's own limit in the OpenRouter dashboard.
   - Check the OpenAI balance (voice).
4. Re-run the checks:
   ```sh
   for p in health privacy support; do curl -s -o /dev/null -w "$p %{http_code}\n" https://api.drillbit.t23.dev/$p; done
   sentry issue list t23/drillbit-api; sentry issue list t23/drillbit-ios
   ```
5. Freeze backend deploys while it's in review, except to fix what review found.

## While it's in review

- **Watch:** Sentry (both projects) and `bun scripts/metrics.ts --sandbox`, which counts reviewer sign-ups, reps and Sandbox purchases. Failed jobs:
  `wrangler d1 execute drillbit-production --remote --env production --command "SELECT kind,error,updated_at FROM jobs WHERE status='failed' ORDER BY updated_at DESC LIMIT 20"` (from `apps/api`).
- **AI failures** show in Sentry by cause:
  - `managed_out_of_credits` or `managed_budget_reached`: top up, or raise the key's limit.
  - `managed_policy_blocked`: OpenRouter guardrails are blocking the model.
  - `managed_key_rejected`: rotate the key with `wrangler secret put OPENROUTER_API_KEY --env production`.
- **Server-side fixes** (prompts, limits, server copy) ship with `wrangler deploy --env production` and need no new build. Anything in the app needs a new build number, upload, re-selecting the build and resubmitting.

## If it's rejected

Reply in App Store Connect's Resolution Center. Name the screen and the steps, and attach a screenshot.

| Guideline | Where it's handled |
|---|---|
| 2.1 Crash or bug | Sentry `drillbit-ios` for the build. Reproduce on a phone, fix, then ship build 21. |
| 2.1 Demo account | Explain that Sign in with Apple creates an account in seconds. Don't share an Apple Account. |
| 2.3 Metadata or screenshots | [Listing](app-store-readiness.md#6-store-listing-you-with-drafts-here). All 5 screenshots show the app in use. |
| 3.1.2 Subscriptions | Price, period, auto-renewal, Terms, Privacy and Restore are on every Pro screen ([`review-paywall.png`](design/app-store/review-paywall.png)). |
| 5.1.1(v) Account deletion | Settings → Delete account. Deletes everything, including the sign-in account. |
| 5.1.2(i) Third-party AI | The permission sheet before any AI call, and Settings → AI and your data ([screenshots](design/app-store/)). |

## After approval

- Release when you're ready, then check that the first real sign-ups get questions, using Sentry and `bun scripts/metrics.ts`.
- Leave name, subtitle and keywords alone for 2–4 weeks before judging them ([paywall plan §15–16](paywall-plan.md) for what to watch).
