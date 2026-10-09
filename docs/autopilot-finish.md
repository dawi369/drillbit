# Autopilot: finish Drillbit

Paste everything below this line into the agent as the task prompt.

---

## Mandate

You are taking Drillbit the last mile. I am done hand-steering this project; you own it until it is a finished app. "Finished" means: a new person can install it, sign in, get a question, practise several times over two weeks, get honest feedback, look back at what they did, change settings, recover from every ordinary failure, and never hit a dead end, a placeholder, a confusing state, a stale string or a crash. Not "the features exist" — "I would hand this to a stranger and not apologise."

You do this by **using the app the way a real person would, repeatedly, over a simulated first two weeks**, writing down everything that is unfinished, wrong, slow, ugly, confusing or dull, fixing it, and going around again until a full pass produces nothing you would fix. Then you run the final acceptance script and hand back a report.

Read first, in this order: `AGENTS.md`, `docs/product-vision.md`, `docs/architecture.md`, `docs/operations.md`, `docs/design/app-audit/notes.md`. The vision is the bar for feel and tone; the architecture is the record of what is built; where the two disagree, the shipped app plus an updated architecture doc wins unless the vision describes an unbuilt decision — then log it as a gap, don't silently build it.

## Non-negotiables

- Preserve user work and existing implementations. Improve in place; no rewrites without asking.
- Every change traces to a logged finding. No speculative features, no drive-by refactors.
- Native rules hold: system type, semantic colours, SF Symbols, system controls, 4-pt spacing, 12-pt radius, Dynamic Type, VoiceOver, reduced motion, native keyboard/dictation.
- Voice: a fellow CS student — casual, direct, concrete, a little playful, honest. `apps/ios/Drillbit/WelcomeView.swift` is the reference. Check every new or changed string against it.
- Out, per the vision: streaks/guilt, XP, levels, readiness %, decorative dashboards, animation standing in for thinking, generic praise.
- Credentials and private practice text never reach logs, screenshots in the report, or fixtures.
- API changes update `packages/contracts/openapi.json` (`bun run contracts`) and fixtures; Swift DTOs stay contract-compatible.
- Lifecycle/concurrency changes get tests against D1 (`bun run test`), not mocked happy paths.
- **Git:** leave all work uncommitted in the working tree and stop for review. Never push. (If I want checkpoints, I will replace this line with "commit after each green iteration, conventional message, never push.")
- **Money and shared systems:** managed AI calls cost real money and the development Worker is shared. Use `--fixtures` for every repeated walkthrough. Real-provider runs are limited to the bounded set in the acceptance script and the evaluation scripts; count them and report the count. Do not deploy, run migrations remotely, touch Clerk, rotate secrets, create invites, or change Wrangler config without asking.
- Stop and ask only for: the items above, a genuine product decision the vision doesn't settle, or a blocker you cannot route around after two honest attempts. Otherwise keep going.

## Round 2 — design pass (9 October 2026, after the first report)

The first pass left `docs/finish-report.md` and a green gate. This round is about how the app *feels*. Put the designer's hat on: walk every screen again as the person, and don't stop until you would be proud to show it. Specific asks, each a finding in the report:

1. **Library:** remove the "Questions / evidence" eyebrow row at the top. The list is the screen.
2. **Ticket → preview:** the zoom transition from Home's ticket into the question preview was beautiful; it was removed on 3 October because the transition's snapshot kept its own shadow for a second after dismissal. Bring the zoom back and fix that glitch properly (match the source's shadow and shape), don't just re-enable it.
3. **Clutter:** several screens carry too much at once. Find them (Home when a session is done, the preview footer, Settings, Reflection, the session detail, the Library question page are suspects) and make each more minimal and focused: one idea per block, fewer labels that restate what the content already says, no duplicate ways to do one thing. Remove, don't rearrange.
4. **Default to voice.** "Talk it through" is the default way to answer; writing stays one tap away and remembered once chosen.
5. **The voice room** must be far better: one quiet stage, honest state in text, and a particle agent (the orb) that is genuinely beautiful and reads real audio — richer motion vocabulary (idle breath, listening, thinking, speaking), depth, colour that follows state, never decorative noise. Still Reduce Motion-safe, still frozen offscreen, still 60 fps on device-class hardware.
6. Iterate: change, rebuild, re-walk, screenshot, look, repeat until satisfied. Then run the full gate once more and append a "Round 2" section to the report with before/after screenshots.

## Operating loop

Each iteration is: **baseline → walk → log → triage → fix → verify → re-walk the affected paths**. Do not fix while walking — finish the walk, then fix, so you see the app as a user does rather than as a developer with a half-fixed bug.

### Phase 0: Baseline (once)

1. `bun install --frozen-lockfile && bun run typecheck && bun run test`
2. `swift test --package-path apps/ios -j 2`
3. `sh scripts/check-ios.sh` (generate, Swift tests, simulator build, XCTest incl. `UITests/`)
4. Boot one iOS 26+ iPhone simulator; `sh scripts/check-ios-launch.sh`
5. Run `AuditScreenshots` and look at every screenshot before touching anything.
6. Record the baseline: what is red, how long each step takes, which screens exist.

Anything red here is finding #1 onward.

### Phase 1: Day 1, brand-new user

Launch with `--fixtures` on the simulator. You are a CS student with interviews in two weeks who just got an invite. Narrate as that person. For every screen ask: what do I want here, is the one main action obvious, does the copy sound like a person, does anything feel like a developer left it behind, does it feel native, does it respond immediately, is there motion that reports nothing real?

Walk, in full, without skipping: Welcome → sign-in → invite → first Today/Home state → prepare a question (defaults, change focus/kind/difficulty, add an instruction) → the question preview and the interviewer's first line → the interview: write a real answer of ~150 words, send, get the follow-up, ask a question with a line ending in "?", request Nudge, request Example, preview/adopt/undo an example, switch style mid-interview → Finish → feedback (one strength, one gap, both quoted from the answer) → Reflection → back to Today → Memory/Recall → Settings (focus, AI access, BYOK entry and removal, account) → the widget if present → background and return → kill and relaunch (draft and state survive).

### Phase 2: The first two weeks

Simulate the days below. Where time matters (scheduler, "missed days", seven-day inactivity pause, pattern evidence needing ≥2 sessions), drive it through fixtures, seeded local data or the local API/D1 — not by waiting. If no mechanism exists to simulate it, that is a finding (testability gap) and you add the smallest honest one.

- **Day 2:** returns, a question is ready. Resumes nothing, starts clean. Thin, lazy answer (~30 words). Feedback must say what is missing, not praise.
- **Day 3:** opens mid-interview from yesterday with an unfinished draft. Resume. Finish. Then tries to prepare a second question while one is active — must be told clearly, never silently replaced.
- **Day 5:** rambling, long answer that asks the interviewer two questions. Mock-interview style. Replace the ready question before starting; the old one must survive if replacement fails.
- **Day 7:** looks at Memory with 4–5 sessions: search, open a completed session, read what help was used (hints/example/draft — never a percentage), request a "similar question" from a past session.
- **Day 9:** missed two days. No backlog, no guilt copy. Scheduler produced exactly one ready question.
- **Day 12:** enters a BYOK key, invalid key never falls back to managed; replaces it; dependent pending help job is cancelled; removes it.
- **Day 14:** reviews two weeks: are patterns shown only with evidence from ≥2 sessions, is anything claiming to measure what it can't, would this person feel they got better at explaining, not at collecting? Then deletes the account and confirms what the app says and what happens on relaunch.

Repeat Phase 1 and 2 with these variations at least once each:
- Dynamic Type at the largest accessibility size — layout must change, not clip.
- VoiceOver on: state changes announced, streamed tokens not read token by token, every control labelled.
- Reduce Motion on.
- iPhone SE-class width and the largest iPhone.
- Dark mode.

### Phase 3: Failure and recovery

Every row of the "Failure and recovery" table in `docs/product-vision.md` is a test case; walk each and compare what you see against the "What the person sees" column and the invariant. Additionally: airplane mode mid-answer then send; airplane mode then Finish (queued, not lost); expired session when sync is needed; kill the app during help generation and relaunch; two devices/stale client editing the same draft (drive via local API with a stale revision); provider failure on generation (keep existing question, Retry); Stop during help (partial marked incomplete, answer restored). D1 concurrency paths get a test if one does not exist.

### Phase 4: Feel, look and UX polish

Only after Phases 1–3 are clean for one full iteration. Go screen by screen with the screenshots from `AuditScreenshots` side by side and ask: is this the quietest, most native, most confident version of this screen? Things to hunt: inconsistent spacing or radii, non-semantic colours, text that is a sentence where a label would do (or vice versa), empty states that are empty instead of helpful, transitions that jump, loading states that lie about progress, hit areas under 44 pt, truncated text at large type, controls with no pressed state, duplicate ways to do one thing, a screen with two main actions. The bar for "catchy" is the vision's: motion that reports real state, Bit appearing only where it is allowed and with moods that reflect real state, copy that makes you grin once and then gets out of the way. Do not add decoration. Make what is there feel inevitable.

Run the prompt/tone evaluators once with real provider calls (`scripts/evaluate-feedback.ts`, `evaluate-questions.ts`, `evaluate-personality.ts`, `evaluate-personalization.ts`, `evaluate-recall.ts`, `evaluate-teaching.ts`) and read the outputs as a person would read the feedback. Log every case where the interviewer is generic, praises a thin answer, lectures, asks two questions at once, or breaks the tone layer. Fix prompts, re-run only the affected evaluator.

### Phase 5: Final acceptance

When a complete pass of Phases 1–4 yields zero new findings at severity ≥ P2 and every open P3 is listed in the report as a deliberate leftover, run the acceptance script below, once, start to finish, without fixing anything mid-run. If it fails, fix, and the whole script runs again from the start.

## Findings log

Keep `docs/finish-report.md` open from Phase 0 and append as you go. One line per finding:

`F-### | P0–P3 | phase/day | screen or module | what a user experiences | root cause | fix (commit-free summary, files) | verification (test/UI test/manual sim/live) | status`

- **P0** crash, data loss, security/scoping, money spent without consent, credential exposure.
- **P1** dead end, wrong state, lost draft, lying copy, broken a11y, can't finish a core flow.
- **P2** confusing, slow, inconsistent, placeholder text, off-voice copy, non-native geometry.
- **P3** polish you noticed and would do with another hour.

Fix in priority order. Reproduce first (test, UI test or exact simulator steps), then fix the root cause, then verify with the narrowest check and show the command and result in the log. Never suppress to get green.

## Final end-to-end acceptance script

Run on one booted iOS 26+ iPhone simulator with a freshly erased device (`xcrun simctl erase`), Debug build, `--fixtures` **off** for steps marked LIVE (count them; expected ≤ 12 provider calls), on for all others. Record a screenshot at every numbered step via a UI test or `simctl io screenshot`; save under `docs/finish-report/shots/`.

1. Install, launch. Welcome reads as the reference voice. No sign-in friction beyond Apple's.
2. Sign in with Apple (development Clerk). Invite required; wrong code gets a calm literal message; right code proceeds.
3. Today/Home empty state: one obvious action.
4. Prepare: defaults remembered after first use; instruction field affects one generation. **LIVE:** generate a real question. It names an audience or bounds the system and asks for decisions and tradeoffs. Only title, prompt, constraints are visible.
5. Interviewer's first line is personal to the setup and arrived with the question (no second call).
6. Write ~150 words. Draft autosaves (kill app, relaunch, draft present with cursor state acceptable).
7. Send. **LIVE:** follow-up is one question, on topic, in tone.
8. A line ending in "?" → **LIVE:** interviewer answers instead of evaluating.
9. Nudge → **LIVE**. Example → **LIVE**: read-only until adopted; preview; append; undo restores exact prior text; edit then undo is refused honestly.
10. Switch style Guided → Mock mid-interview; question unchanged.
11. Airplane mode. Type; help says it needs a connection; nothing retries. Airplane off; queued work drains without duplicates.
12. Finish. **LIVE:** feedback is one strength + one gap, each quoting the answer. No percentage, no generic praise.
13. Reflection → Today. Session shows in Memory with correct help usage labels.
14. Seed/fixture 5 more completed sessions across "days". Memory search finds by keyword; patterns appear only with ≥2-session evidence.
15. Open a past session → similar question. **LIVE:** fresh question, old one unchanged.
16. Replace the ready question with provider forced to fail → old question kept, Retry offered. Force success → replaced.
17. Second prepare while one active → clear refusal, no silent replace.
18. Stale-revision write via local API → conflict sheet, local draft preserved, cloud version viewable, explicit recovery works.
19. Settings: BYOK invalid key → refused, no managed fallback; valid-format key accepted; remove it.
20. Dynamic Type largest + VoiceOver: steps 3, 6, 12, 13 again; nothing clips, every control reachable and labelled, state changes announced.
21. Reduce Motion: step 12 arrival of feedback still reports state without animation.
22. Widget (if built) shows minimal challenge projection only.
23. Delete account: copy is honest about what happens; relaunch lands on Welcome; local data gone.
24. `bun run typecheck && bun run test && swift test --package-path apps/ios -j 2 && sh scripts/check-ios.sh && sh scripts/check-ios-launch.sh` all green. Paste exit codes and durations.

The script passes only if every step matches with no workaround and no "known issue" footnote at P0–P1.

## What I need back

1. **Working tree** with every change uncommitted (or committed per the Git line above if I changed it). No stray files, no debug flags, no fixture leakage into Release.
2. **`docs/finish-report.md`** containing, in this order:
   - Outcome: one paragraph — is it finished, by the definition above, yes or no, and what single thing you would still change.
   - Acceptance script results: each of the 24 steps with pass/fail, screenshot link, provider-call count, and verification level per `AGENTS.md`: **compiled/tested**, **live-service verified**, or **physical-device verified** (you can only claim the first two; say so).
   - Findings log, complete, sorted by severity then order found.
   - Material decisions and tradeoffs made without me, each with the alternative rejected.
   - Doc updates made (`architecture.md`, `operations.md`, OpenAPI, fixtures) and why.
   - Honest leftovers: P3s not done, anything only testable on a physical iPhone, anything depending on production Clerk/Worker that development can't prove.
   - Numbers: iterations completed, total findings by severity, tests added, real provider calls made.
3. **Screenshots** of every screen in both light/dark and default/largest type, from the final build, under `docs/finish-report/shots/`.
4. **Tests** for every P0/P1 fix and every D1 lifecycle path you touched; UI tests for any flow in the acceptance script that was manual before.
5. **Updated `AuditScreenshots`** so the next person can regenerate the screen set in one run.

Write the report the way `CLAUDE.md` asks: outcome first, dense bullets, links not transcripts, no narration. I should be able to decide "ship or not" in five minutes of reading and then trust the log for everything else.
