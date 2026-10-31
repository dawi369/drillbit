# Drillbit: the practice experience

### Positioning — 3 October 2026

**Other apps teach system design. We put you in the interview.**

Supporting line: *Knowing it isn't the test. Saying it out loud to someone who pushes back is.* App Store subtitle: *Rehearse the system design interview.*

The first sentence concedes the content category (Educative, ByteByteGo: daily questions, decks, flashcards). The second says what Drillbit is instead: a room with an interviewer, not a course. Consequences: no lesson decks, term flashcards or daily multiple choice; progress is counted in reps and fixes, never XP, levels or correctness heatmaps. Every Welcome, store and ad string is checked against this pair.

---

This document is direction. [Architecture](architecture.md) records what is built. Superseded plans (the Solo/Coach/Guided workspace, disabled Speak, build slices, council transcripts) are in git history; the decisions that survived are below.

## Principles

- The person's answer is the product; the interviewer supports it. More questions, messages or minutes are not success. A session should leave one thing understood or explained better.
- A quiet practice room: easy to enter, undemanding while thinking, useful when stuck, clear about what happened.
- Generated text stays out of the answer until deliberately adopted, with a preview, a revision check and undo.
- Feedback is one strength and one gap, each quoted from the person's own words. No readiness percentage, generic praise or proficiency diagnosis from one attempt. If the answer is too thin to judge, say what's missing.
- Across many reps, Pro may show a working-level estimate (Intern to Principal) on the Bit tab's knowledge map. It comes only from grounded feedback over several reps, waits until there is enough to go on, says what it's based on, and is labelled an estimate from your reps, not a hiring call. It is never a percentage, and feedback on a single rep still never diagnoses level.
- Finishing freezes the answer and the assistance cutoff together. Late AI results can't change it, and AI or network failure never invalidates completed practice.
- History states what help was used (hints, an example, an AI draft), never an "AI-written percentage".
- Dynamic Type changes layout instead of shrinking text. VoiceOver announces state changes, not streamed tokens. Every voice function has a text equivalent.

**Out:** streak guilt, compulsory timers, live scoring, decorative dashboards, XP and game levels (the engineering-level estimate above is evidence, not a reward), mandatory résumé upload, a questionnaire before each question, an executable coding IDE, and animation standing in for thinking. Motion reports real state.

**Bit**, the mascot, appears around practice, never inside it: Welcome, setup, the question preview and arriving feedback. It stays off sign-in, the answer workspace and the voice room, and its moods reflect real state. See [architecture](architecture.md#bit-the-mascot--2-october-2026).

## Navigation and questions

Home, Recall and Library are tabs; Settings is a sheet. The question workspace is full screen with at most one sheet over it.

- One active attempt: Resume, Finish or explicitly end it before preparing another. Work is never silently replaced, and concurrent Start/Replace has one server winner.
- Preparation is a short brief with remembered defaults.
- A good question names its audience or bounds its system and asks for decisions and tradeoffs. Show only the title, prompt and constraints needed to answer; evaluation criteria come from visible requirements.
- The generator also writes the interviewer's first line, personal to the setup, at no extra model call.
- A replacement keeps the old question until the new one succeeds. Relevance lines ("Another chance to explain rollback") appear only when grounded in prior practice.

## The interview

One interviewer and explicit turns (built as the [Interview room](architecture.md#interview-room--9-september-2026)):

- The draft autosaves. Send creates a durable answer command; the interviewer follows up or wraps up.
- A line ending in "?" asks the interviewer instead of answering.
- Nudge and Example come on request. Session style is Guided, Practice (default) or Mock interview and can change mid-interview without resetting the question.
- Finish freezes the answer and leads to feedback.

Voice is the same interview out loud. Text locks while voice is live, and the conversation returns to the document as transcript rows. Daily starts are limited and reported honestly (remaining, limit, reset in local time); a start that never reaches a provider session is refunded. Drillbit keeps no raw audio by default, and provider retention is verified and disclosed.

**Tone.** Poke is the reference: a sharp, relaxed practice partner. Concise, direct, plain words, one question at a time, comfortable disagreeing, occasionally lightly witty. Guided explains fully, Practice nudges, feedback is candid and specific. Errors and controls stay calm and literal. Past practice is mentioned only when evidence supports it. Tone is a versioned layer under task prompts, checked with a fixed evaluation set and human review.

## Failure and recovery

| Event | What the person sees | Invariant |
| --- | --- | --- |
| Generation or replacement fails | The existing question and Retry | Usable work is never destroyed |
| No network | Writing works; help says it needs a connection | No implicit paid retries |
| Session expires | Reauthenticate when sync or help needs it | The local draft survives |
| Help dismissed or stopped | The answer restored; partial help marked incomplete | Dismiss isn't cancel; partial isn't final |
| Draft changes during help | "Based on your earlier draft" | No stale automatic insertion |
| Finish races help | Saved answer | Late help can't change the review |
| Revision conflict | Both versions recoverable | No silent winner |
| Voice interrupted or unavailable | Paused or explained, with text available | No automatic microphone restart |
| Feedback fails | Answer saved; retry later | Completion doesn't depend on AI |
| App killed | Resume and reconcile operation IDs | No duplicate turns or completions |

## First run and the practice gate — 2 October 2026

**Promise:** one real interview rep, tailored enough to feel personal, with feedback worth acting on, before Drillbit asks for anything.

1. **Welcome**, then **sign in** with Apple, Google or GitHub. The invite field shows only while access is invite-gated.
2. **Two questions:** goal, then familiarity. An interview goal reveals an optional date. Everything else defaults and stays editable in Settings.
3. **First question:** Bit drills while it generates; one swap allowed.
4. **First rep, counted:** Guided by default, opening on one concrete decision answerable in a sentence.
5. **Feedback**, with the daily reminder offered once ("Want a nudge tomorrow?").
6. **Home**, with one line pointing at the first Recall card.
7. **Next rep:** the practice gate.

**Gate.** Every action that starts a rep (Home, retry, similar question, Library) calls one client hook, and the Worker decides. A rep is used when its question is prepared, one swap included; a failed preparation doesn't count. Free accounts get the first rep, then one 7 days after the last, with follow-ups capped at 8 and nudges at 2 (configurable) and no automatic daily question. Home says "Your free rep comes back Thursday." Recall, Library and past feedback stay free. The switch is off during the invite beta; when on, only an environment allowlist is unlimited.

**When Superwall lands:** one gated placement, `practice_rep`, on every rep-starting action. The Worker still authorizes every paid model call; entitlements sync from webhooks keyed by account ID. A 7-day trial is offered on the paywall, never at signup, and its timeline states only true things. The remote paywall's VoiceOver and large-text behaviour is verified separately.

**Open:** two free reps a month instead of one a week, so the first feedback can be acted on before the gate; whether voice is paid-only; per-rep cost (`scripts/measure-inference.ts`) against conversion, with the allowance a per-cohort server setting. These surfaces land during the 1.0 freeze.

## Taste, tips and the voice room — 3 October 2026

The first-run build felt bland, the voice room unpleasant, and the tooltips were missed. Organizing idea: **your touch changes something real**, and Bit reacts to what happened, not to the person. This amends the first run above.

- **Welcome is playable:** a 20-second scripted example with no model call. A push times out; Retry delivers it twice, Check first can't tell; both end on "Retry with the same request ID", the duplicate is skipped, and Bit says "That's an idempotency key." Get started is always available.
- **Sign-in is quiet:** logo and buttons, no mascot.
- **Setup shows consequences:** a date becomes one large number ("12 days until your interview"), and the level says what it changes.
- **The preview asks how you'll answer:** Write it or Talk it through, remembered. Talking shows the session cap and today's allowance, then opens a connected voice room.
- **Three coachmarks, once each**, as compact callouts with no dimming: *Your turn* on the composer until typing starts, *Stuck?* on ••• after the first follow-up, *Keep this one* on Home's Recall row once cards are due.
- **The voice room is one quiet stage:** the collapsed question and a clock that counts down in the last two minutes; a small interviewer orb with a turn label from measured audio; honest labels ("Mic off. They can't hear you.", and "Working through your answer" only while a request is in flight); a fixed four-line caption; a dock with Transcript, Mute and End.

**Deferred:** *Try that fix* (rewrite the weak sentence inline, see before and after, keep it for Recall; needs API work and is the strongest idea not yet built), a five-minute free voice taste when Superwall lands, sign-in after setup, and stopping the interviewer mid-sentence until it's verified on device.

## Exploring — 4 October 2026

The next redesign is being worked out in an HTML prototype before any Swift: first a screen-by-screen teardown of the app, then patterns borrowed from ByteByteGo, Exponent, Excalidraw, Hello Interview and Brilliant. Those patterns are tiny steps with instant feedback, manipulable diagrams, a canvas with a component palette, mock-interview critique and a visible path through a framework. Direction from the user so far: less Bit and more serious, light by default, and no Write it / Talk it through switch. Still to settle: the positioning above rules out lessons and quizzes.
