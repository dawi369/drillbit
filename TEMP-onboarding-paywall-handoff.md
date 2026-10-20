# TEMP handoff: onboarding polish, Free/Pro split, first-run paywall, voice cost

Temporary brief for an implementing agent. Delete once the work and doc updates land. Decisions below were agreed with the product owner on 20 October 2026.

Read first: `AGENTS.md` (copy voice, native UI rules, D1 testing, report format), `docs/product-vision.md` (positioning, first run, Bit), `docs/architecture.md` sections “First run and free reps” and “Plans, paywall and voice metering”, `docs/productionize-plan.md`. The working tree has uncommitted WIP; don't discard it.

## Why

The onboarding is good in voice and structure. The problem was the business model: free gives 3 reps a day, but the heaviest plan a user can build in onboarding is about 5 reps a week. Free covered the whole plan, so a paywall had nothing to sell. Pro now centres on what the positioning sells: **the interviewer, out loud**.

## Current flow (as of 20 Oct screenshots)

1. Welcome 1: "The coding round gets you a callback. The design round gets you hired." Interview-stage timeline, a small text "Next →".
2. Welcome 2: "Grills you like the real one. Wants you to pass." A static sample exchange (push retry → idempotency key), Get started.
3. Setup, 7 steps, each in Bit's bubble with an insight line under the answer:
   01 scenario ("Your side project hits Reddit… What gives first?"), 02 "Where are you right now?" (Interviews are happening → date), 03 familiarity, 04 "Four weeks from now, what's the win?", 05 "How do you think best?" (Talking it out / Typing / Depends), 06 time, 07 plan card ("Here's where we start", "First question's on us").
4. Sign-in (Apple, Google, GitHub): "Your question's ready."
5. Question preview → first rep with coachmark → feedback → Home with tab tour.

## 1. Free vs Pro (agreed)

| | Free | Pro |
|---|---|---|
| First rep (onboarding) | Full Pro experience, voice by default. Doesn't spend the weekly allowance | — |
| Text reps | **3 a week** (rolling 7 days) | Unlimited, hidden fair-use cap |
| Voice | One 3-minute taste a week after the first rep | Unlimited, fair-use cap set from measured cost (§5) |
| Interview depth | About 3 follow-ups and 1 nudge or example | Uncapped |
| Mock interview mode | — | ✓ |
| Daily planned question and interview countdown plan | — | ✓ |
| Feedback, Recall, Library, history | ✓ | ✓ |

**Pricing is undecided.** Don't write prices, trial lengths or plan ids as decisions anywhere. The `.storekit` values are local-testing placeholders only.

Server (`apps/api/src/plans.ts` stays the only place that says what an account may do):
- Replace `FREE_REPS_PER_DAY` with `FREE_REPS_PER_WEEK=3`. The window is "fewer than N distinct `freeRepAt` stamps in the last 7 days"; `resetsAt` = oldest stamp in the window + 7 days. Keep the atomic insert guard, keep a swap counting once, and update `bootstrap.practice` semantics plus OpenAPI and fixtures. Native DTOs stay compatible.
- **First-rep exemption:** the onboarding first rep runs with Pro limits and doesn't spend the allowance. The server grants it **once per account** (an account-level marker set atomically with the first generation), never on the client's word. A practice reset by the developer must not re-grant it unless it's an allowlisted account.
- `FREE_REP_FOLLOW_UPS=3`, `FREE_REP_NUDGES=1`. At the cap the interviewer must **wrap up gracefully into Finish and feedback**, not fail mid-interview. Check how `free_rep_limit` is handled today and change it if it errors. Feedback then shows the existing `ProNudge` ("Pro keeps going").
- `FREE_VOICE_LIFETIME=1` (the first rep's session). Keep the weekly taste (`FREE_VOICE_TASTE_DAYS=7`, `FREE_VOICE_SESSION_MINUTES=3`). Add `FIRST_REP_VOICE_MINUTES` (default 5) for the onboarding session.
- Mock interview is Pro only. Find the guidance-mode enum (Guided / Practice / Mock). Generation, interview and voice-start requests in mock mode return 402 with a distinct reason for free accounts. A mid-interview switch to Mock is blocked the same way.
- Leave the Pro fair-use caps (`PRO_*`) as they are until §5 produces numbers; they're still never shown.
- D1 tests: concurrent starts spend exactly N in the weekly window; the window rolls; the first-rep exemption is granted once under concurrency; the mock gate across all three entry points; graceful wrap-up at the follow-up cap; allowlist overrides.

## 2. Paywall placement (agreed direction)

**Primary: show it right after the first rep's feedback, in the first session.** Most trial starts happen on install day. Feedback is the high point, and this keeps the vision's rule of one real rep before asking for anything. A hard paywall before value is rejected as the default: it's a new category with a trust gap, and voice hasn't been felt yet.

- New Superwall placement `first_rep_complete`. Sequence: feedback arrives and is readable → the existing reminder offer ("Want a nudge tomorrow?") → user taps Continue → soft paywall → Home. Never cover the feedback itself.
- **Experiment arm** (registered in code, off by default, switched on in the Superwall dashboard): `onboarding_plan` on step 07's primary button, skippable, with the first question still free. This runs **before sign-in**, so the Superwall user is anonymous. Verify a purchase there still reaches the Worker after sign-in through the `Transaction.currentEntitlements` sweep in `Plan.swift`, and handle `entitlement_taken` sensibly. Compare arms on net revenue per install, refunds and day-7 retention, not trial-start rate.
- New placement `mock_interview` wherever Mock is chosen. Keep `practice_rep` and `voice_session`. The server stays authoritative: placements only decide whether to offer the paywall, and 402s still do the rest.
- Superwall user attributes, **categorical only**: goal/situation, familiarity, practice mode, minutes, `hasInterviewDate`, `daysUntilInterview`, the first rep's topic area. **Don't send answer text, feedback quotes or other private practice content to Superwall** (AGENTS.md). The feedback screen right before the paywall already carries the personal proof.
- Paywall content (built remotely in Superwall; write the copy in the project voice, checked against `WelcomeView.swift`):
  - A header personalized by attributes, e.g. "12 days to your interview. Practise it out loud."
  - At most 2 plans. The default selection can differ by audience (interviewing vs learning) through Superwall audience filters.
  - A visible close button from the first frame, plus "Keep free" stating what free includes.
  - A trial timeline only if a trial exists, and it must be true. "We'll remind you before it ends" appears only when notifications are authorized and a local reminder is actually scheduled from the transaction's dates. Otherwise leave the line out.
  - No decline-discount by default (experiment only).
  - Verify VoiceOver and large text on the remote paywall separately.
- Fixtures and UI tests: first rep → feedback → paywall shown once → dismiss → Home; purchase via `Simulate purchase`; the `onboarding_plan` arm behind a launch flag.

## 3. Onboarding changes

| # | Change | Pri |
|---|---|---|
| 1 | **Make the first rep short:** voice by default when step 05 is Talking it out; one concrete decision; the interviewer wraps up after about 2–3 exchanges and goes to feedback in about 3–5 minutes. Users who quit mid-rep never see the paywall, so speed to feedback matters most. Use a first-rep flag in generation and the interview prompt, not a new mode | High |
| 2 | **Plan card (07) as a real reveal:** when there's a date, show the countdown ("12 days until your interview"); name the first 3 sessions by area; state the practice mode. No fake "building your plan" loader (the vision rules out animation standing in for thinking). Fix the copy "Data & storage and Scale & performance" → "Data & storage, then scaling" | High |
| 3 | **Drop step 04** ("Four weeks from now, what's the win?"). Derive the goal from 02 (Interviews are happening → interview goal with the existing date reveal; otherwise understanding) and keep it editable in Settings. Keep every profile field that generation and personalization read (`practiceProfile`, the interviewer's opener). The flow becomes 6 steps | High |
| 4 | **Scenario step 01 gets a reveal** after answering: one line teaching the answer (e.g. "Usually the database. Everyone wants the same rows at once."), using the existing insight-line slot. "No idea yet" gets a kind version | High |
| 5 | **Welcome 2 becomes playable,** as the 3 Oct decision describes: messages appear turn by turn and the user taps "Retry it". Scripted, no model call; Get started is always available; respect Reduce Motion | Med |
| 6 | **Welcome 1's CTA** becomes the same primary button as every other screen, not a small "Next →" link | Med |
| 7 | **First-rep coachmark** must not cover the composer. Anchor it above Talk. Copy: "Rather say it? Talk switches to voice. Typing counts the same." | Med |
| 8 | **Home after the first rep** acknowledges it ("1 rep done", linking to that feedback) before "NO. 001"; today the rep seems to vanish | Med |
| 9 | **Home tab tour** says "Two more tabs. Recall and Library" but there are three other tabs (Recall, Library, Bit). Fix the count or include Bit | Low |
| 10 | **Truncated option subtitles:** 02 "On the job" ("Tickets, yes. Designing a whole system,…") and 05 "Talking it out" ("Like the real interview. The interviewer t…"). Shorten them or allow two lines (Dynamic Type) | Low |

Copy:
- Welcome 1: "Drillbit is the complete package for that round." is generic; try "Drillbit is the practice partner for that round."
- Preview: drop the grey "Guided practice helps you structure the approach."
- Ask the owner before changing it: "practise" (British) appears in UI copy; switch to "practice" if the market is the US.

Explicitly **not** changing:
- Bit on the sign-in screen.
- The preview title vs the workspace nav label differing: both are generated per question; document it (§6).

## 4. Where these live

`apps/ios/Drillbit/`: `WelcomeView.swift`, `SetupView.swift`, `FirstUse.swift`, `QuestionFlow.swift`, `InterviewView.swift`, `InterviewVoiceRoom.swift`, `ReflectionView.swift`, `HomeView.swift`, `Plan.swift`, `LiveVoice.swift`, `AppModel.swift` (`mayStartRep`, `voiceFirst`). API: `apps/api/src/plans.ts`, `practice-gate.ts`, `voice.ts`, `ai.ts`, `generation.ts`, `wrangler.jsonc`. Contracts: `openapi.json`, `packages/contracts/fixtures`.

## 5. Measure voice and text cost (before setting Pro caps or prices)

What exists:
- `voice_sessions.usage_seconds` is filled from the provider's `session.usage.updated` / `session.closed` events (`LiveVoice.swift`, `voice.ts`). The provider is OpenAI live sessions, `gpt-live-1`.
- `ai_runs` stores tokens and `cost` per text model call through `recordUsage` (`ai.ts`), including `voice_reasoning` (delegated during voice, via OpenRouter).
- `scripts/measure-inference.ts` measures latency only, not cost.

To do:
1. Look up `gpt-live-1`'s billing unit and rates in OpenAI's docs (per second, or audio/text tokens); don't guess. Check whether the usage events carry a token breakdown beyond `seconds`; if they do, persist it (additive columns). Put the rates in env (for example `VOICE_RATE_*`), used only by reporting.
2. Confirm `ai_runs.cost` is actually populated (OpenRouter may need usage accounting enabled on the request). Add a nullable `challenge_id` to `ai_runs` (additive migration) so cost per rep is exact, not joined by time.
3. Add `scripts/measure-costs.ts`, which reads D1 and prints **aggregates only** (no content, no account ids):
   - cost per voice minute, typical and p90, by session-length bucket (0–3, 3–10, 10–20 min), including the delegated reasoning in each session
   - cost per text rep (generation + turns + nudges + feedback + Recall writes)
   - cost of the first rep
   - cost per free user per week at the new limits
   - worst-case Pro user per month at the current fair-use caps
4. Cross-check: run voice on a dedicated OpenAI project key and compare that project's billed total with the computed total for the same period.
5. Getting data: the dev D1 holds mostly the owner's sessions. The owner runs a small set of real voice sessions on a physical device at each length bucket. Report which numbers are measured and which are extrapolated.
6. Write the table into `docs/productionize-plan.md`. Propose Pro caps and session length so that a heavy user stays under a stated share of net revenue once pricing exists. The owner decides.

## 6. Doc updates (same change set)

- Remove pricing from the docs: `docs/productionize-plan.md` ("Prices are yours; … 7-day free trial…") and `docs/operations.md` should say pricing and trial terms are undecided. Mark the `.storekit` prices as test placeholders in `operations.md`. Leave the competitor prices in `docs/design/app-audit/steal-list.md` (research, not decisions).
- Replace the Free/Pro table in `productionize-plan.md` and the "Plans" paragraph in `architecture.md` with §1. Update `product-vision.md` "First run and the practice gate" for the paywall after the first rep, the experiment arm, the shortened first rep and the 6-step setup.
- `architecture.md`: the new placements (`first_rep_complete`, `onboarding_plan`, `mock_interview`), the first-rep exemption marker, the mock gate, the weekly window, `ai_runs.challenge_id`, the cost script.
- Document that a question has a generated full title (preview) and a generated short label (workspace nav), and that they differ on purpose. Confirm the field names in code first.

## Needs from the owner

- Superwall dashboard: placements `first_rep_complete`, `onboarding_plan` (campaign off), `mock_interview`; the paywall design; the user attributes above available as audience filters.
- Pricing and trial terms (open; blocks only the final paywall content).
- Real voice sessions on device for §5.
- Optional later: US web checkout through Superwall would need a second entitlement source in the Worker (today only Apple-signed transactions are trusted). Not in scope.

## Report format

Per `AGENTS.md`: separate what is compiled/tested, what is live-service verified and what is physical-device verified. Run the D1 tests, `scripts/check-ios.sh` and the UI tests with fixtures.
