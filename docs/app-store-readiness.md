# App Store readiness

Status, 27 October 2026: **the app code is ready for review; the production environment and App Store Connect aren't.** Everything below that says *you* needs an account, a dashboard or a real iPhone. Work through the sections in order. Each one says how to check it's done.

Verification is reported in three levels, as the release gate in [operations.md](operations.md#release-gate) requires:

| Level | Status |
| --- | --- |
| Compiled and tested (simulator, D1) | Done this pass. See [Test evidence](#test-evidence). |
| Live-service verified | Development Worker only. Production doesn't exist yet. |
| Physical-device verified | **Not done.** Needs you with a Sandbox tester (section 7). |

## What changed in this pass

| Fix | Why review would fail without it |
| --- | --- |
| `PrivacyPolicyURL` is now copied into Info.plist (`project.yml`). Before this, `PRIVACY_POLICY_URL` never reached the app, so the paywall and Settings had no privacy link in any build. | 3.1.2: subscription apps need a working privacy link in the app. |
| Release builds fail if `PRIVACY_POLICY_URL` isn't an `https://` URL. | Stops the mistake above from coming back. |
| Third-party AI disclosure and consent before sign-in ("Before we start: Bit runs on outside AI." → **Sounds good**). Anyone already signed in without it sees the same disclosure before Home, and no automatic generation runs first. Settings → Legal repeats it in a footer. | 5.1.2(i), Nov 2025: you must name third-party AI and get explicit permission before any data is sent to it. |
| `OPEN_SIGNUP=true` in production: new accounts are active without an invite. Development stays invite-only. | 2.1: reviewers can't use an invite-only app with no code, and paying customers can't either. |
| Privacy policy and support pages served by the Worker at `/privacy` and `/support` (`apps/api/src/legal.ts`), contact `support@t23.dev`. | App Store Connect requires both URLs. |

The privacy policy is a standard template matched to what the app actually does: what's collected, OpenRouter/OpenAI/Clerk/Cloudflare/Apple/Superwall as processors, deletion, no tracking. **It's not legal advice.** Read it at `/privacy` and have someone qualified check it if you sell in the EU or California. If the product changes, update `legal.ts`, `PrivacyInfo.xcprivacy` and the App Privacy answers (section 4) together.

## 1. Production backend: done 28 October except the AI keys

Clerk production (`clerk.drillbit.t23.dev`, Apple only) and the Worker (`https://api.drillbit.t23.dev`, cron on) are live; details are in [operations.md](operations.md#production-provisioned--28-october-2026). Still needed:

```sh
cd apps/api
./node_modules/.bin/wrangler secret put OPENROUTER_API_KEY --env production   # new key, $100 monthly limit
./node_modules/.bin/wrangler secret put OPENAI_API_KEY --env production       # voice
```

**Check:** `curl https://api.drillbit.t23.dev/health` → 200. Then on a phone, a first question generates (OpenRouter) and Talk connects (OpenAI).

## 2. Release build: one command

Production values are committed in `apps/ios/Config/Production.xcconfig`, and every Release build uses them. Bump `CURRENT_PROJECT_VERSION` in `apps/ios/project.yml` for each upload (13 is next). `MARKETING_VERSION` is `1.0`, matching the version record in App Store Connect; keep them equal. Then, **in your own Terminal** (an agent or SSH shell can't reach the signing key):

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
   - `dawi.drillbit.pro.yearly`: **$79.99** a year. The paywall shows "Save 80%" and "$6.67 a month"; `Config/Drillbit.storekit` uses the same prices for the simulator.
   - Prices and caps are explained in [paywall-plan.md](paywall-plan.md).
3. For each product: display name, description (e.g. "Unlimited reps and voice, billed weekly."), and a **review screenshot** of the paywall. Take it on the device with the TestFlight build (section 7): the simulator fixture paywall shows a debug-only "Simulate purchase" button.
4. **The first subscription has to be submitted with an app version.** On the 1.0 version page, under *In-App Purchases and Subscriptions*, add both products before you press Submit. Otherwise they stay "Ready to Submit" and the reviewer sees an empty paywall.
5. App Information → **App Store Server Notifications**: Production and Sandbox URL `https://<prod-host>/apple/notifications`, Version 2. Leave `APPLE_ENVIRONMENT` unset on production; App Review buys with Sandbox accounts against your production Worker.

What the paywall already does for Guideline 3.1.2 (no work needed; listed so you can answer reviewer questions):
- Shows each plan's name, period and full price. The yearly price comes first and is bigger than the per-month figure.
- Shows the intro offer as "Try a week for $X, then $Y a week".
- Has Restore Purchases, Terms of Service (Apple's standard EULA) and Privacy Policy links, plus a clear Not now.
- Settings has Plan, See Pro or Manage subscription, Terms and Privacy. Restore lives on the paywall (Settings → See Pro → Restore).
- The Worker unlocks Pro only from Apple-signed transactions (`POST /v1/entitlement`) and keeps it current from Apple's notifications.

## 4. App Privacy ("nutrition label") answers

Match `apps/ios/Drillbit/PrivacyInfo.xcprivacy`. Tracking: **No**. For every type below: *Linked to the user: Yes*, *Used for tracking: No*, *Purpose: App Functionality*.

| Category | Type | Why |
| --- | --- | --- |
| Contact Info | Email Address | Sign in with Apple/Google/GitHub via Clerk |
| Identifiers | User ID | Account id |
| User Content | Audio Data | Live voice streams to OpenAI |
| User Content | Other User Content | Answers, transcripts, learning plan |
| Purchases | Purchase History | Subscription verification |
| Usage Data | Product Interaction | Rep and voice counts for plan limits |

Privacy Policy URL: `https://<prod-host>/privacy`.

## 5. Paywall: native StoreKit vs Superwall

**Recommendation: launch with `SUPERWALL_API_KEY` empty.** The app then shows Apple's `SubscriptionStoreView` with the plan picker. It's tested in the simulator (real StoreKit products, gate → paywall → purchase → unlock), compliant by construction, and doesn't depend on a remote dashboard the reviewer might catch half-configured.

If you want Superwall at launch instead:
- Create placements `practice_rep` and `voice_session` and attach one paywall with both products.
- The remote paywall must show, by itself: price and period for each plan, intro-offer terms, Restore, and links to Terms (`https://www.apple.com/legal/internet-services/itunes/dev/stdeula/`) and Privacy (`https://<prod-host>/privacy`). Reviewers reject Superwall templates that hide these or make the close button hard to find.
- Add Superwall to the App Privacy answers if you enable its analytics.
- Test on device with a Sandbox tester before submitting.

## 6. Store listing (you, with drafts here)

| Field | Draft |
| --- | --- |
| Name | Drillbit Practice (the App Store record; the home screen still says Drillbit) |
| Subtitle (30) | Rehearse the system design interview |
| Category | Education (secondary: Productivity) |
| Support URL | `https://<prod-host>/support` |
| Privacy Policy URL | `https://<prod-host>/privacy` |
| Copyright | 2026 t23.dev |
| Age rating | Fill in the 2025 questionnaire honestly. Drillbit has an AI chat feature (the interviewer) that's limited to system design practice. It has no user-to-user communication, no web browsing and no mature content. Expect 13+. Set a higher minimum age if you want. |

**Keywords (100):** `system design,interview,mock interview,software engineer,coding interview,faang,backend,architecture,prep`

**Promotional text:** Hard questions. Good company. An AI interviewer you can think out loud with, in text or voice.

**Description:**

> The coding round gets you a callback. The design round gets you hired.
>
> Drillbit puts you in the system design interview. You get one real question scoped to your level, from Intern to Principal, and an interviewer who reacts to what you actually said. Write your answer or talk it through out loud. Ask for a nudge when you're stuck. Change your mind halfway. That's the point.
>
> • One question at a time, with clear requirements and room to push back
> • Follow-ups that respond to your reasoning, not a checklist
> • Live voice that continues the same interview, with your draft intact
> • Feedback that quotes your own words: one thing that worked, one thing to fix
> • Recall cards and a library of everything you've practiced
>
> Free: 3 questions a day and a taste of voice. Drillbit Pro: practice as much as you like and use voice any time (fair use applies). Pro renews automatically unless you cancel at least 24 hours before the period ends. Manage or cancel in your Apple ID settings.
>
> Drillbit uses third-party AI (OpenRouter and OpenAI) to run interviews. It asks before anything is sent.
>
> Terms of Use: https://www.apple.com/legal/internet-services/itunes/dev/stdeula/
> Privacy Policy: https://<prod-host>/privacy

Keep "fair use applies" next to "as much as you like": Pro has fair-use caps (30 reps a day; voice 60 minutes a day, 150 a week, 20 a session). Unqualified "unlimited" claims invite a 2.3.1 accuracy rejection.

**Screenshots:** iPhone 6.9" (1320 × 2868) is required, and the app is iPhone-only, so there's no iPad set. Six are ready in [`docs/design/app-store/`](design/app-store/): welcome, interview, example, Home, Recall and Library, in that order. They're generated from fixtures as a customer account, so there's no developer tab. To regenerate after UI changes, boot an iPhone 17 Pro Max simulator, run `xcrun simctl status_bar <udid> override --time 9:41 --batteryState charged --batteryLevel 100`, then run `-only-testing:DrillbitUITests/StoreScreenshots` and export the attachments (as `scripts/audit-shots.sh` does). Live voice is the headline feature but isn't in the set: the fixture voice room shows a debug "Simulate speech" link. Take that one on your phone during section 7 (a Pro Max, or scale to 1320 × 2868), mid-conversation with a caption showing. Add short captions in App Store Connect if you want, e.g. "An interviewer who pushes back", "Stuck? Ask for an example", "Recall what you learned".

**App Review notes (paste and fill in):**

> Sign in with Apple to create an account; no invite or demo code is needed. The first launch shows a short intro and a one-minute setup, then asks permission to use third-party AI (OpenRouter for text, OpenAI for voice) before sign-in.
>
> Subscriptions: free accounts get 3 questions per day. To reach the paywall, use Settings → See Pro, or finish 3 questions. Restore Purchases is on the paywall (Settings → See Pro).
>
> Voice: open a question and tap Talk. Microphone permission is requested then. Free accounts get 3 voice sessions.
>
> Account deletion: Settings → Delete account.
>
> Contact: support@t23.dev

Don't provide a demo account unless review asks for one: Sign in with Apple creates one in seconds, and a shared account would carry someone else's history.

## 7. Physical-device acceptance (you, about 45 minutes; required before submitting)

Install the production build on an iPhone signed into a **Sandbox** Apple ID (Settings → Developer → Sandbox Apple Account): either from TestFlight, or straight from the Mac with `scripts/install-ios-device.sh`, run from the Mac's own Terminal. Then go through:

- [ ] Fresh install → intro → setup → AI consent → Sign in with Apple → first question generated
- [ ] Only Sign in with Apple is offered (Google and GitHub come back once production OAuth apps exist in Clerk)
- [ ] Answer, follow-up, nudge, Finish → feedback
- [ ] Voice: microphone prompt, live conversation, back to text with the draft intact; a free account stops at the cap
- [ ] Use 3 reps → Home waits → See Pro → paywall shows real prices and intro offer → buy weekly → Pro without relaunch
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

- AI consent is stored on the device, not the account. A new device or reinstall asks again, even when the sign-in session survives; that's deliberate.
- Voice sessions can't be closed from the server; the client deadline and event rejection bound cost to the session cap.
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

**Not verified**, and can't be from here: real Sign in with Apple/Google/GitHub, live AI and voice through providers, a Sandbox purchase, restore and Apple notifications, production Worker and Clerk (not created yet), widget cold launch, and anything on a physical iPhone. That's sections 1 and 7.
