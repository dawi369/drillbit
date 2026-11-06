# App Store readiness

Status, 4 November 2026: **App Privacy is published; version 1.0 is still missing from the review draft. Physical-device acceptance remains unrecorded.** The live listing already describes three lifetime free questions and one voice mock. See [the current audit](apple-review-audit-2026-11-04.md) for verified portal findings and remaining work. This checklist does not authorize submitting or releasing the app.

Verification is reported in three levels, as the release gate in [operations.md](operations.md#release-gate) requires:

| Level | Status |
| --- | --- |
| Compiled and tested (simulator, D1) | 58 Swift core tests passed on 4 November. Older simulator/D1 evidence is dated below; it is not a fresh acceptance run. |
| Live-service verified | Production Worker serving real traffic: on 31 October, D1 recorded completed question, interview, feedback and voice jobs and one Sandbox entitlement (now expired). |
| Physical-device verified | **Not recorded.** The 31 October production activity suggests a phone signed in and bought in Sandbox, but section 7's checklist hasn't been written up. |

## What changed in this pass

| Fix | Why review would fail without it |
| --- | --- |
| `PrivacyPolicyURL` is now copied into Info.plist (`project.yml`). Before this, `PRIVACY_POLICY_URL` never reached the app, so the paywall and Settings had no privacy link in any build. | 3.1.2: subscription apps need a working privacy link in the app. |
| Release builds fail if `PRIVACY_POLICY_URL` isn't an `https://` URL. | Stops the mistake above from coming back. |
| Third-party AI disclosure and consent, asked just in time: a sheet ("Bit runs on outside AI." → **Sounds good** / Not now) the first time a question would be written or an interview opened, and the API client refuses every AI route until it's given. No automatic generation runs without it. Settings → Legal → AI and your data shows the same words any time. Screenshots for the review notes: `review-ai-consent-first-question.png`, `review-ai-consent-returning.png`, `review-ai-data-settings.png` in `docs/design/app-store/`. | 5.1.2(i), Nov 2025: you must name third-party AI and get explicit permission before any data is sent to it. |
| `OPEN_SIGNUP=true` in production: new accounts are active without an invite. Development stays invite-only. | 2.1: reviewers can't use an invite-only app with no code, and paying customers can't either. |
| Privacy policy and support pages served by the Worker at `/privacy` and `/support` (`apps/api/src/legal.ts`), contact `support@t23.dev`. | App Store Connect requires both URLs. |

The privacy policy is a standard template matched to what the app actually does: what's collected, OpenRouter/OpenAI/Clerk/Cloudflare/Apple/Superwall as processors, deletion, no tracking. **It's not legal advice.** Read it at `/privacy` and have someone qualified check it if you sell in the EU or California. If the product changes, update `legal.ts`, `PrivacyInfo.xcprivacy` and the App Privacy answers (section 4) together.

## 1. Production backend: done

Clerk production (`clerk.drillbit.t23.dev`, Apple only) and the Worker (`https://api.drillbit.t23.dev`, cron on) are live; details are in [operations.md](operations.md#production-provisioned--28-october-2026). Both AI keys are set (`wrangler secret list --env production`, checked 1 November), and production D1 shows completed question, interview, feedback and voice jobs from 31 October. To rotate a key:

```sh
cd apps/api
./node_modules/.bin/wrangler secret put OPENROUTER_API_KEY --env production   # new key, $100 monthly limit
./node_modules/.bin/wrangler secret put OPENAI_API_KEY --env production       # voice
```

**Check:** `curl https://api.drillbit.t23.dev/health` → 200. Then on a phone, a first question generates (OpenRouter) and Talk connects (OpenAI).

## 2. Release build: one command

Production values are committed in `apps/ios/Config/Production.xcconfig`, and every Release build uses them. Bump `CURRENT_PROJECT_VERSION` in `apps/ios/project.yml` for each upload. Build 17 uploaded successfully on 4 November at 22:37 CET; Apple processing was pending at upload completion. Use a number above 17 for the next upload after checking the portal. `MARKETING_VERSION` is `1.0`, matching the version record in App Store Connect; keep them equal. Then run the release script. Signing requires the login keychain to be available to that session; a signed archive succeeded from the agent session on 4 November:

```sh
scripts/release-ios.sh            # archive and verify: production API, pk_live key, privacy URL
scripts/release-ios.sh --upload   # the same, then upload to App Store Connect
```

The script stops if the archive doesn't point at production. It exports with [`scripts/ExportOptions-AppStore.plist`](../scripts/ExportOptions-AppStore.plist). Earlier internal uploads used `testFlightInternalTestingOnly`, and builds made that way can't be submitted.

**Check:** the build appears under App Store Connect → TestFlight after processing.

## 3. Subscriptions in App Store Connect (you)

The paywall reads everything from the products, so nothing in code changes with prices.

1. **Agreements, Tax and Banking:** the Paid Apps agreement must be active, or products never load and review rejects the paywall as broken.
2. Subscription group **Drillbit Pro** with:
   - `dawi.drillbit.pro.yearly`: 1 year.
   - `dawi.drillbit.pro.weekly`: **$7.99** a week, with an introductory offer of 1 week at **$1.99**, pay as you go.
   - `dawi.drillbit.pro.yearly`: **$99.99** a year (raised from $79.99 on 31 October). The paywall shows "Save 75%" and "$1.92 a week"; `Config/Drillbit.storekit` uses the same prices for the simulator. If yearly is already set at $79.99 in App Store Connect, change it under Subscription Prices before submitting.
   - Prices and caps are explained in [paywall-plan.md](paywall-plan.md).
3. For each product: display name, description (e.g. "More reps and voice, billed weekly. Fair use applies."), and a **review screenshot** of the paywall. Take it on the device with the TestFlight build (section 7): the simulator fixture paywall shows a debug-only "Simulate purchase" button.
4. **The first subscription has to be submitted with an app version.** The current shared review draft already contains both products and their group, all Ready for Review. Add version 1.0 to that same draft after choosing the release build; the portal currently refuses submission because no app version is included. Do not submit subscriptions alone.
5. App Information → **App Store Server Notifications**: Production and Sandbox URL `https://api.drillbit.t23.dev/apple/notifications`, Version 2. Leave `APPLE_ENVIRONMENT` unset on production; App Review buys with Sandbox accounts against your production Worker.

What the paywall already does for Guideline 3.1.2 (no work needed; listed so you can answer reviewer questions):
- There are two places to buy, and both carry every disclosure: the Pro sheet (Home, Settings, voice, the first-rep offer) and the Bit tab's showcase for free accounts (`ProShowcase.swift`). Apple allows several purchase screens; each one has to stand on its own.
- Shows each plan's name, period and full billed price. Weekly comes first and is selected; the billed price ($7.99 / week, $99.99 / year) is always the largest figure, as App Review expects. The yearly per-week figure is secondary.
- Shows the intro offer as "$1.99 to start, then $7.99 a week", a "First week $1.99" tag, "First week $1.99, then $7.99 a week. Auto-renews." above the button, and "Start for $1.99". The Bit tab adds a "How your first week works" timeline (Today, Day 8, Anytime). The intro only shows to accounts Apple says are eligible.
- Plans and offers are matched by length in days, because the App Store can report a week as seven days (seen in the sandbox on 3 November).
- Has Restore Purchases, Terms of Service (Apple's standard EULA) and Privacy Policy links, plus a clear Not now.
- Settings has Plan, See Pro or Manage subscription, Terms and Privacy. Restore lives on the paywall (Settings → See Pro → Restore).
- The Worker unlocks Pro only from Apple-signed transactions (`POST /v1/entitlement`) and keeps it current from Apple's notifications.

## 4. App Privacy ("nutrition label") answers

Match `apps/ios/Drillbit/PrivacyInfo.xcprivacy`. Tracking: **No**. For every type below: *Linked to the user: Yes* (except Diagnostics and Customer Support, which are not linked), *Used for tracking: No*, *Purpose: App Functionality*.

| Category | Type | Why |
| --- | --- | --- |
| Contact Info | Email Address | Sign in with Apple/Google/GitHub via Clerk |
| Identifiers | User ID | Account id |
| User Content | Audio Data | Live voice streams to OpenAI; voice notes sent from Settings → Feedback are stored for the developer (App Functionality covers customer support) |
| User Content | Other User Content | Answers, transcripts, learning plan |
| Purchases | Purchase History | Subscription verification |
| Usage Data | Product Interaction | Rep and voice counts for plan limits |
| Diagnostics | Crash Data | Sentry crash reports. **Linked: No** |
| Diagnostics | Performance Data | Sentry app-hang reports. **Linked: No** |
| Diagnostics | Other Diagnostic Data | Device model, OS and app version on Sentry reports. **Linked: No** |
| User Content | Customer Support | Bug reports typed in Settings → Feedback, sent to Sentry. **Linked: No** |

Privacy Policy URL: `https://api.drillbit.t23.dev/privacy`.

## 5. Paywall: native StoreKit vs Superwall

**Production keeps `SUPERWALL_API_KEY` empty.** The Pro sheet uses Apple's `SubscriptionStoreView` with a custom `PlanPicker`; the free Bit tab has its own `ProShowcaseView`. Both purchase surfaces need current-device verification of prices, introductory terms, Restore, Terms and Privacy. Earlier simulator purchase tests do not establish App Review readiness.

If you want Superwall at launch instead:
- Create placements `practice_rep` and `voice_session` and attach one paywall with both products.
- The remote paywall must show, by itself: price and period for each plan, intro-offer terms, Restore, and links to Terms (`https://www.apple.com/legal/internet-services/itunes/dev/stdeula/`) and Privacy (`https://api.drillbit.t23.dev/privacy`). Reviewers reject Superwall templates that hide these or make the close button hard to find.
- Add Superwall to the App Privacy answers if you enable its analytics.
- Test on device with a Sandbox tester before submitting.

## 6. Store listing (you, with drafts here)

| Field | Draft |
| --- | --- |
| Name (30) | **Drillbit: System Design Prep** (28). Saved today: Drillbit Practice. |
| Subtitle (30) | **AI Mock Interviews for SWEs** (27). Saved today: System design interview prep. |
| Category | Education (secondary: Productivity) |
| Support URL | `https://api.drillbit.t23.dev/support` |
| Privacy Policy URL | `https://api.drillbit.t23.dev/privacy` |
| Copyright | 2026 t23.dev |
| Age rating | Fill in the 2025 questionnaire honestly. Drillbit has an AI chat feature (the interviewer) that's limited to system design practice. It has no user-to-user communication, no web browsing and no mature content. Expect 13+. Set a higher minimum age if you want. |

**Keywords (100):** `software,engineer,coding,developer,backend,architecture,distributed,scalability,practice,coach,sde` (98). No word repeats the name or subtitle (Apple combines all three, so a repeat is a wasted slot), everything is singular (plurals match automatically) and there are no spaces after commas. "faang" is gone: it spells out Apple, Amazon and Meta, and Guideline 2.3.7 bans other companies' names in keywords. Checked 6 November with the before.click ASO skill; for "system design interview" the top results mostly have under 100 ratings, so the exact phrase belongs in the name.

**Promotional text:** Your answer is the start. Practise system design with an AI interviewer that pushes back, shows you what to fix, and helps the lesson stick.

**Description:**

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

State the actual allowance in listing copy: Pro has fair-use caps (10 practised reps a day, where a rep counts from its second message; voice 60 minutes a day, 75 a week, 20 a session). Unqualified "unlimited" claims invite a 2.3.1 accuracy rejection.

**Screenshots:** upload the five captioned images in [`docs/design/app-store/2026-11-06-pro/ready/`](design/app-store/2026-11-06-pro/ready/), in order, to the 6.9" (1320 × 2868) slot; App Store Connect scales them into the required 6.3" slot. They replace the six 29 October screenshots still in App Store Connect. All five show the app in use (5 of 5; App Review needs more than half). The app is iPhone-only, so there's no iPad set.

| # | File | Headline |
|---|---|---|
| 1 | `01-interview.png` | Get better at system design. |
| 2 | `02-feedback.png` | Know what worked. Know what to fix. |
| 3 | `03-example.png` | Stuck? See one worked example. |
| 4 | `04-knowledge-map.png` | See what you actually know. |
| 5 | `05-recall.png` | Make the lesson stick. |

A live voice frame from a phone would make a strong sixth (or first) image later; the simulator can't take it. How the set was made and regenerated: [its README](design/app-store/2026-11-06-pro/README.md). The subscription review image is [`review-paywall.png`](design/app-store/review-paywall.png) (regenerated 6 November: weekly first, $1.99 first week, $99.99 a year).

**App icon:** a layered Icon Composer icon, [`apps/ios/Drillbit/AppIcon.icon`](../apps/ios/Drillbit/AppIcon.icon), from build 20. iOS draws its Dark, Clear and Tinted looks from the layers; `scripts/generate-app-icon.swift` renders them, and `ictool` (inside Icon Composer) previews each look.

**App Review notes (paste and fill in):**

> Sign in with Apple to create an account; no invite or demo code is needed. The first launch shows a short intro and a one-minute setup, then sign-in. Before the first question is written, a sheet asks permission to use third-party AI (OpenRouter for text, OpenAI for voice); nothing is sent to an AI model before that. Settings → AI and your data shows the same words any time. Screenshots of the permission sheet are attached.
>
> Subscriptions: free accounts get three questions in total and one voice mock of up to 10 minutes. To reach the paywall, use Settings → See Pro, or use the three free questions. Restore Purchases is on the paywall (Settings → See Pro).
>
> Voice: open a question and tap Talk, then tap the microphone to unmute. Microphone permission is requested then. Free accounts get one voice mock of up to 10 minutes; it counts once they speak.
>
> Account deletion: Settings → Delete account.
>
> Contact: support@t23.dev

Don't provide a demo account unless review asks for one: Sign in with Apple creates one in seconds, and a shared account would carry someone else's history.

## 7. Physical-device acceptance (you, about 45 minutes; required before submitting)

Install the production build on an iPhone signed into a **Sandbox** Apple ID (Settings → Developer → Sandbox Apple Account): either from TestFlight, or straight from the Mac with `scripts/install-ios-device.sh`, run from the Mac's own Terminal. Then go through:

- [ ] Fresh install → intro → setup → Sign in with Apple → AI consent sheet → first question generated
- [ ] Only Sign in with Apple is offered (Google and GitHub come back once production OAuth apps exist in Clerk)
- [ ] Answer, follow-up, nudge, Finish → feedback
- [ ] Voice: microphone prompt, live conversation, back to text with the draft intact; a free account stops at the cap
- [ ] Use all three free reps → Home shows the paywall nudge → See Pro → paywall shows real prices and intro offer → buy weekly → Pro without relaunch
- [ ] Free account → Bit tab → showcase shows real prices, "First week $1.99" and the timeline → Restore, Terms and Privacy open → buying turns the tab into the map
- [ ] Delete and reinstall → sign in → See Pro → Restore → Pro
- [ ] Settings → Manage subscription opens Apple's sheet; cancel there and check that the plan returns to Free after expiry (sandbox weeks last minutes)
- [ ] `SELECT * FROM entitlements` in production D1 shows the row with `environment = Sandbox`
- [ ] Airplane mode mid-answer → draft kept → reconnect → syncs
- [ ] Widget shows today's question after a cold launch
- [ ] Settings → Delete account → signed out; signing in again is a fresh account
- [ ] VoiceOver and the largest Dynamic Type size on Welcome, consent, paywall and the interview

Record the results in [operations.md](operations.md) under a new dated heading, like the earlier TestFlight builds.

## 8. Submit

Version 1.0 → choose the build → attach both subscriptions → add the review notes → Submit. Usual first-review questions and answers:

- *"What data goes to the AI?"* The consent screen and the privacy policy list it. Answers and transcripts go to OpenRouter models, live audio to OpenAI, and no email address is sent.
- *"Why is there a camera string?"* The bundled WebRTC framework links camera APIs. Drillbit never asks for camera access. The string says so.
- *"Is BYOK an IAP bypass?"* The provider-key setting is only shown to developer accounts, and production has none.

## Known limits (documented, not blockers)

- AI consent is stored in the device's Keychain, not the account. A reinstall keeps it, like the sign-in session; a new device asks again.
- Voice sessions can't be closed from the server; the client deadline and event rejection bound cost to the session cap. A close counts at least the time since start, but a modified app that closes early while keeping the provider connection open isn't caught (paywall-plan.md section 14).
- A refund or revocation takes effect when Apple's notification arrives; until then the user keeps Pro.

## Test evidence

27–28 October 2026. Each line is the exact command and its result.

| Check | Command | Result |
| --- | --- | --- |
| API types | `bun run typecheck` | Passed |
| API + D1 (Workers runtime) | `bun run test` | **164/164 passed**, 16 files. New: open signup activates new and waiting accounts, never revives `deleting` under concurrent sign-ins, one account when first sign-ins race; public `/privacy` and `/support`; reinvite refused with open signup |
| Contract drift | `bun run contracts && git diff --exit-code -- packages/contracts` | No drift |
| Swift core | `swift test --package-path apps/ios -j 2` | **54/54 passed** |
| Simulator: every unit and UI journey | `xcodebuild … -destination 'platform=iOS Simulator,id=32C4E22D…' test` (iPhone 17, iOS 27) | **142/142 passed**: onboarding, AI consent (three paths), interview, voice room (fixture), library, recall, settings, paywall gate → StoreKit prices → purchase → unlock, restore/terms/privacy, Dynamic Type AX-XXXL, light and dark, reduced motion, offline settings |
| Second screen size | Seven journeys, including the paywall and walkthrough, on an iPhone 17 Pro Max (6.9") | Passed |
| Release build | `xcodebuild -configuration Release … build` | Builds; `PrivacyPolicyURL` embedded. With `PRIVACY_POLICY_URL=` the build fails with the guard's message, as intended |
| Live development Worker | `curl` against `drillbit-api-development` after deploying `c9bf49e2` | `/health` 200, unauthenticated `/v1/bootstrap` 401, `/privacy` and `/support` 200 with `support@t23.dev`, forged Apple notification 400 |

Four existing UI scripts were stale and failed on their first run; none was an app bug. Two screenshot walks typed while the second coach tip deliberately shielded the screen. The Settings walk looked for Delete account in the wrong scroll direction. The profile test didn't scroll to a row that moved under Developer. All four were fixed and pass.

**Historical scope of the 27–28 October tests:** they did not verify production authentication, live providers, Sandbox purchase/restore/notifications, or physical-device behavior. Production was subsequently provisioned and later service evidence is recorded above and in operations. The complete physical-device checklist in section 7 still has no recorded result.
