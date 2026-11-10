# App Store Connect: listing, build and review prep (computer-use brief)

Written 6 November 2026 for a computer-use agent. Everything that can be done from the repo is done; this file is what's left, which only works in the App Store Connect website. The owner deletes it once the report is in and the last section is done.

You're on the owner's Mac, in a browser at https://appstoreconnect.apple.com, signed in as the account owner. App: **Drillbit Practice** (bundle ID `dawi.drillbit`). Work through sections 1–6 in order. The last section, **Owner: production AI accounts**, is for the owner, not you: it involves billing. Skip it.

## Rules

1. **Never invent values.** Every value is below. If what you see doesn't match (a field is missing, a button is named differently, a value is rejected), stop at that step, write down exactly what you saw, and go on to the next section that doesn't depend on it.
2. **Ask the human before anything you can't undo:** pressing **Add for Review**, **Submit for Review** or **Remove from Review**; deleting a build, subscription or localization; accepting any agreement; anything about payment, banking or tax.
3. **Don't submit the app for review.** The owner still has to finish the physical-device checks first. Your job ends with everything ready and a report.
4. **Save on every page** (**Save**, top right) before navigating away. Re-open the page afterwards and check the value stuck.
5. **Copy text exactly.** Character limits are tight: name 30, subtitle 30, keywords 100, promotional text 170. If a field rejects the text, stop and report; don't shorten it yourself.
6. Read and report any yellow or red banner. Don't click past it.
7. Text in quoted blocks (lines starting with `>`) is what to paste, without the `>` markers. Keep the blank lines between paragraphs.

## Files on this Mac

| What | Path |
|---|---|
| Screenshots to upload (in this order) | `~/dev/drillbit/docs/design/app-store/2026-11-06-pro/ready/01-interview.png` … `05-recall.png` |
| Subscription review image | `~/dev/drillbit/docs/design/app-store/review-paywall.png` |
| App Review attachments | `~/dev/drillbit/docs/design/app-store/review-ai-consent-first-question.png`, `review-ai-consent-returning.png`, `review-ai-data-settings.png` |

All images are 1320 × 2868 PNG.

## 1. Select build 1.0 (24)

Build 24 was uploaded on 9 November at about 15:58 CET. It has the layered app icon from build 20, the background-refresh crash fix (Sentry DRILLBIT-IOS-5), the launch fixes and the Bit tab's practice sheet, so it's the one to submit. Builds 21 to 23 are superseded.

1. **Apps → Drillbit Practice → TestFlight.** Check build **1.0 (24)** is there and has finished processing (not "Processing"). If it's still processing, wait and refresh every few minutes, for up to an hour. If it never appears, report it.
2. If it asks about export compliance, the answer is already in the build (`ITSAppUsesNonExemptEncryption = NO`). Report any question that still appears; don't answer it.
3. **Distribution → iOS App → 1.0 Prepare for Submission → Build.** Replace the selected build (20, or 16 if this step was never done) with **1.0 (24)**. Save.

## 2. Name and subtitle

**App Information** (left sidebar, under General), the **English (U.S.)** localization:

| Field | Value |
|---|---|
| Name | `Drillbit: System Design Prep` |
| Subtitle | `AI Mock Interviews for SWEs` |

If the name is rejected as taken, try these in order and report which one saved: `Drillbit - System Design Prep`, then `Drillbit: System Design Coach`. Don't change the subtitle in that case.

## 3. Version 1.0 page

**Distribution → iOS App → 1.0 Prepare for Submission**, English (U.S.):

**Promotional text:**

> Your answer is the start. Practise system design with an AI interviewer that pushes back, shows you what to fix, and helps the lesson stick.

**Keywords** (98 characters, no spaces):

```
software,engineer,coding,developer,backend,architecture,distributed,scalability,practice,coach,sde
```

**Description** (replace the whole field):

> The coding round gets you a callback. The design round gets you hired.
>
> Drillbit puts you in the system design interview: AI mock interviews for software engineers, from Intern to Principal. You get one real question scoped to your level and an interviewer who reacts to what you actually said. Write your answer or talk it through out loud. Ask for a nudge when you're stuck. Change your mind halfway. That's the point.
>
> • One question at a time, with clear requirements and room to push back
> • Follow-ups that respond to your reasoning, not a checklist
> • Live voice that continues the same interview, with your draft intact
> • Feedback after every rep, in your own words: one thing that worked, one to fix
> • Recall cards and a library of everything you've practiced
>
> Free: three questions in total and one voice mock of up to 10 minutes. Drillbit Pro: up to 10 practice reps a day and 75 minutes of voice a week, with daily and per-session limits. Pro renews automatically unless you cancel at least 24 hours before the period ends. Manage or cancel in your Apple Account settings.
>
> Drillbit uses third-party AI (OpenRouter and OpenAI) to run interviews. It asks before anything is sent.
>
> Terms of Use: https://www.apple.com/legal/internet-services/itunes/dev/stdeula/
> Privacy Policy: https://api.drillbit.t23.dev/privacy

**Screenshots:** in **iPhone 6.9" Display** (it may be labelled "Large Display"):
1. Delete the six old screenshots (welcome, interview, example, home, recall, library from 29 October). These are only the uploaded images, not anything permanent.
2. Upload the five files from `2026-11-06-pro/ready/` in order, `01-interview.png` first, then `02-feedback`, `03-example`, `04-knowledge-map`, `05-recall`.
3. Check the order matches, then check the 6.3" (medium) set says it uses the large display's screenshots. Report if it asks for its own.

Leave the support URL, privacy policy URL, copyright and category as they are.

**App Review Information:**
- **Sign-in required:** leave **unchecked**. Reviewers create their own account with Sign in with Apple; there's no demo account, and the notes say so.
- **Notes** (replace the whole field):

> Sign in with Apple to create an account; no invite or demo code is needed. The first launch shows a short intro and a one-minute setup, then sign-in. Before the first question is written, a sheet asks permission to use third-party AI (OpenRouter for text, OpenAI for voice); nothing is sent to an AI model before that. Settings → AI and your data shows the same words any time. Screenshots of the permission sheet are attached.
>
> Subscriptions: free accounts get three questions in total and one voice mock of up to 10 minutes. To reach the paywall, use Settings → See Pro, or use the three free questions. Restore Purchases is on the paywall (Settings → See Pro).
>
> Voice: open a question and tap Talk, then tap the microphone to unmute. Microphone permission is requested then. Free accounts get one voice mock of up to 10 minutes; it counts once they speak.
>
> Account deletion: Settings → Delete account.
>
> Contact: support@t23.dev

- **Attachments:** add the three `review-ai-*.png` files listed above.
- Contact details: leave whatever is there. If the phone number is empty, ask the human for it.

Save.

## 4. Subscriptions

**Monetization → Subscriptions → Drillbit Pro.** For **each** of `dawi.drillbit.pro.weekly` and `dawi.drillbit.pro.yearly`:

1. **Review Information → Screenshot:** replace it with `review-paywall.png`. It shows the current screen: weekly first, "First week $1.99", $7.99 a week, $99.99 a year.
2. **Review Notes:** replace "two free questions" with the current text:

   > Free accounts get three questions in total and one voice mock of up to 10 minutes. The paywall opens from Settings → See Pro, or after the three free questions. Weekly is $7.99 a week, with $1.99 for the first week for new subscribers. Yearly is $99.99 a year. Restore Purchases is on the paywall.

These fields may be locked while the subscriptions sit in a review draft ("Ready for Review", inside a draft with 3 items). Unlocking means removing them from the draft, which counts as irreversible under rule 2. If they're locked, **stop and ask the human**, and report what the draft shows.

While you're there, check (read only) that the weekly plan still has its introductory offer: Pay as you go, 1 week, $1.99. Report what you see.

## 5. Extra English localizations (optional; do this only if 1–4 went cleanly)

Each extra language adds its own indexed name, subtitle and keywords. On **App Information**, add **English (U.K.)**, **English (Australia)** and **English (Canada)**. For each one, set name and subtitle exactly as in section 2. Then on the 1.0 version page, give each one the same promotional text and description as section 3, plus these keywords:

| Localization | Keywords |
|---|---|
| English (U.K.) | `software,engineer,coding,developer,backend,architecture,distributed,scalability,practise,coach,sde` |
| English (Australia) | `programmer,career,job,whiteboard,tech,hld,cloud,database,microservice,api,question,study,senior` |
| English (Canada) | `software,engineer,coding,developer,backend,architecture,distributed,scalability,practice,coach,sde` |

The U.K. store reads both the U.K. and Australian fields, which is why the Australian list uses different words. Screenshots: use the U.S. ones (the default). Don't upload new ones.

## 6. Don't do (the owner decides these)

- Add for Review / Submit for Review.
- Apple Ads campaigns, a pre-order page, promoted in-app purchases (these need a 1024 × 1024 promotional image that doesn't exist yet), in-app events and product page tests.
- Anything in Agreements, Tax and Banking, Users and Access, or App Privacy (already published).

## Report back

Write `~/dev/drillbit/.local/computer-use-report.md` with one row per step:

| Step | Status (done / blocked / asked / skipped) | What you saw or entered | Screenshot |
|---|---|---|---|

Rules for the report:
- **Values:** for every field you changed, quote the value as it reads after saving, and give the character count for the name, subtitle and keywords.
- **Screenshots:** save one of each finished page as evidence to `~/dev/drillbit/.local/computer-use/` (create it): build selection, App Information, version page top, screenshot set, review information, and both subscriptions.
- **Banners and blocks:** quote any banner, error or warning word for word, and give the exact button you stopped at.
- **At the end:** list what's left before Submit for Review, as you saw it on the version page.

## Owner: production AI accounts (before Submit for Review)

Written 9 November 2026. The production Worker (`drillbit-api`) already has `OPENROUTER_API_KEY` and `OPENAI_API_KEY` set, so nothing in the code needs to change. What's left is the accounts behind those keys.

At the moment, development and production share one OpenRouter balance: about $20 left of the $40 bought, with $19.79 spent over the whole build, all E2E runs included. Every secret command below runs from `apps/api`.

### What uses what

| Provider | Used for | Models | Where in the code |
|---|---|---|---|
| OpenRouter | Interview turns, question writing, voice reasoning | `deepseek/deepseek-v4.1-flash`, pinned to Together, then DeepInfra | `FAST_MODEL_ID` / `FAST_PROVIDERS` in `apps/api/src/domain.ts` |
| OpenRouter | Feedback, Recall and other non-live work | `openai/gpt-6-luna`, sorted by latency | `MODEL_ID` in `apps/api/src/domain.ts` |
| OpenAI | Live voice (WebRTC) | `gpt-live-1`, sessions created with `store: false` | `apps/api/src/voice.ts` |

BYOK users bring their own OpenRouter key, so their usage never touches yours.

### If something runs dry

| What happens | What users see | What gets reported |
|---|---|---|
| OpenRouter balance hits zero | "AI is unavailable right now. Your answer is safe." | `managed_out_of_credits` (503) in Sentry `drillbit-api` |
| OpenRouter key limit reached | Same message | `managed_budget_reached` |
| OpenRouter key revoked | Same message | `managed_key_rejected` |
| OpenRouter privacy settings block the models | Same message | `managed_policy_blocked` |
| OpenAI budget, credit or rate limit hit | "Couldn't connect voice. Try again later." Typing still works | `voice_provider` (502), plus a `voice_provider_rejected` log line with the status and reason |

### OpenRouter (https://openrouter.ai)

1. **Credits → top up**, then turn on **auto top-up**. Pick a threshold and amount you're happy to have charged without warning. This is the one that takes the whole app down if it hits zero.
2. **Keys → Create key**, named `drillbit-production`.
   - Give it its own **credit limit**, high enough not to trip during launch. It's a guard against a runaway loop, not a budget. Something like $100 a month is a sane start; check after week one.
   - Keep the existing development key at its $20 limit. That way development runs can't eat production's money.
3. **Store the new key:** `./node_modules/.bin/wrangler secret put OPENROUTER_API_KEY --env production`, then paste the key when asked. No redeploy needed; secrets apply straight away.
4. **Settings → Privacy:**
   - Turn off training on your inputs, and turn off input/output logging. The privacy policy (`apps/api/src/legal.ts`) says content only goes to providers to produce a response.
   - If you turn on a stricter filter (zero data retention only, or blocking providers), check right after that typed reps still work. If no allowed provider serves `deepseek/deepseek-v4.1-flash` or `openai/gpt-6-luna`, every request fails with `managed_policy_blocked`.
5. **Revoke the old production key** once step 7 below passes, if it's a different key from the development one.

### OpenAI (https://platform.openai.com)

1. **Settings → Projects → Create project**, named `drillbit-production`. Keep development on its own project, so spend and limits are separate.
2. **In that project, create an API key** (service account or your own).
   - Simplest is permissions **All**.
   - If you restrict it instead, test voice straight after, because the live sessions endpoint has to be allowed.
3. **Project → Limits:**
   - Allow only `gpt-live-1`, so a leaked key can't be used for anything else.
   - Set a **monthly budget** with an email alert at about 50% and 80%.
4. **Billing:** add prepaid credit and turn on **auto recharge**.
5. **Limits → rate limits:** check the requests-per-minute and tokens-per-minute for `gpt-live-1` on your usage tier, because that caps how many people can talk at once. A new account starts on a low tier and moves up with spend. If the numbers look tight for launch, add credit early to move up.
   - Voice usage caps for sizing: Pro is up to 60 minutes a day and 75 a week; Free gets one 10-minute mock.
6. **Store the new key:** `./node_modules/.bin/wrangler secret put OPENAI_API_KEY --env production`.
7. **Settings → Data controls:** check that sharing with OpenAI for training is off at the organization level. Sessions are already created with `store: false`.

### Check production (both providers)

1. **Watch the logs:** in one terminal, run `./node_modules/.bin/wrangler tail drillbit-api --format pretty` from `apps/api`.
2. **Do one typed rep on your phone** (build 24, production): start a question, answer twice, end it and wait for feedback.
   - The tail should show `inference_first_text` lines and no `managed_*` errors.
3. **Do one voice rep:** talk for a minute, then end it.
   - Look for any `voice_provider_rejected` line in the tail.
   - Look for usage on the `drillbit-production` project in the OpenAI dashboard. It can take a few minutes to appear.
4. **Check the OpenRouter activity page:** the requests should be on the `drillbit-production` key.
5. **Check Sentry** (`drillbit-api` and `drillbit-ios`): no new issues from the run.
6. **Revoke the old keys** in both dashboards once all of the above is clean.

When this is done, add a dated line to `docs/operations.md` saying which keys production uses (names only, never the keys).

## Owner: confirm customers get Pro and you get paid (after approval)

Written 10 November 2026, after 1.0 (24) was approved. Pro is sold only through Apple (StoreKit subscriptions `dawi.drillbit.pro.weekly` and `dawi.drillbit.pro.yearly`). The production Worker grants Pro from Apple-signed transactions: the app sends one to `/v1/entitlement` right after a purchase, and Apple's webhook `/apple/notifications` keeps renewals, cancellations and refunds in step.

**Checked from the repo on 10 November:**
- Production's bundle ID and product IDs match the app.
- Both endpoints are up: `/health` returns ok, and `/apple/notifications` rejects junk with 400.
- Production D1 has no real purchases yet, only your manual Pro override.
- The app wasn't on the App Store yet: the lookup by ID found nothing and the store page returned 404.

### 1. App Store Connect (5 minutes)

1. **Business** (Agreements, Tax, and Banking):
   - the **Paid Apps** agreement is **Active**;
   - the bank account and tax forms show no warnings.

   Without an active agreement, the subscriptions don't sell at all.
2. **Apps → Drillbit Practice → App Information → App Store Server Notifications:**
   - the **Production** URL and the **Sandbox** URL are both `https://api.drillbit.t23.dev/apple/notifications`;
   - both are set to **Version 2**.

   Without this, new purchases still unlock Pro, but cancellations and refunds never reach the server, so people keep Pro.
3. **Distribution → iOS App 1.0:**
   - if it says **Pending Developer Release**, press **Release This Version**;
   - **Subscriptions** shows both plans as **Approved**.

### 2. One real purchase (once the App Store page is live)

TestFlight and Xcode builds always buy in the sandbox. Only the App Store build charges real money.

1. **Prepare the phone:** on the iPhone, go to **Settings → Developer → Sandbox Apple Account** and sign out, so the purchase uses your real Apple ID. Delete the TestFlight build, then install Drillbit from the App Store.
2. **Use a fresh account:** sign in with an account that isn't your owner account. That one already has Pro through the manual override, so the purchase would prove nothing.
3. **Watch the logs:** in a terminal, run `./node_modules/.bin/wrangler tail drillbit-api --format pretty` from `apps/api`.
4. **Buy:** see Pro, then buy **weekly**, which charges the $1.99 first week.
   - The app turns Pro without a relaunch.
   - The tail shows an `apple_notification` line with `SUBSCRIBED`. That proves the webhook is wired up. `applied` can be `false` if Apple's notification beat the app's own report, which is fine.
5. **Check the database row:** run `./node_modules/.bin/wrangler d1 execute drillbit-production --remote --env production --command "SELECT product_id, status, active_until FROM entitlements WHERE environment='Production'"`. It should show one active weekly row.
6. **Check cancelling:** cancel in **Settings → Manage subscription**.
   - The tail shows `DID_CHANGE_RENEWAL_STATUS` with `applied: true`.
   - Pro stays until the week ends.
7. **Optional, check refunds:** request a refund at https://reportaproblem.apple.com. When Apple approves it (hours to days), a `REFUND` notification turns the account back to Free.

### 3. The money

**Sales and Trends** shows the sale the next day. Apple pays out monthly, roughly 33 days after the end of its fiscal month, once you're over the payment threshold. Check **Payments and Financial Reports**.

### Known trade-off

Production also accepts sandbox purchases, because App Review buys in the sandbox. A TestFlight tester's sandbox purchase therefore gives Pro on production for free, but sandbox subscriptions stop renewing after a few hours. Keep it this way while App Review checks updates.
