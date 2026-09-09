# Native rebuild acceptance — 8 September 2026

This is an implemented native application and development backend. It is **not yet a signed, end-to-end accepted TestFlight release**. Configuration and physical-device checks below are release gates, not cosmetic polish.

## Verified

- TypeScript compilation against the Worker bindings passes; frozen Bun installation and whitespace checks pass.
- All 20 Worker tests pass using real local D1 with mocked Clerk JWKS and model responses: account isolation, invitation gate, JWT audience, completion idempotency, revision rejection, one active question, generation replay, malformed AI output, bounded context, streamed framing/truncation, pagination and account deletion.
- All five Swift core tests pass on macOS and in the iPhone simulator. They exercise wire decoding, newer-edit acknowledgement, offline completion preservation, conflict recovery, device-token date parsing and minimal widget data.
- Final Debug simulator and unsigned Release iPhone builds pass, including the app icon and embedded widget. Xcode reports no compiler warnings in the final Debug/test logs. Fixture UI inspection covered Today → practice editor → local save → coaching sheet → return with answer retained. The final build reconfirmed entry/save. The initial CUA check could not activate Finish; the subsequent XCUITest pass below verifies completion through the native UI with fixture data.
- Development Worker, D1 and Workflow provisioned independently of other projects. Three database migrations applied. Deployed `/health` returns 200 and unauthenticated `/v1/bootstrap` returns 401 using curl.
- Remote D1 export restored into a separate local SQLite database; integrity check returned `ok`. This exercised schema restoration on the new development database, not recovery of production user data.
- Prior modified Expo source preserved in `legacy/expo` and a separate pre-rebuild snapshot. No commit, push or TestFlight upload performed.

## Required before distribution

- Verify both managed and encrypted BYOK paths through a real signed-in account. Managed provider generation was checked directly with the existing key; that does not verify the complete account-to-job flow.
- Run real iPhone acceptance: cold authentication, reconnect/airplane mode, force quit during a draft and completion, two-device revision conflict, rejected/replaced/removed BYOK, interrupted coach stream, widget refresh/deep link, denied reminders, background/foreground transitions, deletion and reinstallation.
- Check VoiceOver reading/focus, largest Dynamic Type, dark appearance, keyboard/dictation, long prompts and answers, and reduced motion. Simulator fixture inspection does not establish accessibility acceptance.
- Create a separate release environment, privacy policy/support URLs and App Store privacy declarations. Validate provider data handling and retention disclosures before inviting external testers.

## Operational limits

- Provider billing cannot be exactly once after ambiguous failures. App mutations are idempotent; provider attempts have a shared daily cap and workflow retries are bounded.
- WidgetKit, local reminders and background refresh do not guarantee an exact delivery time. Cloud scheduling remains authoritative.
- Failed account deletion requires operator attention while account access stays disabled.
- The OpenAPI contract is generated and bootstrap/history are contract-tested; Swift uses explicit Codable DTOs, not a generated client. Android UI is deferred.
- Prompt quality, memory-label consistency and coaching UX require real practice sessions. No readiness score or learning outcome is claimed.

## Reproducible evidence from this run

- Xcode 26.6 (17F113), iOS SDK 26.5; installed the matching available iOS 26.5 simulator component (23F77) to repair asset compilation.
- Development authentication configuration was completed after the initial rebuild; see the update below.
- Local logs: `/tmp/drillbit-target-build.log`, `/tmp/drillbit-device-build.log`, `/tmp/drillbit-ios-tests.log`, `/tmp/drillbit-core-tests.log`. These temporary logs are not repository artifacts.
- Deployed unauthenticated widget endpoint also returns 401. Real token/account/provider flows remain gated above.

## Authentication configuration update

- Clerk development application linked, native iOS registration/callback saved, and the `drillbit` JWT template created. Apple, Google and GitHub buttons use the native Clerk SDK.
- Real OpenRouter key validation passed. A live generation exposed a provider translating structured output into plain JSON mode; the adapter now includes explicit JSON/schema instructions and requires supported provider parameters. A subsequent live challenge passed schema validation. The regression test checks those request fields.
- All 20 backend tests, TypeScript checks and five iOS simulator tests passed after integration changes.
- Signed iPhone and signed Simulator builds passed. App signing uses team `7M4NDAAP73`; Keychain entitlement separation keeps Clerk credentials private to the app and widget tokens in the shared group.
- The signed Simulator launches with real Clerk configuration and displays Apple, Google and GitHub login controls without the unsigned-build Keychain assertion. Physical app signature verification passed.
- Development deployment `70678d58-6df6-408b-ba24-6ba0066cbba0` passed live health (200) and unauthenticated bootstrap (401) checks after the provider fix.
- First end-to-end user sign-in and physical-device practice acceptance are still required. No TestFlight upload occurred.

## Confirmed Apple cleanup

The user confirmed deletion of Assistant-MK1's App ID and App Store profile. Profile `WWS29A7F5J` (`*[expo] com.dawi369.assistantmk1 AppStore 2026-08-15T15:04:08.034Z`) was deleted and is absent from the profile list. Apple rejected removal of App ID `69Z6529R92` / `com.dawi369.assistantmk1` because it is in use by the App Store. The identifier remains. Shared certificates, the team-scoped Expo push key, and other applications were preserved. No Assistant-MK1 Services ID or App Group appeared in the inspected lists.

## Minimal UI pass

- Replaced the disconnected welcome layout with one heading, concise copy and equal-width provider buttons. Central semantic colours, regular/semibold system text, 12-point custom control corners and a 48-point minimum button height. Signing in disables duplicate requests and shows progress.
- Today and Memory use compact navigation titles. Main practice and reflection actions share the same neutral style. Coach opens at full sheet height.
- Fixed maximum Dynamic Type overflowing the practice viewport: accessibility text sizes open the question in a scrollable sheet, leaving the answer editor and coaching action available.
- Visually reviewed login in light/dark appearance and at maximum Dynamic Type. Inspected screenshots of Today, editor with keyboard, Coach, reflection, Memory, session detail, Settings and Focus on iPhone 17 Pro / iOS 26.5.
- Two XCUITest scenarios passed: the complete fixture practice/review flow including Settings and Focus navigation; and maximum-text-size question/editor navigation with hittable editor and coach controls. These run through native controls, including Finish. Source: `apps/ios/UITests/PracticeUITests.swift`.
- Signed simulator build and whitespace checks passed. Local result bundles: `/tmp/drillbit-ui-review-final.xcresult`, `/tmp/drillbit-ui-accessibility.xcresult`. Reviewed screenshots are copied into ignored `.local/ui-review/`. Simulator restored to normal text, light appearance and real sign-in.
- This is a bounded visual/interaction pass, not full accessibility certification. VoiceOver, smaller iPhones, widget presentation, live account flows and the other physical-device release gates remain unverified.

## Text practice implementation — 9 September 2026

- Implemented Solo/Coach/Guided with explicit help actions, a result-first help sheet, preserved native editor/keyboard behaviour, and disabled **Speak — In development**. No app microphone permission or voice transport was added.
- Implemented preparation with remembered focus/kind/difficulty and a one-off instruction, safe ready-question replacement, similar-question context, conservative assistance descriptions, frozen completion context, and previewed outline/example/draft adoption with append, replace, source history and revision-checked undo.
- Gemini 3.1 Flash Lite is the only model for managed and BYOK. Older preferences and queued settings normalize to that model. Action-specific schemas prevent hint/check/example responses from masquerading as draft suggestions. Evaluator criteria derive from visible requirements.
- **Backend:** TypeScript and all **31 tests** pass against local D1. Coverage includes authenticated wire responses, one-help enforcement, command replay/conflicts, concurrent adoption, stale insertion/undo, cross-account source rejection, Start versus replacement, cancellation, late help after Finish and immutable reflection context.
- **Native:** signed iOS Simulator build and **six native tests** pass. Three XCUITest journeys pass on iPhone 17 Pro / iOS 26.5: normal writing/help/review/history; maximum Dynamic Type question/editor access; Guided preview/replace/undo and disabled Speak. Checked rendered screenshots for keyboard layout, help, preview, review, Today and settings; also inspected dark Today. Final fixture screenshots are in `.local/ui-review/practice-v2/`; result bundles are `/tmp/drillbit-practice-final.xcresult` and `/tmp/drillbit-practice-unit-final.xcresult`.
- **Live provider:** eight action cases and six edge cases pass output schema and suggestion-field checks with the real configured OpenRouter key. Human review found remaining tone and factual-grounding issues, recorded in [prompt evaluation](prompt-evaluation.md). Passing these contracts is not a claim of model correctness.
- **Development service:** D1 was exported before migration 0004. Deployed help and question-generation Workflows completed with synthetic data and the new model; the isolated synthetic account was then deleted and absence verified. Latest Worker version `d6c468ca-2c46-4bbe-a502-eb429d08cb76` returns health 200 and unauthenticated bootstrap 401.
- **Handoff:** restored light appearance and launched the signed app without fixture arguments. The existing signed-in account successfully shows Today and its preserved in-progress rate-limiter practice, ready to Resume.

The new full practice flow has fixture UI coverage and live provider/workflow coverage, but has not been completed through a real signed-in client or on a physical iPhone in this pass. Full VoiceOver navigation, interrupted-network device testing, BYOK live generation and the previous TestFlight gates remain open. Live Speak, reliable selection replacement and immutable linked retries remain intentionally deferred. No TestFlight upload or git commit was made.

## Finish confirmation and companion council

Finish now opens “Finish practice?” with **Keep writing** and **Finish practice**. The signed simulator UI journey verifies that cancellation preserves the exact draft and does not complete the session, then verifies that confirmation reaches review. Test passed: `/tmp/drillbit-finish-confirmation.xcresult`; screenshot: `.local/ui-review/finish-confirmation.png`.

The new ambient Coach/Guided specification is documented in [companion vision](companion-vision.md). It is not yet implemented or covered by these tests. The pre-native backup directory contains `source.tar.gz`, `working-tree.patch` and `HEAD` (2.5 MB); it is preserved as recovery material, not an active second app.

## Contextual companion — 9 September 2026

Implemented: quiet Solo; one reserved bottom companion in Coach/Guided; independent blank/unchanged-answer pause; substantial-edit checks; explicit Guided entry; pause/resume and dismissal; contextual actions/plan/focus; existing insertion/undo and Finish confirmation. Migration 0005, additive contracts/fixtures, account-scoped recovery, local-generation freshness and conservative delivery freezing are integrated. Gemini 3.1 Flash Lite is still the sole model; Speak is disabled.

### Verified locally and in Simulator

- TypeScript typecheck, OpenAPI generation and **38 API tests** pass against the Cloudflare test D1 runtime. New cases cover competing requests, duplicate cycles, context revisions/mode epochs, cross-device consumed cycles, pause/cooldown/budget/capability, cosmetic changes and reversions, account-scoped receipts, stale completion and receipt/completion races. Existing stale adoption, job lifecycle and HTTP tests remain green.
- **12 native tests** pass in both the core test suite and signed simulator host. Coverage includes rewrites/deletions/cosmetic changes, four-second settling, independent blank pause, cooldown/budget, foreground reset, persisted consumed cycles, capture freshness, draft/outbox conflicts, pending completion and receipt acknowledgements preserving newer intent.
- **Five XCUITest journeys** pass: largest accessibility text; actual 30-second blank Coach pause; Guided preview/replace/undo with disabled Speak; meaningful-edit hint in dark mode with reduced effects; practice/help/review including Finish cancel and confirm.
- Pause and meaningful-edit tests assert unchanged editor frame. Blank-pause test also asserts the keyboard remains present and subsequent typing enters the same answer. These checks are not a measurement of every caret/viewport configuration.
- Exported screenshots were visually inspected in light/dark appearance, with keyboard visible/hidden and largest accessibility text. The initial largest-text overflow was found visually and fixed. Reduced-effects testing uses fixture overrides of the same panel branches; it is not an OS-level accessibility-setting verification.
- UI evidence: `.local/ui-review/companion-final/`; complete UI result `/tmp/drillbit-companion-verified.xcresult`. Final account/pending-completion changes compiled and passed native tests in `/tmp/drillbit-companion-shipping.xcresult`. The five full UI journeys precede those final nonvisual recovery changes.

### Live service and model evidence

- Development D1 exported to the ignored private file `.local/before-companion-20260909.sql`; migration `0005_companion.sql` applied successfully. Automatic help is enabled only through the development server capability flag; manual help remains usable when it is disabled.
- A synthetic account exercised a real deployed Cloudflare Workflow → Gemini → D1 companion result. It completed with a grounded blank-answer starting hint, no answer proposal and no Coach plan. The isolated synthetic account was subsequently deleted and absence verified. This is deployed workflow evidence, not a claim that every new authenticated HTTP path was manually exercised on a physical phone.
- Live Gemini evaluation included blank pause, correction, already-covered-answer silence, nonrepetition, Guided entry, selected focus and a full example. Initial outputs failed product review: invented requirements, Coach plans and overclaims about availability. Revised Coach schema/prompts produced useful opening/correction hints, `no_intervention` for covered requirements and a different relevant hint after earlier help.
- Guided is still a product-quality limitation: schema-valid outputs sometimes broaden the chosen focus or sound instructional rather than collaborative. The final example respected monotonic rollback generations and acknowledged residual client/cache failures. That small sample does not establish reliability across topics. Raw synthetic results are private in `.local/companion-model-evaluation*.json` and `.local/companion-guided-evaluation.json`; rerun with `bun scripts/check-companion-model.ts` / `--guided`.

### Remaining acceptance limits

Full VoiceOver navigation, physical-device keyboard dictation/IME composition, prolonged offline/competing-device interaction and long-answer viewport stress remain unverified manually. Marked-text and lifecycle suppression are implemented, but should not be described as physical-device verified. Expanded Guided focus and tone need further real practice evaluation. Live voice, selection-specific replacement and linked retry/revision attempts remain deferred by design.

Final development Worker version: `30e5032d-1481-4117-b790-43a12d1e29d5`. The synthetic Workflow check ran on the immediately preceding companion deployment; the final deployment additionally bounds older discussion context and normalizes silent outcomes. Final signed app was installed and launched without fixture arguments on iPhone 17 Pro (`27D30430-98BA-41DC-8696-08C61A440121`), showing the real signed-in Today screen. The UI-test runner was removed. No physical-device or TestFlight installation is claimed.

## Owner-only TestFlight distribution — 9 September 2026

Release archive and distribution upload succeeded for `dawi.drillbit`, version `2.0.0` build `1`. Live App Store Connect UI verifies **Testing**, **Internal**, and assignment to **Owner Testing** (one tester, one build); the account holder status is **Invited**. The store record is **Drillbit Practice** (`6810226020`), since “Drillbit” was unavailable. Installed display name remains Drillbit. This build requires iOS 26 and uses development services. No public App Store submission or external testing release was made. Physical iPhone installation and the device acceptance gates above remain pending user testing. See [operations](operations.md#first-internal-testflight-release--9-september-2026).

## Settings and engineering levels — 9 September 2026

Implemented: removed Settings footer; LLM provider naming; selected Focus preview with full accessibility label; six engineering levels in Settings/onboarding/preparation; curated searchable IANA timezones including saved/device zones. Saving preserves the chosen zone; local reminders now carry that timezone. Additive level contracts preserve old clients, map legacy snapshots and record levels on new questions without rewriting historical sessions.

- **41 API tests passed** against Cloudflare D1, including all six settings values, preservation on legacy updates, persisted timezone, old snapshot normalization and New York spring/fall DST plus Kolkata offset scheduling. TypeScript and OpenAPI generation passed.
- **13 native tests passed**, including level/settings encode-decode recovery and matching local reminder calendar components across DST.
- **Two new signed XCUITest journeys passed**: settings level/timezone/provider selection; largest accessibility text with full Focus accessibility label and scrollable editor, followed by onboarding with all six levels. The first accessibility test needed scrolling to discover the lazily rendered editor; the corrected journey passed. Screenshots: ignored `.local/ui-review/settings-levels/`. Results: `/tmp/drillbit-settings-ui.xcresult` and `/tmp/drillbit-settings-accessible-final.xcresult`.
- Visually inspected light Settings and dark onboarding/largest-text Settings/Focus screenshots. These are accessibility-tree and Dynamic Type checks, not a manual spoken VoiceOver traversal. Physical-device notification delivery and timezone travel behavior remain unverified.
- **Live Gemini:** two six-level synthetic samples on Backend caching passed schema checks. Product review caught unrealistic consistency/latency demands and weak Staff/Principal distinction in the first batch; revised generation instructions improved the second batch to cross-team ownership and multi-year regional decisions. Intern/Junior overlap and Senior consistency wording still warrant ongoing prompt tuning; one sample per level is not calibration proof. Latest outputs: ignored `.local/practice-model-levels.json`; repeat with `scripts/check-practice-model.ts --levels`.
- Compatible development backend deployed as `1d798d23-25d4-457d-a36e-a68b2e6a9ecf`; health HTTP 200, unauthenticated bootstrap HTTP 401. No schema migration was required.

Release verification: signed `2.0.0 (2)` archive and upload succeeded. App Store Connect subsequently reports processing **Complete**, **Testing / Internal**, **Owner Testing**, one invitation. Build ID `0936344e-6e1c-4826-a725-036c153038e4`. Physical installation is not claimed. Simulator restored to light appearance, UI runner removed and normal app relaunched.

## Compact Today dashboard

Replaced unlabeled completion copy/takeaway with two exact practice counts, latest session title and New question. 42 API tests passed, including cross-account isolation and totals exceeding the 100-session page; 13 native tests passed. Signed simulator UI journey verifies counts, latest-session metadata and New question navigation; screenshot visually reviewed in light appearance (`/tmp/drillbit-dashboard-ui.xcresult`). Fixture screenshot counts are synthetic. Dynamic Type stacking is implemented; manual VoiceOver/dark/largest-text checks for this specific dashboard remain unverified. Backend deployed; no TestFlight build or upload performed.

Dashboard follow-up: last-session metadata now includes its recorded engineering level and localized completion date/time. Missing legacy metadata is omitted. Signed simulator dashboard journey passed and screenshot was visually reviewed (`/tmp/drillbit-dashboard-details.xcresult`). No backend change or TestFlight upload.

Legacy level fix: live read-only metadata confirmed the reported notification-service session contains difficulty=easy and no engineeringLevel. Swift previously discarded difficulty. It now decodes it and displays the agreed Junior/Mid-level/Senior mapping, preferring an explicit engineeringLevel. Missing metadata shows Level not recorded. Fourteen native tests passed, including historical JSON decoding and precedence; signed dashboard UI journey passed with legacy Easy expecting Junior (`/tmp/drillbit-legacy-level-ui.xcresult`). Normal simulator app relaunched; no data migration or TestFlight upload.

## New-question sheet and temporary overrides

Implemented Topic picker sharing Settings presets (plus saved custom focus), Target level, Format/Choose for me and a visible optional request placeholder. Topic and level are local to this question; reopening initializes from global settings and ignores old preparation caches. Prepare question keeps the existing preview-before-Start flow. Review's Practise this next now opens the same sheet with removable feedback/source context. Follow-up generation receives bounded submitted answer and delivery/capture facts and treats recent history as variety context, not mastery evidence.

42 API tests and 14 native tests passed; TypeScript passed. Signed temporary-selection UI journey passed (change/cancel/reopen/default Settings checks); its screenshot was visually inspected (`/tmp/drillbit-prepare-ui.xcresult`). Development backend deployed as `0cc24031-2dd9-4dc2-aaa2-8872ac72cdd2`, health 200. This prompt refinement has not had another live Gemini evaluation. Physical-device/accessibility checks and additional ambiguous-request recovery remain unverified in this pass. No TestFlight build/upload.

Full practice/review/follow-up UI journey passed after refreshing stale Settings test selectors (`/tmp/drillbit-prepare-followup-final.xcresult`). Verified review opens New question with source feedback, Remove clears it, and Cancel returns to the completed review. Simulator relaunched normally and UI runner removed.

## Persistent Today and question preview — 9 September 2026

Implemented a permanent dashboard with compact ready/in-progress cards, coordinated preparation/loading/preview sheet, scrollable full prompt and pinned Start. Closing or backgrounding does not reopen the sheet when generation finishes. Preview never starts an attempt; successful Start hands off to the editor. Start errors remain inline; failed replacement retains the old question and recoverable preparation input. Resume preserves the local answer. No backend, schema or API changes for this iteration.

- Fourteen native package tests passed (`/tmp/drillbit-today-unit.log`). Signed simulator lifecycle test passed for preview/close, closing during generation, reopening the generated question and Start (`/tmp/drillbit-today-preview.xcresult`).
- Failure injection caught an app-wide alert dismissing the preview. Replaced it with inline error presentation; failed Start and failed replacement checks then passed (`/tmp/drillbit-today-failures.xcresult`). These are fixture failures, not live network fault injection.
- Explicit generation-to-preview-to-Start-to-close-to-Resume preserved typed text; backgrounding the loading preview returned to Today without reopening (`/tmp/drillbit-today-recovery2.xcresult`, two tests passed). An initial run failed on duplicate test labels; a dedicated preparation-submit identifier fixed the test ambiguity.
- iPhone 15 simulator: dark-mode lifecycle and largest Dynamic Type/long-prompt checks passed (`/tmp/drillbit-today-small.xcresult`, two tests). Start remains hittable while scrolling; Today action and Memory tab remain reachable. Normal dark preview and largest-text preview screenshots were visually reviewed. Temporary iPhone 15 simulator was removed after testing.
- iPhone 17 Pro: light preview/dashboard and accessible editor checks passed; screenshots reviewed. Accessibility identifiers, hierarchy and Dynamic Type are covered; manual spoken VoiceOver traversal and physical-device verification remain unperformed. Live generation/API behavior was not re-evaluated in this native-only change. No TestFlight build or upload.

Final signed Pro regression: full practice/Coach/Finish cancel-confirm/review/follow-up preparation/history journey and failed Start/replacement both passed (`/tmp/drillbit-today-final-review.xcresult`, two tests). Final code also checks account identity before loading a local draft or starting an attempt, and retains removable source context when recovering a failed follow-up brief. `git diff --check` passed.
