# Session styles — 13 September 2026

Current product labels: Guided / Practice (default) / Mock interview. Wire values remain learn_together / coach_me / mock_interview; teaching behavior is unchanged. Earlier evaluation labels below refer to those same policies.

## Behavior

| Mode | Responsibility |
|---|---|
| Guided | Demonstrate one small worked step, explain why it helps, then let the learner try a decision. |
| Practice — default | Learner leads; catch consequential mistakes, poor ordering and unnecessary complexity. Explain a better next step and hand control back. |
| Mock interview | Probe decisions and assumptions without proactively supplying a framework. Answer explicit help requests; retain feedback at completion. |

All three retain the playful, patient practice-partner character. Banter need not become a technical question. Humor targets imaginary systems, not the learner. No hidden requirements, invented progress, automatic finishing or inference of independent mastery from coached work. A valid alternative is not a mistake merely because the model prefers another design.

### Endings — 28 September 2026

Each style ends differently (`endingPolicy` in `prompts/teaching.ts`, feedback prompt `feedback-v3`). The summary job reads the style from the frozen question data and requires that style's extra output, so strict schemas stay free of optional fields. The stored reflection records `guidanceMode`.

| Style | Ending | Extra output |
|---|---|---|
| Guided | Lesson recap: "What you worked out", then "Try it solo" | `lesson { learned[0–3], tryAlone }` |
| Practice | Coaching summary (unchanged) | none |
| Mock interview | Debrief: a verdict first, then how each area landed and what would pass | `debrief { verdict: pass \| borderline \| not_yet, reason, signals[requirements, design, trade_offs, communication], toPass }` |

The mock verdict judges the answer against the round at the stated level, not the person, and it is not a hiring decision. With little technical work, grounding forces `not_yet` with "There wasn't enough design to judge yet." Reflections written before this change have no extra part and render as Practice.

### Mock interview runs on the clock

- The generator sets `minutes` (10–60) for every question; only Mock interview shows it. Pooled and older questions fall back by level (`roundMinutes`).
- Starting a question stamps `startedAt` in the challenge data (start route, Library start, retry moment). The clock counts from it, keeps running if you leave, and then counts overtime. It never ends the round.
- The interviewer receives `interview.timing { limitMinutes, elapsedMinutes }` in text and voice. The mock policy paces it like a real round: steer to the key open decision past halfway, give one short five-minute warning, and invite Finish when time is up.
- Mock hides Nudge and Show an example. Asking for help in words still works, as the policy requires.
- **You scope it.** Mock questions are always open (no constraints, at every level), and the prompt is an interviewer's one-to-three-sentence opener with no numbers. When asked, the interviewer answers scale and requirement questions with concrete, consistent numbers and records them as parameters. The debrief rates scoping under requirements.
- **Hidden phases.** `mockRound` sends the interviewer `timing { limitMinutes, elapsedMinutes, phases, deepDive, curveballUsed }`. The phases are requirements (15%), high-level design (to 50%), deep dive (to 85%) and wrap-up, scaled to the round's minutes, and `deepDive` is the question's path. The interviewer closes each phase when its time passes and never shows the plan. The app shows only the clock.
- **One curveball.** Mock's strict reply schema has `curveball`. The interviewer changes one requirement realistically in the deep dive once the candidate has a working design. The server keeps only the first `curveball: true` per round, so a second one can't happen even if the model tries. The debrief judges how the candidate adapted.
- Company targeting (future): a target company's format would extend the mock policy, time limit and debrief bar in `teaching.ts`. The question contract and grounding rules would not change.

### Guided holds your hand

- **A visible path.** The generator writes `path`: 3–5 short steps a strong answer works through, in order. It is a roadmap and adds no requirement. Guided interviews get `interview.guidedPath { steps, current }`. The interviewer takes the steps one at a time, names each new one, and reports `step` on every reply. The app pins a step rail under the title ("Step 2 of 4 · Sketch the API"). Older and pooled questions have no path, so no rail.
- **Answer by tapping.** Every Guided reply that continues the exercise ends with one small question and 2–3 `choices`, each under 60 characters. When a worked example would help, the last choice is "Not sure, show me". The app shows them as chips above an empty reply box. Tapping one sends it as the answer, and typing still works. "Not sure, show me" makes the interviewer demonstrate the step and then ask you to apply it.
- Both fields exist only in Guided's strict reply schema (`interviewer-teaching-v4`). Other styles never return them, and replies that omit them default to no choices at step 0. Voice keeps its own spoken schema.

Choose **Session style** in Prepare or the interview’s … menu. Choices apply to that attempt, not global difficulty. Changing modes preserves the draft and sends no paid request. A pending reply or live audio blocks mode changes. Text and voice share the same conversation policy; voice adds spoken-delivery constraints.

## Implementation

- `apps/api/src/prompts/interviewer.ts`: shared character and immutable edition resolver; new default `interviewer-teaching-v3`, with bounded current-draft policies for ephemeral Nudge and Example assistance.
- `apps/api/src/prompts/teaching.ts`: three teaching policies and truthful-progress policy, edition `teaching-v1`.
- `apps/api/src/prompts/voice-context.ts`: bounded dialogue projection and the same message builder used by text. Fragment timing/IDs do not become model context.
- `guidanceMode` is optional/additive. Existing quick/standard/in_depth values remain accepted for old clients, but do not represent teaching responsibility. Missing mode resolves to Coach me; old requests preserve a recorded mode. No migration.
- Mode selection persists locally per account/attempt, and reaches the cloud on preparation, accepted reply, or voice start. Job retries retain their captured mode. Merely opening a selector never generates an answer.
- A 12-second provider deadline and 15-second native delivery gate prevent an unanswered delegation from becoming an indefinite wait. A late result cannot follow a timeout fallback. No extra model is used to repair a poor response.

## Live model evaluation

`bun scripts/evaluate-teaching.ts` uses the root environment's OpenRouter key and writes synthetic results under ignored `.local/`. Optional `EVAL_CASE` narrows cases; `EVAL_REASONING` is an experiment override, not production configuration. The script pairs text and voice-reasoning requests against the same preceding conversation. It does **not** open a GPT-Live audio session.

Reviewed 96 responses across the shared-pipeline candidate, holdout and retry-regression batches: all three modes, text and voice reasoning, approach selection, scale arithmetic, premature architecture, direct examples, banter, anxiety, waiting complaints, response-size trade-offs, payment retries and cold-start caching. All 96 completed and parsed; schema success is separate from product acceptance. Provider-reported combined cost was $0.10038. Complete-response medians were 1.63 seconds for text and 1.38 seconds for voice reasoning; maxima 3.19 and 3.09 seconds respectively. These are direct provider timings, not app latency or speech-to-first-audio timings.

Useful observed responses:

- Learn together supplied an order-status GET path and a minimal status/updatedAt example, explained why a small response matters, then explored unchanged state.
- Coach me recommended client needs → contract → load/reliability before selecting infrastructure. It corrected 10,000 clients polling every five seconds to 2,000 average RPS and distinguished burst capacity.
- Mock asked which requirement justified six microservices; in the retry holdout it probed what happens when a charge succeeds but its acknowledgement is lost.
- Banter often stayed social: “Fair enough, we'll keep the rodent workplace conditions confidential for now.” Waiting complaints stopped eliciting promises of background checking or a few more seconds in the shared-pipeline sample.
- Cold-cache examples identified missing first-start data. Explicit response-body wording preserved the low-complexity API alternative.

### Product acceptance remains partial

The behavior is more useful, but not consistently at the final personality/correctness bar:

- The ambiguous phrase “GET … with a small JSON body” frequently triggered an invented request-body correction even though the following sentence described a response. Explicit RESPONSE wording passed. Do not count that ambiguous case as accepted.
- One Coach response still claimed retries guarantee at-least-once delivery; retries alone do not. Prompt guidance explicitly rejects this, but instructions are not a correctness guarantee.
- Mock sometimes coaches too much. Generic praise, unnecessary follow-up questions and some code-like syntax in spoken examples remain.

An 18-response medium-reasoning experiment on Gemini 3.1 Flash Lite improved the sampled retry corrections but still misread the ambiguous body in five of six cases. This is historical model-specific evidence. Current GPT-6 Luna interview calls disable reasoning for latency; Luna's quality needs separate acceptance rather than inheriting these results.

No automatic repair inference or brittle domain-specific canned-response replacement was added. Future evaluation should retain these failing cases, measure multi-turn recovery after corrections, and improve grounding without recreating the long voice wait.

## Native and backend verification

- 94 API tests pass against the Cloudflare/D1 test runtime: captured modes, legacy omission/replay, generation persistence, account scope, duplicate inference, failed delegation state and compact/overlapping transcript context.
- 30 native tests pass, including mode persistence with pending commands, draft preservation, legacy decoding and deadline/late-result races. Three simulator UI journeys pass: preparation/current-interview mode changes, largest Dynamic Type selector, and voice/text draft/transcript handoff.
- Visually inspected dark mode selection and largest Dynamic Type in light mode on iPhone 17 Pro. Selection remains native and scrollable; accessibility selected traits are asserted. Spoken VoiceOver and real microphone interruptions were not newly verified.
- Signed simulator build installed and normal app relaunched. No TestFlight upload. Backend deployment and health verification are recorded in operations/acceptance.

Evidence logs: `/tmp/drillbit-teaching-api-release.log`, `/tmp/drillbit-teaching-ui.log`, `/tmp/drillbit-teaching-ui-final.log`; live samples `/tmp/drillbit-teaching-live-shared.jsonl`, `/tmp/drillbit-teaching-holdout.jsonl`, `/tmp/drillbit-teaching-retries-final.jsonl`, and the two medium experiment logs. Inputs are synthetic; private production transcripts are not published here.
