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

## Disabled live-voice control — 9 September 2026

Removed Practice options' Answer with section. Added a disabled 44-point waveform button at the leading edge of the workspace footer, aligned with mode/save status, using a muted semantic surface and 12-point corners. Accessibility identifies Live voice, In development; recording remains unimplemented. Signed Pro simulator Guided/adoption/undo journey passed, including the disabled-state assertion and removed-section check (`/tmp/drillbit-voice-button.xcresult`). Visually inspected its placement above the open keyboard. No physical-device or spoken VoiceOver check, backend change or TestFlight upload.

## Interview room — 9 September 2026

Implemented the approved writing-first interview: temporary Quick/Standard/In-depth style; explicit Share answer; one active prompt and fresh draft per follow-up; Ask interviewer for clarification, nudge and read-only examples; durable Conversation; explicit Keep going and confirmed Finish. Disabled voice remains bottom-left. Native mode switching and pause-triggered coaching are absent from this workspace; legacy APIs/history remain compatible. Original question and confirmed Skip remain available from the toolbar menu.

- **51 API tests passed** against D1, including authenticated HTTP/wire validation, duplicate/reused commands, competing devices, stale revisions, account ownership, clarification preserving the draft, response-only retry, Quick's deterministic wrap-up without a provider call, and completion racing a late response. TypeScript, generated OpenAPI and `git diff --check` passed. Results: `/tmp/drillbit-interview-api-ordered.log`.
- **17 native tests passed**, including pending-command/draft recovery across actual store recreation, account-scoped cache isolation, optional legacy preparation decoding, style/level independence and prevention of stale cloud snapshots rolling back acknowledged drafts (`/tmp/drillbit-interview-native-final.log`). Native refresh also checks edit generation before applying a result.
- **Signed Pro simulator journeys passed:** style picker → generated preview → selected style; answer → follow-up → conversation → help without changing the draft → wrap-up → Finish cancel/confirm; close/resume preserving draft; light/dark with keyboard; largest accessibility text with keyboard and reachable Ask/Share controls. Screenshots visually reviewed and layout refined after discovering wrapped primary-button text and cramped accessibility metadata. Results: `/tmp/drillbit-interview-ui.xcresult`, `/tmp/drillbit-interview-ui2.xcresult`, `/tmp/drillbit-interview-final-ui.xcresult`, `/tmp/drillbit-interview-wrap-ui.xcresult`. Final simulator build compiled after refresh/skip safeguards (`/tmp/drillbit-interview-release-sim.log`).
- **Live Gemini evaluation:** synthetic initial follow-ups across all three styles plus clarification, nudge and wrap-up samples. Initial samples wrongly advanced clarifications, attributed an unmentioned technique to the user, and asked more questions during wrap-up. Separate action schemas, an interviewer-specific prompt, canonical wrap-up copy and deterministic style ceilings address those observed classes. Revised samples were grounded and clarification remained a reply. Nudge brevity and broader style/technical calibration remain ongoing prompt work; this small sample is not comprehensive learning-quality validation. Script: `scripts/check-interview-model.ts`; ignored results: `.local/interview-model.json`.
- **Live development workflow verified:** an isolated synthetic account/challenge produced a completed Gemini follow-up through deployed Cloudflare Workflows and stored it in D1. The synthetic account and its data were deleted afterward. This exercised workflow/provider/storage, not physical-device sign-in or a live native network-failure journey.
- Development D1 was exported privately before additive migration `0006_interview.sql`; migration succeeded. Compatible Worker final version: `43ca2338-28c9-486b-8e36-04ca2b1c5db4`. No TestFlight upload. Manual spoken VoiceOver and physical-device validation remain unperformed; this iteration's visual checks used the Pro simulator, not another iPhone 15 simulator.

Interview menu refinement: moved Ask interviewer and the recorded style into …; footer now keeps only voice and Share answer. Style remains chosen during preparation. Signed simulator interview/help/Finish journey and style-menu check both passed (`/tmp/drillbit-interview-menu.xcresult`); menu screenshot visually reviewed. No backend change or TestFlight upload.

Conversation navigation refinement: moved the workspace's top-right Conversation button into …, removing its dedicated header row. The wrap-up shortcut remains. Signed simulator interview journey passed through the menu into the saved conversation (`/tmp/drillbit-conversation-menu.xcresult`). No backend change or TestFlight upload.

## Preview readability and loading alignment — 9 September 2026

Removed topic, engineering level and interview style from the preview reading surface. Title/prompt now explicitly retain their multiline intrinsic height within a full-size scroll view; the Start/Choose another footer stays safe-area anchored. Shared centered loading status now covers preview generation, Today generation, interviewer responses and example preparation.

Signed iPhone 17 Pro simulator checks passed: selected style remains available in the overflow menu after its removal from preview; largest Dynamic Type preview actually changes scroll position; a long normal-size prompt can scroll to its final line above Start; loading transitions into the minimal preview. Screenshots of centered loading, normal preview, long-prompt ending and accessibility scrolling were reviewed. Results: `/tmp/drillbit-preview-layout.xcresult` (style passed; initial scroll gesture incorrectly landed on the large footer), `/tmp/drillbit-preview-scroll3.xcresult` (corrected gesture within the reading viewport passed), `/tmp/drillbit-preview-final.xcresult` (two tests passed). No backend changes, physical-device verification or TestFlight upload for this adjustment.

## Interview style, focus stability and Share recovery — 9 September 2026

- Workspace … → Interview style reuses the native checkmarked selection list. Choice persists per account/attempt locally and is carried by the next explicit command; backend atomically records the selected style with the accepted turn and uses it in generation context. Old clients omit the optional field and retain the current style. No migration or global-settings change.
- Removed the workspace save-status caption. Keyboard focus no longer collapses the question; the disclosure remains user-controlled.
- Reproduced the reported Share message in the real native controller/outbox path using injected HTTP transport: overlapping autosave produced zero submissions and “Your draft is saved. Connect and sync before sharing.” (`/tmp/drillbit-share-red2.log`). Sync previously returned immediately when another pass was running. It now awaits that pass, drains this challenge, and checks this draft rather than all account pending writes. Retry retains and resubmits a preflight-failed action. Drafts/conflicts and ambiguous idempotent commands remain preserved.
- **18 native tests passed**, including three submission scenarios (in-flight autosave with a newer edit, offline failure then explicit Retry, unrelated unsynced work), style cache restoration and style in the submitted command. Tests use the real controller, DiskStore and HTTP serialization with synthetic transport, not live Clerk/Gemini. `/tmp/drillbit-share-style-final.xcresult`.
- **52 D1/API tests passed**, covering style capture, idempotency, stale-revision rejection and omitted-field compatibility (`/tmp/drillbit-style-api-final.log`). Shared request fixture validation subsequently passed all 11 HTTP tests (`/tmp/drillbit-style-http-final.log`). TypeScript and diff checks passed.
- **Pro simulator UI:** full Share/follow-up/help/Finish journey passed (`/tmp/drillbit-share-style.xcresult`); editable style, retained selection after reopening, and question remaining visible during typing passed (`/tmp/drillbit-share-style-final.xcresult`). Picker and keyboard screenshots visually reviewed. Initial style UI assertion had an incorrect literal prompt; corrected to a stable accessibility identifier. Physical device and spoken VoiceOver remain unverified.
- Compatible development Worker deployed as `aaccb3da-6ba7-4089-a45b-163b5a1b678e`; live health returned 200. No live model request was needed for these changes. Simulator only, no TestFlight upload.

## Continuous, manually foldable interview document — 9 September 2026

Implemented the approved second-council direction: one scroll surface for original specification, question/answer/help exchanges and a growing draft. Exchange headings fold manually, with overflow-only trailing fade and separate chevron; two-line native truncation replaces the fade at accessibility sizes. Header carries the actual title; Finish moved into …; original-only Full question remains available. Active history no longer needs a separate Conversation sheet. Submitted answers and inline wrap-up preserve the document.

- **20 native tests passed**, including projection ordering, one copy of each follow-up, assistance grouped with its question, failed-answer retention and account-scoped folding/offset persistence. Existing submission race, offline Retry and unrelated-pending-draft regressions remain green.
- **Signed Pro simulator verification passed**: Share → follow-up → inline previous answer → help with unchanged draft → wrap-up → Finish cancel/confirm; manual fold + close/resume with draft/position preserved; delayed wrap-up while reading history without a viewport jump; a separate delayed follow-up check also preserved position and showed New follow-up; long multiline typing retained the entire value and grew the editor; largest Dynamic Type editing and original-question sheet return stayed reachable. Main evidence: `/tmp/drillbit-document-final.xcresult` (20 native tests, four UI tests), `/tmp/drillbit-document-followup.xcresult` (targeted follow-up journey).
- Visually reviewed light-mode folded/history and response screens, dark long-answer keyboard, and largest text with keyboard/full question. The SwiftUI multiline field initially failed the long-answer sizing/caret check. A small UITextView bridge now disables internal scrolling, measures growing content, and reports caret geometry to the parent scroller. Its focus lifecycle is owned by the native delegate; the final long-answer test checks complete text retention as well as height growth.
- Disclosure choices are never changed by typing, requests or response arrival. A person scrolling back gets an explicit return/new-response action rather than a forced jump or an enabled offscreen Share action. Presentation offset is local, device-specific convenience state.
- No backend/API migration or deployment for this document change. No TestFlight upload. Physical-device, spoken VoiceOver, and dedicated Reduced Motion/Reduced Transparency setting runs remain unverified; this layout adds no custom animation or translucent surface.


## Inline original question and Share freeze — 9 September 2026

Removed the duplicate original-question modal and its redundant inline link. Full question in … expands the original exchange and scrolls to the document’s top edge, including after keyboard dismissal. The entire specification scrolls with the document; draft and history remain in place.

Reproduced the user’s live-simulator Share freeze. A three-second process sample (`/tmp/drillbit-share-hang.sample.txt`) placed every main-thread sample in `GrowingInterviewEditor.updateUIView` → `UITextView.resignFirstResponder` → SwiftUI responder-graph re-entry / AttributeGraph cycle reporting. UIKit focus/editability reconciliation now runs on the next main-queue turn with current bindings, outside the view update. This fixes a UI-thread stall before submission rather than changing the backend or bypassing draft synchronization.

Verification: 20 native tests passed, including overlapping autosave, offline retry and unrelated pending-draft submission cases (`/tmp/drillbit-inline-share.xcresult`). The interview Share → follow-up → ask → wrap-up → Finish cancel/confirm UI journey passed in that run; its initial two navigation failures were fixed by scrolling to the document edge. Both final navigation regressions then passed (`/tmp/drillbit-inline-jump.xcresult`): an 18-paragraph original specification scrolls through to the unchanged draft, Full question returns to the heading whether folded or expanded, and largest Dynamic Type supports expand → fold → type → Share without a hang. Screenshots were inspected.

Live-service verification: launched the updated signed-in simulator, resumed the preserved user draft, focused its editor and shared it successfully. The backend returned a grounded follow-up visible inline. Full question expanded the original specification at the top without a modal. No backend changes/deployment or TestFlight upload; no physical-device verification. The simulator is left running for testing.


## Keep shared answers beside replies — 9 September 2026

Question disclosures now hide only question wording. Sent answers remain visible; completed answer snapshots appear immediately above the interviewer follow-up in the same block. Accepted Share folds the question just answered; failed submission keeps the draft and disclosure intact. A divider separates the original question from the initial answer editor. No backend or persistence contract changes.

Simulator verification: `/tmp/drillbit-answer-pair.xcresult` passed the complete interview journey and largest Dynamic Type editor journey. Assertions verify automatic original-question collapse, the submitted answer remaining hittable beside its response, and continued visibility when the follow-up is manually folded; clarification preserves the next draft and Finish cancel/confirm still works. The follow-up screenshot was visually inspected. Normal signed-in simulator relaunched; no TestFlight upload or physical-device verification.


## Response-driven answer folding and faster model — 10 September 2026

20 native tests and the complete interview UI journey passed (`/tmp/drillbit-collapse-speed.xcresult`). The journey verifies that a completed answer is collapsed, its row stays reachable beside the reply, and tapping restores the full text. The original disclosure now previews the title. Pending/failed answers remain expanded; manual expansion persists in an optional cache field.

52 backend/D1 tests and TypeScript checking passed, including fixed-model/latency-routing/reasoning-off request assertions and legacy model acceptance. In a two-prompt synthetic OpenRouter comparison, 2.5 Flash-Lite completed in 0.84/0.51 seconds at $0.0000208/$0.0000174, versus 3.1 Flash-Lite at 0.91/0.82 seconds and $0.0000765/$0.0000725. Both used latency routing; 2.5 had reasoning disabled and 3.1 used minimal reasoning. This small sample establishes neither global fastest-model status nor production percentile latency.

Live checks using the app’s prompts and actual generation/interview schemas returned valid, coherent outputs: question generation 1.41 seconds ($0.00014); interview follow-up 0.49 seconds ($0.0000636). A separate interview sample took 0.48 seconds. These are direct provider times, excluding workflow dispatch and client polling. Broad level-specific quality evaluation is not complete; 2.5 may offer less precise follow-ups than 3.1. Routing semantics: https://openrouter.ai/docs/guides/routing/provider-selection . Backend deployed with health 200; simulator installed; no TestFlight or physical-device verification.


## Home, compact send and voice input foundation — 10 September 2026

Home replaces Today, retaining practice counts and question/preparation controls while removing the latest-session summary. The send/finish control uses a 44-point SF Symbol with explicit accessibility labels; existing disabled states and confirmation remain. Screenshots of Home and keyboard-open sending were inspected.

`/tmp/drillbit-home-voice.xcresult`: 21 native tests and two UI journeys passed (Home dashboard and complete interview flow). The new finalized-answer test checks account rejection, written-draft preservation, stale prompt rejection, duplicate/mismatched event handling and restored answer/reply history. These voice-input tests use a fixture response, not live audio or a live voice service. The existing backend still owns response generation and turn storage. No API migration/deployment or TestFlight upload was needed. Final simulator build includes the remaining Home recovery-copy rename.


## Resume disclosure timing and compact question preview — 10 September 2026

Restores local disclosure choices before showing interactive document content; network hydration no longer applies saved choices after user interaction. Collapsed original question displays a two-line title and up to three description lines. AI answer waiting/sharing labels are inline text, without large loading indicators or spinners.

`/tmp/drillbit-resume-final.xcresult`: two UI journeys passed — history restoration/late response and full send/ask/review/Finish flow. Checks include restored collapsed state and draft, stable history position during reply arrival, and zero progress indicators while waiting. The earlier history test assumed a Return to answer control would always be needed; it now also supports the shorter history produced by collapsed answers. The collapsed-preview screenshot was visually inspected. Simulator only; no backend deployment or TestFlight upload.


## Skip alert and tighter disclosure headers — 10 September 2026

Replaced Skip’s anchored confirmation dialog with a standard alert. Expanded question headers now use bottom-aligned 44-point hit areas and an 8-point body gap; answer headers use 4 points. `/tmp/drillbit-skip-spacing.xcresult`: full interview journey and Skip cancel/confirm journey both passed. Cancellation preserved the typed draft, confirmation returned to Home, and the alert screenshot was inspected. Simulator only; no backend or TestFlight changes.


10 September 2026: reduced the gap above expanded Follow-up headers while preserving collapsed exchange spacing. Removed sharing/waiting captions from interview and Ask surfaces, retaining failure recovery. The complete interview UI journey passed (`/tmp/drillbit-tight-followup.xcresult`); follow-up screenshot inspected. Updated app relaunched in the simulator. No backend or TestFlight changes.

## Immediate Send and streamed interviewer — 10 September 2026

Implemented immediate collapsed outgoing answer + Interviewer header, real provider streaming through durable jobs, and removal of the automatic wrap-up panel/turn ceiling. Visually inspected screenshots immediately after Send and during partial response: the disclosure arrow/header already exist before text arrives, with the previous compact exchange spacing preserved.

- Backend: typecheck/contracts generation passed; 53 tests across seven files passed. Coverage includes provisional text before completion, JSON escape fragments, account isolation, lifecycle cancellation and existing retry/revision behavior.
- Native: 21 unit tests passed; complete interview journey and explicit slow-stream UI journey passed (`/tmp/drillbit-stream-final.xcresult`). After fixing the completion/submission race, 21 native tests and the immediate-Send/partial-stream journey passed again (`/tmp/drillbit-stream-race-fixed.xcresult`). UI fixtures deliberately delay responses to verify the intermediate state; they are not live latency measurements.
- Live Gemini 2.5 Flash Lite: direct provider stream returned first parsed text at approximately 810 ms, completed at 879 ms, with a grounded worker-retry follow-up. This measures provider transport, not the signed-in native round trip. Short replies may appear nearly together at the snapshot cadence.
- D1 backup created under ignored `.local`; additive migration 0007 applied and compatible development backend deployed. Simulator build only; no TestFlight or physical-device verification. Full signed-in native streaming latency remains unmeasured.

## System-design library and metadata — 10 September 2026

Implemented the approved foundation: system-design-only preparation; temporary area picker; 24-concept taxonomy; short scenarios; immutable questions with repeatable attempts; native Library/search/filters; skipped-question pool recovery; coverage counts; deterministic basic selection; and account-scoped reset epochs/outbox recovery. Context engineering, skill inference and personalized review scheduling remain deferred.

Verification:
- Backend typecheck, contract generation and 61 tests across eight suites passed (`/tmp/library-test-final2.log`). D1 checks include 103-question pagination, combined filters/alias search, coverage counts, account isolation, repeated/competing starts, immutable original answers, stale eligibility revisions, conflicting command payloads, and restored-question selection without calling a provider.
- 22 native tests passed, including account-scoped reset cleanup, durable draft recovery and interview submission regression checks (`/tmp/drillbit-library-final.xcresult`). Generation/preview/resume passed in `/tmp/drillbit-library-v2.xcresult`; temporary preparation and accessible Settings/onboarding passed in `/tmp/drillbit-library-v3.xcresult`.
- Library/Skip/Add back/Preview/Start UI journey passed at normal size; the same journey passed in actual dark appearance at largest Dynamic Type (`/tmp/drillbit-library-large.xcresult`). Screenshots were inspected. Large content requires native scrolling; tests verify reaching actions after scrolling. A fixture-only uninitialized Clerk access in coverage loading was fixed during validation. No complete VoiceOver session or physical iPhone test was performed.
- Live Gemini samples rotated all 24 concepts across the six levels. The final batch accepted 23/24; one overlong scenario was rejected by validation. An explicit retry for that concept passed. Earlier testing exposed copied-evidence/cross-array disagreements, leading to the single indexed tag-list contract. Sampled prompts were reviewed for visible design decisions and level scope; this is not a validated skill assessor. Evidence files: ignored `.local/library-generation-evaluation.json` and `.local/library-generation-retry.json`.
- Development D1 was backed up, migration 0008 applied, then practice records were reset. Post-reset counts: one account, one settings record, zero D1 credential records (unchanged from backup), zero questions/attempts/old companion commands/practice jobs. Managed-provider Worker secrets remain configured. The maintenance gate was re-enabled after deployment; backend health returned OK. No TestFlight upload.

## Library refresh and floating interview controls — 10 September 2026

Implemented account/filter-scoped cached Library presentation with background revalidation, cached question details, a two-word scenario header, directly visible Close, no Return to answer shortcut, and transparent safe-area footer around voice/send controls. No backend contract changes.

Verification: Pro simulator build and Library revisit → skipped recovery → preview → start passed, as did immediate send/collapse/streaming (`/tmp/drillbit-floating-controls.xcresult`). The history restoration test initially failed because simulator typing entered a character out of order; an unchanged rerun passed draft restoration, late-response scroll preservation and manual scrolling to the response (`/tmp/drillbit-history-refresh-recheck.xcresult`). Library and streaming screenshots inspected. No physical-device, fresh accessibility-matrix or live slow-network verification in this change. No TestFlight upload.

## Library preload correction — 10 September 2026

Removed refresh-on-entry and pull-to-refresh. Launch warms the first 25 completed/skipped questions, question details and each latest full attempt. Library navigation uses prepared snapshots; uncached filters/pagination remain demand-loaded. Completion refresh waits for stored server feedback outside the results screen; skip refreshes only skipped records and eligibility acknowledgements patch cache.

Verification: 10 ContractTests passed, including preload-once/until-invalidation and preloaded attempt data (`/tmp/drillbit-preload-unit.xcresult`). Library revisit/skipped restoration/preview/start passed (`/tmp/drillbit-library-preload-final.xcresult`). Initial UI verification caught stale restored eligibility in fixture cache; corrected and rerun passed. Cold-launch network latency, physical-device behavior and the live delayed-feedback watcher were not separately measured. Simulator-only delivery.

## XML interviewer context — 10 September 2026

Backend typecheck, generated contracts and 65 tests across nine suites passed (`/tmp/context-tests-final.log`). Added D1 checks for bounded account-scoped history and pinned prompt edition, plus XML escaping and committed role ordering tests. The updated native style journey passed (`/tmp/drillbit-standard-style-v2.xcresult`); screenshots inspected with Standard selected and Quick/In-depth disabled in preparation and active interview.

Reviewed five synthetic live batches with the unchanged Gemini 2.5 Flash Lite configuration. Final batch: eight schema-valid replies (`.local/interviewer-context-evaluation.json`, `/tmp/interviewer-context-final-live.log`). Direct clarification and nudges improved; role-paired history improved the resolved-topic example. Repetition, generic refusals and unwanted follow-up wording remain stochastic quality limitations. One earlier batch had one provider/schema failure. This is exploratory product evaluation, not a guarantee of instruction adherence or technical correctness.

Development Worker deployed as `c6d06d35-063a-4cc3-ac32-c3f2227de8a2`; health returned OK. No migration, TestFlight upload or physical-device verification.

## Smooth interview document transitions — 10 September 2026

Unified structural animations, fading incoming rows, animated stream growth and settled scrolling replace abrupt response-time relayout. Busy clarification/help preserves the editor rather than removing it. Reduced Motion bypasses animation.

Pro simulator send/stream/next-editor and history-restoration/late-response tests passed (`/tmp/drillbit-smooth-response.xcresult`); final send journey passed after removing overlapping outgoing fades (`/tmp/drillbit-smooth-response-polish.xcresult`). Recorded and inspected frame sequences from `/tmp/drillbit-response-motion-polished.mov`: the interviewer header remains in place through streaming, then the next editor arrives below it. Earlier recording revealed outgoing editor/question ghosting, which was removed with identity removal transitions. No physical-device or separate Reduced Motion runtime check in this pass. Simulator only.

## Faster, clipped question expansion — 10 September 2026

Manual disclosures now open in 180 ms with intrinsically measured content clipped to the animated reveal height. Content hides immediately during collapse so it does not overlap the returning excerpt. Reduced Motion removes timing; collapsed text is neither interactive nor exposed to accessibility.

Send/stream and history restoration regressions passed (`/tmp/drillbit-clipped-disclosure.xcresult`). Repeated original-question expand/collapse test checks the first history row remains below the prompt (`/tmp/drillbit-expansion-final.xcresult`). Recorded 20 fps frame inspection around opening in `/tmp/drillbit-question-expansion.mov` showed the question progressively revealing above the history. Collapse inspection prompted removal of lingering full text behind the excerpt. Physical-device behavior not checked.

### Stable question title

The original question now has one persistent title in the disclosure header, with consistent typography and intrinsic wrapping. Only the description passes through the clipped reveal, preventing the title from being sliced during expansion. Repeated expansion/history-boundary test passed (`/tmp/drillbit-stable-question-title.xcresult`); recorded frames from `/tmp/drillbit-stable-title.mov` inspected. Simulator only.

### Unified original-question motion

The original description now remains one text view, with its height animated between a three-line preview and the full prompt. This supersedes the immediate full-text hiding described above for the original question. Manual disclosure and first Send share a 220 ms ease-in-out transition; the title stays outside the clipped area.

Repeated expansion/history-boundary and immediate-send/stream tests passed (`/tmp/drillbit-unified-question-motion.xcresult`). The send test passed again (`/tmp/drillbit-first-send-unified.xcresult`); 20 fps frames from `/tmp/drillbit-first-send-unified.mov` show the description shrinking progressively on first Send, with a stable title and the You/Interviewer rows appearing below. No physical-device or separate Reduced Motion runtime verification in this pass.

### Submitted text uses the question disclosure motion

Submitted answers now keep one opaque text view while compressing to a single line, using the same 220 ms ease-in-out measured-height component as the original question. Send stages the snapshot without the document insertion animation before compressing both disclosures. Manual answer expansion uses that same component; the complete answer remains available.

The original-question expansion/history-boundary test passed in `/tmp/drillbit-answer-motion.xcresult`. The extended multi-line Send, partial stream, completed response, and answer reopen/re-collapse journey passed in `/tmp/drillbit-submission-final.xcresult`. Earlier runs missed the fixture's 100 ms partial updates; the explicitly slow fixture now holds each partial for 400 ms, leaving production transport unchanged. Recordings exposed the initial blank handoff and informed the staging fix. Final recording `/tmp/drillbit-submission-final.mov` confirms settled and reopened content, but did not capture every handoff frame reliably. Exact animation feel still needs user confirmation; physical-device and separate Reduced Motion runtime checks were not performed.

### Compact, content-aware transcript rows

Three Pro simulator UI tests passed in `/tmp/drillbit-compact-final.xcresult`: original-question expansion stays above history; multi-line Send/stream/reopen works; one-line user and interviewer turns have no disclosure controls. Exported screenshots in `/tmp/drillbit-compact-screens` were inspected for the short-turn history and completed streamed reply. They show the reduced divider/header spacing, short turns as plain text, and arrows on longer turns. Dynamic Type uses live SwiftUI measurements, but largest-type, VoiceOver and physical-device runtime checks were not repeated in this pass. Simulator only.

### Stable row labels

Send/partial-stream/completion/answer-reopen and single-line disclosure tests passed in `/tmp/drillbit-stable-labels.xcresult`. Labels now opt out of local animation, and exchange/draft insertion no longer fades their headers. Existing disclosure timing is preserved. This pass verifies simulator interaction regression checks; transient shimmer has not been independently frame-verified or checked on a physical phone.

## Optimistic Skip and pool restoration — 11 September 2026

Home clears immediately after local Skip persistence; the workspace closes without awaiting HTTP or Library hydration. Cancel still preserves the editor. Pool restoration patches local eligibility after enqueue and syncs outside the detail view. Queued commands are account-scoped, applied over refreshed snapshots, and included in sign-out pending-write checks. Skipped drafts use a local terminal marker so stale remote snapshots cannot overwrite the retained answer or restart its upload.

Verification: 21 Swift core tests passed (`/tmp/drillbit-final-core.log`), including duplicate/scoped Skip queue handling, on-disk queue restoration and retained draft after acknowledgement/stale load. Skip cancel/confirm/Home and Library pool-restoration simulator journeys passed (`/tmp/drillbit-optimistic-final.xcresult`). These UI journeys use fixtures; live offline/reconnect and physical-device flows were not exercised. Existing repeat-safe Skip and revision-checked eligibility endpoints are unchanged; no deployment or TestFlight build.

## Inference pipeline optimization — 11 September 2026

Verified 68 backend tests on the D1 test runtime (`/tmp/drillbit-latency-verified.log`) and TypeScript checking. Added coverage for atomic unsynced-answer submission, old-client text matching, competing revisions, idempotent replay, slow workflow enqueue after durable job creation, and provider-token draining under a blocked single partial writer. All 22 Swift core tests passed (`/tmp/drillbit-latency-core.log`), including account-scoped local atomic command preparation, retained text before acknowledgement and stale-text acknowledgement rejection. Simulator Send/stream and Skip checks passed (`/tmp/drillbit-latency-ui.xcresult`); generation/preview/resume and Send passed in `/tmp/drillbit-inference-final-ui.xcresult`. These UI tests use fixtures, not authenticated live atomic-submission traffic.

Four synthetic live provider requests returned schema-valid interview outputs. Previous duplicated-prompt first-visible-text times: 905 and 477 ms; compact-prompt: 460 and 574 ms (`/tmp/drillbit-live-latency.log`). These are provider-only observations with uncontrolled routing/warmup, not evidence of an end-to-end percentage improvement. Native/Worker timing instrumentation is available for the next real interview.

Development backend deployed as `2550aac2-a5e9-4014-9760-ac98c3a03c28`; deployed `/health` returned `status:ok`. No schema migration. Simulator delivery only; no TestFlight or physical-device verification. Workflow startup remains; D1-backed SSE is still used. Architecture documentation explicitly distinguishes those retained costs from the optimizations implemented.

## Cache-first practice statistics — 11 September 2026

Native build and two Pro simulator UI tests passed in `/tmp/drillbit-cache-home.xcresult`: cached statistics were present on the first observed Home frame across two launches, and Library/Skipped restoration remained functional. The statistics fixture writes through DiskStore and exercises the production hydration helper before Home publication; it does not exercise live Clerk authentication or a physical offline/reconnect cycle. Exported Home screenshot inspected in `/tmp/drillbit-cache-home-screens` shows populated counts with no dash or loading placeholders. Cache retention and stale account/request guards were reviewed in code. Simulator only; no backend deployment or TestFlight upload.

## No sign-in flash during launch — 11 September 2026

Build and two simulator UI tests passed (`/tmp/drillbit-auth-launch-final.xcresult`). An eight-second delayed restoration fixture verifies the neutral launch surface has no Apple sign-in button, then reaches cached Home; a separate confirmed-signed-out fixture reaches Welcome after restoration. The cached-statistics launch regression also passes twice. Clerk's installed source confirms `isLoaded` requires both environment and client. The first test run used too short a fixture delay for accessibility observation; the final run extends only the fixture delay. Timeout and authenticated-bootstrap recovery branches were code-reviewed, not live fault-injected. No physical-device or TestFlight verification.

## Fluid disclosure layout — 11 September 2026

Two simulator UI tests passed in `/tmp/drillbit-fluid-disclosure.xcresult`: repeated original-question expansion retains the history boundary, and Send/stream/answer-reopen remains functional. Inspected 16 fps frames from `/tmp/drillbit-fluid-disclosure.mov` (`/tmp/drillbit-fluid-motion.png`): downstream rows and labels move progressively during question collapse/expansion rather than labels jumping ahead. No physical-device or new Reduced Motion runtime verification.

## Practice personality and voice foundation — 11 September 2026

TypeScript checking and 69 D1/backend tests passed (`/tmp/drillbit-personality-tests-release.log`). All 25 native tests passed (`/tmp/drillbit-personality-native-final.xcresult`), covering normalized voice replay, draft protection, stale identities, finished/inactive admission, and restoration. The full native run also exposed older tests expecting Quick style and a pre-submission draft upload; updated those expectations to Standard and injected offline failure at the actual atomic interview endpoint, retaining pending-work/retry assertions. Simulator Send/stream/reopen passed (`/tmp/drillbit-personality-ui.xcresult`).

Live synthetic personality evaluation is a partial product pass, despite 14/14 valid final response envelopes. See `docs/context-engineering.md` for observed improvements, failures, costs and reproducible evaluator. Final non-reasoning sample: `/tmp/drillbit-personality-release.log`; earlier baseline and candidate logs are retained under `/tmp/drillbit-personality-*.log`. No real user history was used. No claim of fully polished Poke-like personality, prompt-injection resistance, end-to-end latency or live audio readiness.

Development Worker deployed as `b426c78b-b2f8-4ba7-81f5-3d462d57ec6a`; `/health` returned `status:ok`. No migration. Simulator build installed; no TestFlight or physical-device verification.

## V4 playful practice partner — 11 September 2026

TypeScript checking and 72 backend/D1 tests passed (`/tmp/drillbit-v4-verified-tests.log`), including social-context isolation/full-context restoration, rejecting technical messages from social routing, deterministic protocol outcomes, legacy editions, malformed moves and streaming under slow partial writes. Two complete 24-turn live candidate runs and one final refusal check were reviewed; see `docs/personality-acceptance.md` for actual replies, scope and latency/cost.

Development Worker deployed as `ab6f37c9-16b7-4b2e-a42d-5ce2f0766c6c`; health returned `status:ok`. No database migration or public API changes; no native UI changes in this iteration. Provider evaluations are synthetic, not authenticated end-to-end app tests. No TestFlight or physical-device verification.

## Internal TestFlight build 3 — 11 September 2026

- Signed Release `2.0.0 (3)` archive and internal-only App Store Connect upload succeeded. Existing development backend health returned `ok`; V4 personality is already deployed. No voice recording enabled.
- Apple displayed build 3 as **Processing**. Later App Store Connect queries stalled/returned empty data, so processing completion and Owner Testing availability remain unverified. This is upload verification, not physical-device acceptance.
- Version bump persisted in XcodeGen source and generated project. `git diff --check` passed; earlier native/backend/personality test evidence remains recorded in their respective sections.

## Stable disclosure headers — 11 September 2026

Removed pressed-state label dimming from the original-question disclosure button. Paired answer/interviewer spacing now stays constant across disclosure states, removing the 4-point upward header shift while preserving the shared body/document animation. Two iPhone 17 Pro simulator UI tests passed: repeated toggles preserve header Y within 0.5 points, and expanded original content keeps history below it (`/tmp/drillbit-stable-headers.xcresult`). Manually inspected expanded/collapsed simulator layouts; frame-by-frame opacity and physical-device verification remain unclaimed. Simulator only; no new TestFlight upload.

## Text-practice completeness — 11 September 2026

See [implementation and evidence ledger](product-completeness.md). 77 backend/D1 tests, 25 native unit tests and nine targeted simulator journeys passed; latest simulator build succeeds. Appearance persistence, dark typing, largest-text Library/Settings, cached stats, restoration, late-response history, interview completion and new evidence navigation were exercised. OpenAPI/fixtures include additive evidence and export contracts. Live Gemini: 24 personality turns and four final reflection cases reviewed after correcting earlier reflection failures. Physical-device notification/widget delivery, MetricKit delivery, full VoiceOver navigation and multi-device interruption remain unverified. No voice or TestFlight rollout.

### 12 September — voice integration, simulator and D1 only

83 API/D1 tests pass, including paid-start reservation competition, transcript replay/collision/account scope, text/finish blocking while active, frozen completion and post-close delegation rejection. Native tests cover stable overlap grouping, draft preservation and restoration without paid startup. Fixture UI journeys cover voice start, mute/unmute, inline speech, end and preserved draft in light and largest Dynamic Type/dark. Screenshot inspection prompted compact accessibility controls. These are simulated provider events, not verified microphone or GPT-Live behavior. Server gate remains off pending OpenAI credentials and live/device acceptance. No TestFlight upload.

Voice verification artifacts: `/tmp/drillbit-voice-api-verified.log`, `/tmp/drillbit-voice-verified.xcresult` (native lifecycle tests and two UI journeys), plus grouping tests in `/tmp/drillbit-voice-final.xcresult`. Development Worker `4c657ab8-5b46-455f-9b13-960dd2382307`: health 200, anonymous voice startup 401, live gate false. Latest signed simulator app installed; no TestFlight upload.

12 September credential follow-up: OPENAI_API_KEY installed as a development Worker secret. Direct model lookup returned 200 for gpt-live-1; a bounded, silent WebSocket session-start probe returned `credit_balance_exhausted`. No audio was captured. Voice gate remains false pending API credit; model lookup alone does not establish voice-session availability. Simulator rebuild succeeded and the app was reinstalled/relaunched (`/tmp/drillbit-key-build.log`).

12 September billing resolved: a silent direct GPT-Live WebSocket probe received `session.started` followed by `session.closed` (usage seconds 0). Enabled VOICE_ENABLED for the development testing environment. This verifies provider startup, not native WebRTC audio, microphone quality or physical-device behavior. No client rebuild or TestFlight upload required.

12 September empty voice row: suppress rendering for reserved voice blocks with no text, so startup cannot add a second separator beside the draft. The voice UI journey asserts no voice separator before speech; passed in `/tmp/drillbit-voice-divider.xcresult`. Simulator installed. Dedicated voice room remains a proposal in `voice-room-plan.md`, not implemented.

## Dedicated voice room — 12 September 2026

Implemented: stable interview shell owns connection/outbox across writing/voice routing; canonical question disclosure; Question/Conversation selection; shared transcript with manual-scroll precedence and Latest; fixed mute/end controls; synchronous local audio stop on Back/End; connecting cancellation; conservative recovery on the writing page. Empty voice blocks render no separator in either reading surface. Entry uses a 300 ms bottom-leading 0.96-scale/opacity surface transition; Reduced Motion uses 180 ms opacity only. No network, DTO, database, provider or TestFlight change in this iteration.

Evidence:
- `/tmp/drillbit-voice-room-v2.xcresult`: native InterviewSubmissionTests passed, including persisted voice fragments, account isolation, restored draft and no automatic restart; autosave/offline submission scenarios passed.
- `/tmp/drillbit-voice-room-v3.xcresult`: all three UI journeys passed on iPhone 17 Pro simulator: normal light; largest Dynamic Type/dark; cancellation during a deliberately suspended startup. Normal/dark journeys exercise mute/unmute, transcript generation, switching both ways without session loss, End, preserved draft and inline transcript. Cancellation waits past suspended startup and verifies no microphone/room resurrection.
- Inspected exported light/dark Question and Conversation screenshots in `/tmp/drillbit-voice-room-images`. Question/history scroll above the fixed controls; large text remains readable with native scrolling. Fixed controls retain accessible labels; an inherited parent identifier discovered during QA was removed.
- Final empty-transcript filtering was compiled in `/tmp/drillbit-voice-room-final-build.log` after these journeys.

Not established by these fixture runs: physical-device microphone/audio routing, real provider interruptions/close races in the new page, VoiceOver spoken navigation, Reduced Motion visual playback, extended manual transcript scrolling, or real-time audio/motion performance. Existing backend voice tests/provider evidence remain separate; no new paid provider evaluation was run for this UI change. No TestFlight upload.

## Text-first workspace and voice refinement — 12 September 2026

Implementation: [interview workspace](interview-workspace.md). Quick-help actions are inline menu operations, Send always sends, and voice uses a question/latest projection with History/Live and balanced Mute/Use text controls. Availability is checked without consuming usage; unavailable entry preserves the draft. No migration or TestFlight upload.

Verified:
- Backend typecheck and 84 D1-backed tests passed (`/tmp/workspace-api-tests.log`), including read-only capability limits/account scope plus existing voice concurrency/receipt/completion tests. Contract generation and available/unavailable/limit/legacy fixture parsing passed. `git diff --check` passed.
- `/tmp/drillbit-workspace-v1.xcresult`: 10 native tests and six UI journeys passed: full text interview with direct hint while retaining unfinished reply, immediate submission/streaming/collapse, normal voice, largest Dynamic Type dark voice, unavailable voice with preserved reply, and cancellation during suspended startup.
- `/tmp/drillbit-workspace-native-final.xcresult`: eight InterviewTests passed, including the added capability expiry/future-date/legacy omission test and overlap-preserving latest projection; existing submission/restoration tests passed in v1. The earlier single-method selection in `/tmp/drillbit-workspace-final.xcresult` ran zero tests and is not test evidence.
- Inspected light and largest-text dark captures in `/tmp/drillbit-workspace-images`. Removed the oversized Latest overlay found in review; the 44-point replacement uses a safe-area inset. `/tmp/drillbit-workspace-polish.xcresult` passed the dark/large-text voice journey after that change; captures are in `/tmp/drillbit-workspace-polish-images`.
- Compatible development backend deployed as `20401975-8283-4142-8284-f824130673da`; deployment succeeded, but this turn did not perform an authenticated live capability/provider session probe.

Remaining verification boundaries: no physical-device microphone/audio interruption test, VoiceOver spoken-navigation pass, or Reduced Motion visual recording in this iteration. Fixture voice does not establish real provider timing or network race behavior. Existing native Reduced Motion, account ownership and interruption handling remain; do not treat source review or simulator screenshots as physical-device acceptance.

Follow-up: `/tmp/drillbit-workspace-scroll.xcresult` passed the largest-text dark journey with an explicit Latest tap and assertion that the interviewer response is hittable. Final simulator app installed and launched normally after fixture tests.

## Owner voice allowance and Library detail cleanup

The simulator owner's exact account is exempt from daily voice starts and technical voice-guidance limits, with usage retained. 85 backend/D1 tests and typecheck passed, including exact-ID matching, unaffected other accounts, disabled service, starts above six and technical guidance above forty. Library detail removes the redundant scenario/level row and labels related-question filters as Concepts. `/tmp/drillbit-library-cleanup.xcresult` passed the Library/skipped restoration journey; its question-detail capture was visually inspected. Simulator build only; no TestFlight upload.

## Daily app-open generation — 12 September 2026

Implemented server-side account/local-day claims and client day caching, existing-question/pending-job reuse, explicit failure recovery, no scheduled generation, and a generic local reminder. 88 D1/backend tests and typecheck passed (`/tmp/daily-tests.log`), including concurrent devices, DST/local midnight, account isolation, preservation of existing work, and no generation from overdue scheduler settings. Daily wire fixture parsing and contract generation passed. `/tmp/drillbit-daily-open.xcresult` passed Home automatic preparation/regeneration; final native build passed (`/tmp/daily-final-build.log`).

D1 migration 0010 applied after private backup. Worker deployed as `465f3af9-8d38-4090-9c43-a13b00e14a95`. Final simulator installed/launched; remote D1 read verified the owner's authenticated app created the `2026-09-12` daily-visit record. This verifies live app-to-backend day registration, not a fresh live inference or physical notification delivery. No TestFlight upload or APNs setup.
