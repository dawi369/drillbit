# Finish report

Result of the autopilot finish pass ([autopilot-finish.md](autopilot-finish.md)), 9 October 2026, on top of the uncommitted 3 October taste-pass work (preserved). Everything below is uncommitted in the working tree.

## Outcome

**Not finished by the mandate's definition, but close, and the gap is verification rather than product.** Every fixture-driven path a person can take in the first two weeks (Welcome → first rep → feedback → Home → resume → replace → Memory → Settings, at default and largest type, light and dark, Reduce Motion on) walks clean after 20 findings were fixed, and the suites are green: API 147 D1 tests, Swift 51, UI 65 incl. the 8 new walkthroughs. What I could not do: sign in with Apple on the simulator (an interactive Apple ID is needed), so the LIVE half of the acceptance script (steps 2, 4–19 end to end against the development Worker) was not run as a UI flow. The server side of those steps is covered by D1 tests and the prompt evaluators were run live (64 provider calls); the client side is covered by the same screens in fixtures. The one thing I would still change: the Mock debrief's per-area **Strong / Mixed / Weak** ratings read as a proficiency diagnosis from one attempt, which the vision rules out; the cheap-cut doc already proposes dropping them for three honest states with quotes. That is a product decision, so it is logged (D-3), not changed.

## Acceptance script results

Verification levels per AGENTS.md: **compiled/tested** (fixtures, D1, XCTest), **live-service verified** (real Worker or provider). Nothing here is physical-device verified. Screenshots: [finish-report/shots](finish-report/shots/).

| # | Step | Result | Level | Evidence |
| --- | --- | --- | --- | --- |
| 1 | Install, launch, Welcome voice | pass | compiled/tested | `check-ios-launch.sh` green; `testAuditA` a01–a04 |
| 2 | Sign in with Apple, invite | **not run** | — | needs an interactive Apple ID on the simulator; invite copy "That invite is invalid or has already been used." is literal and calm (server test "blocks product access until an invitation is redeemed") |
| 3 | Home empty state, one action | pass | compiled/tested | c01 (`prepareQuestion` is the whole ticket) |
| 4 | Prepare: defaults, instruction, LIVE generation | partial | live (provider) | e02–e06 in fixtures; live question quality via `evaluate-questions.ts` ×3 runs: 8/8 name an audience or bound the system and end on a decision; mock openers fixed (F-019) |
| 5 | Opener arrives with the question | pass | compiled/tested + server test | e07; `opener` is a required generation field (jobs.test "publishes the opener…") |
| 6 | ~150 words, autosave, kill, relaunch | pass | compiled/tested | f01–f03 (`--fixture-persist`, F-010) |
| 7 | Send → one on-topic follow-up | pass (live tone) | live (provider) | e09; `evaluate-personality.ts` 24/24 valid, one question per turn |
| 8 | "?" line → answer, not evaluation | pass | compiled/tested + live | e11, e12; personality cases `holdout-evidence`, `playful` |
| 9 | Nudge / Example / adopt / undo | pass for Nudge+Example; adopt/undo **N/A** | compiled/tested | e13, e14, b13, b14; examples are read-only in the Interview room by the 9 Sept decision (D-1) |
| 10 | Switch Guided → Mock mid-interview | pass | compiled/tested | e15–e17; F-005 fixed so the ending follows the switch |
| 11 | Airplane mode, help needs connection, no retries, drain without duplicates | code-reviewed | — | not simulable headlessly; no automatic help retries (`InterviewController`, `jobs.ts`); outbox dedupes by command ID (Swift `localOutboxPreservesNewerEditDuringAcknowledgement`, server idempotency tests) |
| 12 | Finish → one strength + one gap, quoted, no % | pass (live) | live (provider) | `evaluate-feedback.ts`: grounded/assisted/false-guarantee quote the answer; social-only says there isn't a design yet; h02 fixture |
| 13 | Reflection → Today → Memory with help labels | pass | compiled/tested | e19–e21 ("No explicit help recorded" / "Practised with help") |
| 14 | 5 seeded sessions, search, ≥2-session patterns | partial | compiled/tested | i04, i05 search; patterns endpoint filters ≥2 sessions (server) and the UI never shows patterns (F-018) |
| 15 | Past session → similar question, old unchanged | pass | compiled/tested + server test | i06–i10; "branches a completed interview moment without changing the source" |
| 16 | Replace with provider failure → old kept, Retry | pass | compiled/tested | i01–i03 |
| 17 | Second prepare while active → refusal | pass | compiled/tested + server | h06; server `active_attempt` 409 copy |
| 18 | Stale-revision write → conflict sheet | code-reviewed + server test | — | RootView conflict sheet; "commits exactly one answer snapshot and rejects stale or competing devices"; not driven live |
| 19 | BYOK invalid refused, no managed fallback, remove | pass (server) | compiled/tested | http.test BYOK case extended: cancel of dependent jobs, default model, `credential_required` after removal; g04 UI (F-006) |
| 20 | Largest type + VoiceOver | partial | compiled/tested | k01–k07 at AXXXL; VoiceOver labels checked by identifiers/labels in tests, not with VoiceOver running |
| 21 | Reduce Motion feedback arrival | pass | compiled/tested | l03, l04 |
| 22 | Widget minimal projection | pass | compiled/tested | Swift `widgetProjectionExcludesPrivatePractice` |
| 23 | Delete account → Welcome, local data gone | server-tested | — | "deletes a redeemed invitation and all account data after Clerk deletion"; client path `signOut(deleting:)` clears store; not run live |
| 24 | Full gate | see table below | compiled/tested | |

Final gate, run once from the final tree, then the whole script again after harness fixes (the mandate's rule):

| Run | typecheck | `bun run test` | `swift test` | `check-ios.sh` (gen + Swift + build + 65 XCTests) | `check-ios-launch.sh` |
| --- | --- | --- | --- | --- | --- |
| 1 (13:12–13:52) | exit 0, 0.8 s | 147/147, 5.7 s | 51/51, 5.3 s | exit 65: 62/65, 3 harness failures (F-021, F-022, F-023) in 1750 s | green, 20.6 s |
| 2 (13:53–14:24) | exit 0, 0.8 s | 147/147, 5.9 s | 51/51, 1.9 s | exit 65: 64/65, F-022 again (editor fully under the footer at AXXXL; the test now scrolls until it clears the Send row) in 1787 s | green, 9.0 s |
| 3 (14:24–15:05) | exit 0, 0.8 s | 147/147, 6.0 s | 51/51, 2.3 s | **exit 0: 65/65, 0 failures** in 1779 s (`** TEST SUCCEEDED **`) | green, 12.2 s |

Run 3 is the record for step 24. Logs: `/tmp/final-gate.log`, `/tmp/final-check-ios.log` (runs 1–2 kept as `*-run1.log`, `*-run2.log`). The 145 PNGs under [finish-report/shots](finish-report/shots/) are from run 3's build: `a*`–`d*` the original audit tour, `e*`–`l*` the finish-pass walkthroughs (default and largest type, dark and light, Reduce Motion).

F-021 | P3 | 5 | Fixture | The completed Library attempt had no reflection, so the "similar question" step found no "Practise this next" button; a real completed attempt always has feedback. | Fixture realism. | Fixture attempt carries a reflection. | run 3 | fixed
F-022 | P3 | 5 | UITests `testAccessibilityTextEditor` | At AXXXL the editor sits entirely under the two-row footer after the question re-expands; XCUITest still reports it hittable and taps the footer. A person scrolls. | Harness. | Scroll until the editor's top clears the Send row, then tap its top. | run 3 | fixed
F-023 | P3 | 5 | UITests `testWalkK` | `inlineNudge.isHittable` checked while the keyboard was still animating in at AXXXL; passed in isolation, failed in the full suite. | Harness timing. | Check before focusing the editor. | run 3 | fixed

## Material decisions made without you

- **D-1 Example adopt/append/undo = not applicable.** The acceptance script's step 9 describes the pre-September `PracticeView`/`HelpView` adoption flow. The shipped Interview room makes examples read-only popups (architecture, 9 Sept); the adoption code and server routes still exist but no screen reaches them. I treated the step as satisfied by "read-only until adopted" and did not rebuild adoption. Alternative rejected: wiring Append/Undo into the popup (new UI, contradicts the quiet-room decision).
- **D-2 Completion carries the style (F-005).** Alternative rejected: sending an empty `continue` turn on style change (a paid model call for a UI choice).
- **D-3 Mock debrief ratings left as is.** Strong/Mixed/Weak per area contradicts "no proficiency diagnosis from one attempt"; the cheap-cut doc already proposes three honest states with quotes. Product call; logged, not changed.
- **D-4 Expired session returns to Welcome instead of forcing Sign out (F-016).** Alternative rejected: an in-app "Sign in again" button on the alert (Clerk's sign-in sheet needs the Welcome stage's providers anyway).
- **D-5 Mock openers get their own layout instruction (F-019)** rather than post-processing bullets out of generated prompts. Alternative rejected: stripping `• ` lines server-side (would produce prompts that lose information mid-sentence).
- **D-6 Dead code left in place** (`HistoryView`, `patterns`, `PracticeView`/`HelpView`, the Recall catalogue decks). Your rules say don't delete unasked; listed under leftovers.

## Doc updates

- [architecture.md](architecture.md) "Finish pass — 9 October 2026": completion `guidanceMode`, expired-session behaviour, BYOK UI rules, mock opener instruction, footer/editor accessibility rules, fixture flags, and a correction to "Model and prompt policy" (it still named gemini as the only model; the code has used DeepSeek + gpt-6-luna since 5 October).
- [operations.md](operations.md): `scripts/audit-shots.sh`, the new fixture flags, Reduce Motion via `simctl spawn defaults`.
- [openapi.json](../packages/contracts/openapi.json): `guidanceMode` on the completion body; `remaining`/`limit`/`resetsAt` on voice capabilities were already in the WIP code and are now in the document (regenerated with `bun run contracts`).
- Fixtures: none changed (the new field is optional).

## Honest leftovers

- **Not provable here:** anything behind Sign in with Apple on the simulator — invite redemption UI, live generation in the app, live follow-ups in the app, revision conflict sheet, BYOK sheet against the Worker, account deletion → Welcome. All have server tests; the client paths are exercised in fixtures or reviewed.
- **Physical iPhone only:** VoiceOver with the screen reader actually running (announcements of arriving feedback and tips), keyboard dictation, haptics, voice room audio levels.
- **P3 not done:** F-011 (help popup fixed detent leaves a blank band), F-015 (Library search discoverability, native behaviour), F-018 (dead code).
- **Product tensions open:** D-3 (debrief ratings); the vision's "Exploring — 4 October" direction (less Bit, no Write/Talk switch, light default) describes the next redesign and was deliberately not acted on.
- Development Worker was not deployed; the server changes (completion `guidanceMode`, mock opener instruction) are live only in the local test runtime. The new client is safe against the current Worker: `answerSchema` is a plain `z.object`, which strips unknown keys, so an older Worker accepts the request and ignores the style. Deploy before relying on the ending matching a mid-interview switch.

## Numbers

- Iterations: 3 full walk passes (baseline, after Phase 1 fixes, after Phase 2–4 fixes), 3 full gate runs (the first two failed only on harness timing at accessibility sizes), plus targeted re-runs.
- Findings: 23 — P0 0 · P1 0 · P2 7 (F-001, F-002, F-005, F-006, F-013, F-016, F-019) · P3 16. Fixed 20, open 3 (all P3: F-011, F-015, F-018).
- Tests added: 1 D1 (completion style), 1 D1 case extended (BYOK cancel/remove/no-fallback), 1 Swift (completion write), 8 UI walkthroughs (`testWalkE`–`testWalkL`), 4 UI tests repaired.
- Real provider calls: 64 (feedback 4, questions 8+8+8, personality 24+1 debug, teaching ~9 cases × turns ≈ 14, personalization 6, recall ≈ 8; see `/tmp/evals`). Cost reported by the scripts ≈ $0.05. No Clerk, deploy, migration or secret changes.

## Findings log

`F-### | P0–P3 | phase/day | screen or module | what a user experiences | root cause | fix | verification | status`

### Phase 0 baseline — 9 October 2026

Environment: Xcode 27.0 (27A266a), one iPhone 17 simulator (iOS 27, `32C4E22D-…`), uncommitted WIP from the 3 October taste pass left in place.

| Step | Result | Duration |
| --- | --- | --- |
| `bun install --frozen-lockfile && bun run typecheck` | green | <1 s (no changes, incremental tsc) |
| `bun run test` | green, 146/146 in 15 files | 5.7 s |
| `swift test --package-path apps/ios -j 2` | green, 50 tests in 7 suites | 8 s |
| `sh scripts/check-ios.sh` | build green; XCTest 57 tests, **4 failed** (F-001–F-004) | 1374 s |
| `sh scripts/check-ios-launch.sh` | green, signed Debug launch | 37.6 s |
| `AuditScreenshots` (5 tests) | green | 71 s + 41 s + 150 s + 170 s + 180 s |

Findings:

F-001 | P2 | 0 | UITests `testAccessibilityTextEditor` | At AXXXL the test re-tapped Original question and read "Collapsed" instead of "Expanded". | Two causes: the footer's `Need a nudge?` wrapped letter-by-letter at accessibility sizes and sat under the swipe-down path, so a swipe opened the nudge sheet; and the test tapped during the keyboard's interactive dismissal. | Footer uses `ViewThatFits`: one row normally, nudge on its own line when the row no longer fits ([InterviewView.swift](../apps/ios/Drillbit/InterviewView.swift)); the test dismisses a stray popup and waits for layout. | `xcodebuild test -only-testing:…/testAccessibilityTextEditor` passed 25.3 s | fixed
F-002 | P2 | 0 | Interview editor at accessibility sizes | At AXXXL the empty editor is ~400 pt tall (6-line minimum × huge line height), pushing the composer's centre below the screen; XCUITest couldn't focus it, and a person sees a wall of empty space. | `GrowingInterviewEditor.sizeThatFits` enforced six lines regardless of content size category. | Three-line minimum at accessibility categories ([GrowingInterviewEditor.swift](../apps/ios/Drillbit/GrowingInterviewEditor.swift)). | `testAccessibleInterviewDocument` passed 13.3 s | fixed
F-003 | P3 | 0 | UITests `testCancellingAssistanceUnlocksImmediately` | `buttons["Need a nudge?"]` matched both the footer button and the ••• menu item after the taste-pass rename. | Test selector ambiguity; both controls are intentional. | Same predicate `testInterviewJourney` already uses (`identifier != inlineNudge`). | passed 21.0 s | fixed
F-004 | P3 | 0 | UITests `testOriginalQuestionExpandsAndScrollsInline` | With the 18-paragraph fixture question, collapsing moved the editor ~600 pt; the test tapped the stale frame. | Harness timing. | Wait for the editor to be hittable after the collapse. | passed 25.9 s | fixed

### Phase 1 — Day 1, new person, fixtures (`testWalkE/F/G` in [AuditScreenshots.swift](../apps/ios/UITests/AuditScreenshots.swift), shots under `finish-report/shots/e*,f*,g*`)

F-005 | P2 | 1 | Interview → Finish | Switched Session style to Mock mid-interview (clock appeared), finished at once: feedback came back as "Practice complete / One idea to carry forward", not the debrief the clock promised. | The style only reached the server with the *next* turn; Finish never sent it, so the reflection used the generated mode. Fixture completion read `challenge.guidanceMode` too. | `POST /complete` accepts optional `guidanceMode`, stored in the lifecycle transaction before the context freeze and only by the winning command ([store.ts](../apps/api/src/store.ts), [domain.ts](../apps/api/src/domain.ts)); the outbox reads the cached per-attempt style when draining a completion ([AppModel.swift](../apps/ios/Drillbit/AppModel.swift)); `InterviewController.finish` stamps the mode on the local copy. OpenAPI regenerated. | D1 test "the style chosen at Finish decides the ending" (jobs.test.ts, 13/13); Swift `completionWriteCarriesTheFinishingStyleOnlyWhenKnown` | fixed
F-006 | P2 | 1 | Settings → LLM provider | "Remove key" shows in red with no key saved; Model ID is required by the client even though the server defaults it, so a person with just a key can't save; nothing says what happens if you pick "My OpenRouter key" and never add one (every generation then fails with "Add or replace your OpenRouter key"). | View never checked for a saved credential; `KeyInput.model` non-optional. | Remove key only with a credential; Model ID optional (omitted when blank); key field says "Replace with a new key" once one exists; footer warns when BYOK is selected with no key; explicit removal switches back to Included AI and the footnote says so ([SettingsView.swift](../apps/ios/Drillbit/SettingsView.swift)). | compiled; `testWalkG` shot g04 | fixed
F-007 | P3 | 1 | Settings, Prepare | Section header "Appearance" over a row labelled "Appearance"; "Session style" header over a "Session style" row. | Redundant headers. | Headers dropped. | shots g01, e02 | fixed
F-008 | P3 | 1 | Settings → Learning plan | Objective reads "Strengthen up my skills" (ungrammatical) and differs from setup's "I want to get sharper" for the same value. | Two copies of one list. | Settings uses setup's three labels. | shot g02 | fixed
F-009 | P3 | 1 | Settings → Delete account | Alert title "Delete Account?" is title case; every other alert is sentence case. | — | "Delete your account?" / "There’s no undo." | shot g07 | fixed
F-010 | P3 | 1 | Testability | No way to kill and relaunch a fixture run and keep local drafts (in-memory store), so step 6 of the acceptance script couldn't be driven. | Fixture container is in-memory by design. | `--fixture-persist` (temp-dir store) and `--fixture-persist-reset`, Debug only ([DrillbitApp.swift](../apps/ios/Drillbit/DrillbitApp.swift)). | `testWalkF_DraftSurvivesRelaunch` | fixed
F-011 | P3 | 1 | Nudge / Example sheet | Fixed 360 pt detent leaves a large empty band between a one-line nudge and "Got it". | Fixed detents. | — | shot e14 | open
F-012 | P3 | 1 | Tooling | No single command regenerated the audit screenshot set. | — | [scripts/audit-shots.sh](../scripts/audit-shots.sh): runs `AuditScreenshots` (all or named tests) and exports PNGs by attachment name. | used for this report | fixed

### Phase 2 — the first two weeks (`testWalkH/I/J/K/L`, shots `h*`–`l*`)

F-013 | P2 | 2 (day 3) | Interview room | While the document scrolls under the footer, the draft placeholder "Answer or ask a question…" shows through between Talk and the nudge (shot h04 before fix). | Footer had no background; `safeAreaInset` content is transparent. | Footer paints `AppPalette.background`. | shot k03/k04 after | fixed
F-014 | P3 | 2 (day 5) | Question preview after a failed replacement | The failure message sits under "THE SCENARIO" with a blinking caret that never stops, as if a question were still coming. | The empty title segment keeps its placeholder caret regardless of failure. | Placeholder only while no failure is shown ([QuestionFlow.swift](../apps/ios/Drillbit/QuestionFlow.swift)). | shot i02 | fixed
F-015 | P3 | 2 (day 7) | Library | The search field is hidden until you pull the list down; nothing says search exists. | Standard `.searchable` behaviour in a `List` under a large title. | — (native; documented) | shot i04/i05 | won't fix
F-016 | P2 | 3 | Expired session | A 401 with no Clerk session left the person inside the app with a recurring "Sign in again" alert and no way back to sign-in except Sign out, which demands discarding unsynced edits. Vision: "Reauthenticate when sync or help needs it; the local draft survives". | `refresh()` only raised an alert. | When Clerk reports no session, drop to Welcome without clearing the local store; drafts stay keyed by account ([AppModel.swift](../apps/ios/Drillbit/AppModel.swift)). | compiled; not reproducible in fixtures or against development Clerk without revoking a session (leftover) | fixed, live-unverified
F-017 | P3 | 2 (day 9) | Scheduler | Architecture promises a 15-minute-early cron candidate and a seven-day inactivity pause; the Worker's cron only reconciles jobs and the daily question is written on the first visit of the day (`daily.ts`). Nothing generates unattended, so "no backlog, no guilt" holds trivially, but the doc described behaviour that isn't there. | Doc drift. | Noted in the finish-pass section of architecture.md; code unchanged. | `testWalkJ`: exactly one question after a gap | fixed (doc)
F-018 | P3 | 2 (day 14) | Memory patterns | `/v1/memory.patterns` (≥2-session filter) is decoded by the app and never shown; `HistoryView` ("All sessions", searchable) is defined and unreachable. Evidence per session is what the UI shows, which already states help as "Practised with help / No explicit help recorded". | Legacy code paths left after the Library/Evidence redesign. | Left in place (no deletes unasked); no claim in the UI exceeds its evidence. | code review | open (dead code)

### Phase 3 — failure and recovery

Walked against the vision's table by code review plus the server suite (146 tests, including stale completion, completion/help races, cancelled help, one-active-challenge, start vs replacement, concurrent adoptions, voice freeze) and fixtures where one exists:

| Event | Observed | Status |
| --- | --- | --- |
| Generation/replacement fails | Preview shows the failure and "Back to preparation"; Home keeps the old question (shots i02, i03). | pass |
| No network | Writing works (local store); help popup shows the transport's literal message and "Your reply is unchanged." when none; no automatic retries (`InterviewController.watchResponse` has none; help jobs have no provider retries). Not simulable headlessly on the simulator. | code-reviewed |
| Session expires | F-016. | fixed |
| Help dismissed or stopped | Cancel marks the turn cancelled locally and server-side; a late reply is never stored (server test). `testCancellingAssistanceUnlocksImmediately` green. | pass |
| Draft changes during help | Interview room never inserts help; examples are read-only (Interview room decision, 9 Sept). | pass by design |
| Finish races help | `complete` cancels pending help/interview jobs in the lifecycle batch; "completion wins over a late provider result" test. | pass |
| Revision conflict | Conflict sheet with cloud answer, local answer export, explicit choice (RootView). Server 409 test. Not driven end-to-end here (needs a live account). | code-reviewed |
| Voice interrupted | Existing `voiceJourney` UI tests and voice server tests. | pass |
| Feedback fails | Reflection shows "Your answer is saved…" and Retry feedback for a failed summarize job. | code-reviewed |
| App killed | `testWalkF` (draft) and pending-command recovery on relaunch (`InterviewController.load → recover`). | pass |

F-019 | P2 | 4 | Interviewer (live) | Mock openers were generated with the key-facts bullet layout (`mock-has-facts` on 2/2 mock combos), so a Mock round opened like a Guided brief instead of an interviewer speaking. | The generic `question_structure` instruction outranked the one-line mock exception. | `generationRequest` sets `mockOpener`; `questionFormattingInstructions(enabled, mock)` swaps in a spoken one-paragraph structure ([formatting.ts](../apps/api/src/prompts/formatting.ts), [generation.ts](../apps/api/src/generation.ts), [ai.ts](../apps/api/src/ai.ts)). | `evaluate-questions.ts` run 3: both mock prompts one paragraph + ask, no bullets (16 live calls across runs 1–3) | fixed
F-020 | P3 | 4 | Evaluators | `evaluate-personality.ts` and `evaluate-teaching.ts` used `provider.sort: latency` and strict `JSON.parse`; production pins `FAST_PROVIDERS` and tolerates a trailing-brace truncation. The first run crashed on a provider that production never routes to. | Script drift. | Both scripts use `FAST_PROVIDERS` and `parseModelJSON`. | personality 24/24 valid, teaching 84 rows | fixed

## Round 2 — design pass (9 October 2026, afternoon)

Asked for after the first report: remove the Library eyebrow, bring the ticket zoom back, declutter, default to voice, and make the voice room and its orb far better. Before shots of the room are under [shots/before](finish-report/shots/before/); after shots are `m*` (room: m02 preview, m03 live, m05 caption, m06 muted, m08 connecting, m09 idle), `n*` and the refreshed `e06`, `e17`, `e19`, `e20`, `i04`, `i06`.

F-024 | P2 | R2 | Library | "Questions / evidence" eyebrow sat above the list and said nothing the list didn't. | — | Removed ([LibraryView.swift](../apps/ios/Drillbit/LibraryView.swift)). | shot i04 | fixed
F-025 | P2 | R2 | Home → preview | The zoom from the ticket into the preview had been replaced by a plain sheet (3 Oct) because the transition's snapshot kept its own shadow for about a second after dismissal. | The matched source had no shape or shadow of its own, so UIKit drew a default one. | `matchedTransitionSource` now carries the ticket fill, 12 pt radius and the ticket's printed shadow; `navigationTransition(.zoom)` restored ([HomeView.swift](../apps/ios/Drillbit/HomeView.swift)). | `testWalkN_TicketZoom` return frames n04-0…9 match n01 at rest; `testTicketSettlesStraightAfterClosingPreview` green. Device check still worthwhile. | fixed
F-026 | P2 | R2 | Preview | Default answer mode was writing; the product is "we put you in the interview", and talking is the interview. | — | `answerMode` defaults to `talk`; fixtures default to writing unless `--fixture-talk` ([QuestionFlow.swift](../apps/ios/Drillbit/QuestionFlow.swift), [AppModel.swift](../apps/ios/Drillbit/AppModel.swift)). | shot m02 ("Start talking"), `testWalkM` | fixed
F-027 | P1 | R2 | Voice room | The room looked unfinished: a 168 pt dim orb with no depth, a full "Original question" disclosure taking the top third, a "Connecting…" spinner duplicating the state line, allowance text above the button. | Layout and renderer. | One stage: one-line question (opens on tap), 260 pt orb, dot + state line, four-line caption, dock with Start talking → allowance → Write instead ([InterviewVoiceRoom.swift](../apps/ios/Drillbit/InterviewVoiceRoom.swift), `voiceQuestion` in [InterviewView.swift](../apps/ios/Drillbit/InterviewView.swift)). | shots m03–m09 vs before/c09–c12; `testAuditC`, `testWalkM`, voice UI tests green | fixed
F-028 | P1 | R2 | Orb (`SignalPresence`) | Flat scatter: no body, no idle motion, one glow, no "thinking" state, muted barely distinguishable. | Renderer. | New vocabulary: idle breath, connecting sweep arc, dark body + faint limb, depth² shell alpha, hot centre, afterglow after the interviewer's last word, cool-white shell particles that lift when you speak, `thinking` mode (core beat, shell draws in, dust counter-rotates), 60 fps while live/thinking ([DesignSystem.swift](../apps/ios/Drillbit/DesignSystem.swift)). Gradients and fills only; Reduce Motion still a still frame. | shots m03, m05, m06, m08; Swift tests green (rig unaffected) | fixed
F-029 | P2 | R2 | Preview footer | "THE SCENARIO" eyebrow and a footnote under the mode picker in both modes ("Type it out. You can switch…") restated the UI. | — | Eyebrow removed; footnote only while talking (cap · allowance). | shots e06, m02 | fixed
F-030 | P3 | R2 | Home done ticket | "Your line" label above an underlined quote; the underline is the label. | — | Removed. | shot e19 | fixed
F-031 | P2 | R2 | Reflection | Help footnote above the feedback, then "Other moments" listing three branch points under the main action. | — | Footnote moved under the feedback; one "Retry a moment" (the last answer). | shot e17 | fixed
F-032 | P3 | R2 | Session detail / Library question | Eyebrow "Completed session" over a title, inline "Copy or share answer" link, "Explore related questions" footer. | — | Eyebrow dropped, share moved to the toolbar, footer dropped. | shots e20, i06 | fixed
F-033 | P3 | R2 | Tooling | `xcodebuild test` spends up to 10 min after the tests in `simctl diagnose`, holding the result bundle. | Xcode default. | Not changed in the scheme (needs your call); runs here killed the collector after the tests reported. | — | open

Verification: `testWalkE/I/M/N` and `testAuditC`/`testTicketSettles…` green on the new build.

Round-2 gate (16:07–17:04): typecheck exit 0 · `bun run test` 147/147 · `swift test` 51/51 · `check-ios.sh` **66/67** in 3292 s · signed launch green. The one failure, `testWalkE_DayOneTextRep` (479 s), happened while the SSH session dropped: typing the 150-word answer took 190 s instead of ~20 s and the simulator was starved. Re-run alone on the same build it passed in 95.6 s (`/tmp/r2c.log`). No code change between the two runs. Screenshots under [finish-report/shots](finish-report/shots/) are refreshed from this gate's build (164 PNGs + 3 before-shots).

Numbers after round 2: 33 findings — P0 0 · P1 2 (F-027, F-028) · P2 12 · P3 19; fixed 29, open 4 (F-011, F-015, F-018, F-033). UI tests 67. Provider calls still 64.
F-034 | P2 | R2 | Home ticket (live daily question) | After the automatic question finished writing, the ticket went blank for about a second, then showed the question. | `ensureHomeQuestion` released `busy`/`preparingDraft` when the job finished, but the challenge only arrived with the following `refresh()`, so Home fell through to the empty ticket for one round trip. | `busy` and the draft stay set until the refresh has placed the question; if bootstrap still lacks it, the challenge is fetched by id ([AppModel.swift](../apps/ios/Drillbit/AppModel.swift)). Fixture flows were unaffected (challenge set before `busy` clears), so this is live-only and reviewable by code; `testHomeAutomaticallyPreparesAndRegenerates` and `testGenerationPreviewAndResume` green. | compiled/tested | fixed

### Round 2b — voice first, no switch, Bit in the room

F-035 | P2 | R2 | Preview | The Write it / Talk it through switch asked a question nobody needs to answer up front. | — | Removed; one **Start** opens the interview out loud (`AppModel.voiceFirst`); Resume returns to where you were; fixtures stay in text unless `--fixture-talk`. | shot m02; `testTalkFromPreviewOpensStraightIntoVoice` | fixed
F-036 | P2 | R2 | Voice room | The particle orb, even improved, was decoration standing in for a person; the question was folded away; "Write instead" sat in the dock beside the voice controls. | — | Orb removed entirely (`SignalPresence` and its renderer deleted). The room shows the whole question on open, then a small Bit as the interviewer's presence — `talking` on measured output, `listening` while you speak, `thinking` while connecting or waiting — the state line and the caption. The keyboard is a toolbar button in every state; the dock holds only voice actions. | shots m03, m05, m09, c09–c16; voice UI tests green | fixed

Gate for 2b: see the final gate row below.
