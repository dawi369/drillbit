# Interviewer council: candidate product direction

9 September 2026 · Updated after a second council: the user approved a continuous, manually foldable interview document. The original brief, exchanges and growing draft now share one scroll surface; asynchronous replies never fold content. One disclosure per exchange was chosen over separate question/answer accordions, and manual folding over automatic history compaction. See the Continuous interview document section of architecture.md for the delivered mechanics. Earlier council discussion is retained below. The user approved the Interview room and the name **Interview style**, with **Quick / Standard / In-depth**, then requested implementation. See architecture.md and acceptance.md for the delivered behavior and evidence.

Three perspectives reviewed the current product: interview learning, native interaction, and adaptive assistance. They agree on replacing mode switching with one interviewer and explicit conversational turns. They disagree on whether the remaining setting should describe support or follow-up depth. This document preserves that disagreement rather than presenting every recommendation as consensus. The implemented baseline remains in architecture.md and companion-vision.md.

## Shared conclusion

The central change is from an assistant reacting to an evolving essay to an interviewer reacting to reasoning the user deliberately shares. A pause means thinking, not submission. The current answer is saved while the user writes; Share answer gives the interviewer the floor. One grounded follow-up then opens one fresh answer draft. Previous shared answers remain accessible and are not overwritten.

Engineering level remains Intern through Principal and defines question scope. Interviewer behavior must not silently change that scope, introduce hidden grading requirements, or make a previous answer inadequate retrospectively. Added constraints belong explicitly to the follow-up that introduces them.

## Three strongest candidates

### 1. Interview room — recommended synthesis

One current question, a spacious writing area, and a minimal footer. This combines the learning perspective's Interview room with the interaction perspective's writing-oriented Interview desk; both use committed turns, not one endlessly edited answer.

Flow:
1. Today stays the dashboard. Prepare retains temporary topic, engineering level and optional request.
2. Preview includes the original brief and a compact interviewer setting. Start interview is explicit.
3. The interviewer presents the problem. The user can read requirements, ask a clarification, or write/dictate an answer.
4. Share answer commits that answer. A real pending state appears; no model feedback or advancing while typing.
5. The interviewer asks one question about what was shared. Example: “You chose one queue. What happens when one customer fills it?”
6. The next answer is a fresh draft. Original brief and Conversation remain accessible, without a transcript consuming the main writing surface.
7. Finish remains available and confirmed. An interviewer wrap-up offer provides Finish and review / Keep going, never automatic completion.

Screen: Close / Interview / Finish at top; collapsible current prompt and accessible original brief; answer canvas; bottom-left disabled waveform, Ask interviewer and primary Share answer. Remove the persistent Solo/Coach/Guided menu. At accessibility sizes, controls can stack rather than compress the editor.

Ask interviewer opens a compact sheet with a natural question field and a nudge action. Clarification/help must not submit the draft or consume the current answer turn. Stronger explanations/examples remain explicitly accessible, with no mandatory hint ladder. This adds a secondary interaction destination, but keeps one obvious primary answer destination.

Advantages: spacious technical writing, clear conversational ownership, minimal navigation, natural future voice adapter. Cost: less immediate transcript visibility than chat, and genuine turn persistence is required.

### 2. Conversation-first interview

A restrained chronological conversation with a composer that grows for longer replies. A persistent Brief action retains original requirements. Candidate answers, clarification exchanges and follow-ups appear in order; Finish leads to review.

Advantages: familiar conversational rhythm and easy visibility of previous exchanges. Costs: long code/reasoning competes with transcript space; asking a clarification versus sharing an answer is ambiguous unless the UI makes intent explicit. Expanding into another writing screen introduces complexity. Most likely to feel like a generic chatbot.

Best if conversational exchange becomes more important than extended written reasoning. Not the recommended initial direction.

### 3. Checkpoint interview

The existing durable solution stays central. Discuss my approach shares a snapshot; the interviewer asks a focused question about it. The user replies separately or deliberately revises the solution, then discusses again. Finish freezes both the solution and discussion.

Advantages: coherent system-design/code artifact and lower disruption to the existing product. Costs: the distinction between solution and discussion remains a teaching burden; risks being Coach renamed. Best for deliberate design practice, less convincing as an interview simulation.

Visible fixed rounds were considered and rejected as a default: they encourage artificial checklists and unnecessary follow-ups. Broad internal coverage planning may help the interviewer, but should adapt to what was already answered.

## What interviewer levels should mean

Do not combine warmth, help, depth, seniority and time pressure into an unexplained difficulty slider. All interviewers remain respectful.

### Preferred experiment: follow-up depth

| Choice | Observable behavior |
| --- | --- |
| Light | Explore one central decision, then offer a wrap-up. |
| Standard | Probe a decision and a consequence or alternative. |
| Deep | Pursue connected consequences and further trade-off defence. |

These are conversation-depth promises, not fixed turn counts or assessment multipliers. Depth remains bounded by the selected engineering scope. More conversation is not automatically better. Stop proposing follow-ups when the key reasoning has been explored or questions become repetitive; offer a wrap-up and let the user decide.

Help remains available at every depth. This is the adaptive-assistance perspective's recommendation and the lead synthesis preference: change how far the interview goes, rather than requiring a mode change to receive help.

### Credible alternative: interviewer approach

Supportive / Balanced / Probing. Supportive breaks a broad question into smaller decisions; Balanced follows the candidate's lead; Probing spends more time on assumptions and alternatives. Two council members initially preferred this direction. It could better match a user who wants adjustable scaffolding, but requires concrete behavior contracts to avoid recreating Solo/Coach/Guided with different names.

Practice / Mock is a separate possible future distinction: teaching and retry versus evaluation held until the end. It should not be silently mixed into depth. Do not ship depth, support, realism and pressure controls together in the first version.

## Concrete example

Senior · System design · Standard depth.

Interviewer: “Design a notification service. How would you accept and deliver a notification reliably?”

Candidate shares an API, queue and worker approach.

Interviewer: “The worker sends an email, then crashes before acknowledging the job. What happens on retry?”

Candidate asks for a nudge. The draft stays intact; the interviewer directs attention to what can establish whether the external effect already happened. Asking does not automatically insert an answer.

Candidate shares their reasoning about retries and deduplication.

The interviewer may probe one unresolved consequence, or offer a wrap-up. Review distinguishes reasoning volunteered, reasoning prompted by a follow-up, and reasoning developed with explicit help. It links observations to actual turns and shows one useful next practice target; no invented readiness percentage.

## Behavioral and architectural boundaries

- Ordered durable interviewer/candidate turns, one active question and one unshared draft. Shared snapshots stay historically accurate; corrections are subsequent clarifications.
- Share commands are revision-bound and idempotent. Failures preserve text and reconcile the original submission; Retry must not create duplicate turns or follow-ups.
- An answer accepted while inference fails is still submitted. Recover the interviewer response separately rather than asking the user to share again.
- Restoration resumes the exact pending/current turn without another paid request. Account ownership, assistance receipts, safe example adoption and completion cutoff remain necessary.
- Explicit actions distinguish answer, clarification, help, follow-up and wrap-up. Prompt tone alone cannot enforce turn ownership.
- No automatic analysis from a typing pause in the recommended default. A passive local help affordance could be evaluated later; it must never count as submission.
- Voice remains disabled. Future voice commits finalized responses to the same turn model; provisional transcripts and silence do not become answers automatically.
- No extra tabs, avatar, live score, mandatory timer, multi-composer scratchpad or fixed-round navigation initially.

## Decision to validate before implementation

Prototype the Interview room first with a short authored exchange. Validate that users understand Share answer, can find their previous answer, ask a clarification without losing their draft, and know when they can finish. Compare depth versus approach language only after the core turn-taking feels natural. These are product hypotheses from the council, not empirical learning claims or verified model capability.
