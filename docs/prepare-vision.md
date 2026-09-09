# Prepare: a short practice brief

Status: council recommendation, not implemented. September 9, 2026. This revises the proposed preparation experience; current shipped behavior remains described in architecture/acceptance.

## Decision

Prepare should help someone choose one useful question, not configure an AI generator. Keep a fresh question as the default; make focused follow-up an explicit choice from review. The learning, native UX and context council agree on this boundary. A general automatic recommendation card was considered and deferred because current history does not establish independent ability or reliable skill gaps.

## Native sheet

Title: **New question**. Toolbar: **Cancel**.

One compact native Form group:

- **Topic**: editable natural-language focus, prefilled from existing preferences. No autofocus or keyboard until tapped.
- **Target level**: Intern, Junior, Mid-level, Senior, Staff, Principal. Visible and user-selected; not a proficiency assessment.
- **Format**: Choose for me, Explain, Design. Preserve the existing auto/explain/design wire values.

A lightweight **Add a request** disclosure exposes **Anything to include?** This applies to one question and starts empty on subsequent preparations. No persistent instructional paragraph.

One prominent **Prepare question** button, outside the input group. Use the existing primary button style, system fonts/colors, 4-point spacing and native controls. Use the existing sheet/navigation coordinator. Allow scrolling at accessibility sizes; preserve full accessible values and keyboard-safe access to the action.

Do not add time budgets, assistance mode, voice settings, score targets, tags, readiness badges or a multi-step onboarding wizard here. Solo/Coach/Guided remains a workspace choice.

## Practice loop

Question preview → Start → user reasoning → one consequential feedback point → optional practice of that point in a different situation.

Example: a notification-service answer misses retry bounds. A follow-up might ask about bounded retries in a payment worker. It should require applying the principle, not copy the preceding question or provide its solution.

Regular entry from Today uses remembered topic/format and the user's target level. Settings remain the authority for the default level; a per-question override does not silently update account settings. Opening, editing, restoring and cancelling Prepare never calls the model.

When a completed review has feedback, **Practise this next** opens this same sheet with a removable context block:

- **Building on your last session**
- The actual prior improvement text, with expansion if long.
- Source question title, linked to its read-only details.
- **Remove** returns to fresh-question semantics, preserving the edited topic/level/format.

The context block does not pre-fill or silently rewrite Topic. A changed topic with attached context explicitly requests transfer of the same improvement to the new topic. User constraints take precedence. If no review is available, offer a fresh question; do not manufacture a suggested improvement. This explicit source context is never sticky across unrelated preparations.

## Context and lifecycle

Reuse PreparationInput and followUpId. Route the review action through Prepare instead of generating immediately. No new recommendation endpoint or extra provider call is needed for this increment.

On submission, fetch the owned source again and require completed state plus a usable review for this targeted path. Show a recoverable source-unavailable message if it was deleted or its review is unavailable; offer explicit removal of context rather than silently generating something different. Preserve existing clients' general follow-up behavior through additive intent if strict targeted validation would otherwise break compatibility.

The server-side follow-up snapshot should carry bounded frozen answer evidence, the selected improvement, and conservative delivery/adoption evidence. Generated, shown, adopted and uncertain exposure remain distinct. Recent history is useful for avoiding repetition; skipped questions and assisted answers must not become claims of mastery or reasons to change level.

Submission returns to Today with real preparation status. Preserve the prior ready question until replacement succeeds. Retain the submitted brief for errors and idempotent recovery; Retry must reconcile the existing job before explicitly creating a replacement for a definitively failed job. A running attempt remains Resume, never silently replaceable.

## Acceptance

- A returning user can submit with one action, but can explain topic, target scope and format before doing so.
- New/no-history, pending review and missing source states are understandable and do not fabricate personalization.
- Topic/level/format/request edits take effect and never mutate account preferences silently.
- Review-origin context is visible, removable and account-scoped; foreign/deleted sources are rejected.
- Assisted history never produces automatic promotion or claims of independent proficiency.
- Opening/cancelling/restoring costs no model request; network failures preserve the brief and current question.
- Preview remains before Start; keyboard, VoiceOver and largest Dynamic Type remain usable.
- Live examples should demonstrate meaningful transfer under changed conditions, rather than near-duplicate questions. Inspect generation relevance and technical consistency separately from schema validity.

Focused feedback followed by varied practice is a product hypothesis, not demonstrated learning efficacy for Drillbit. Evaluate whether a person applies the previous improvement on a later question, keeping assistance visible. Activity counts alone do not measure learning.

Implementation and review default to the simulator. No TestFlight build/upload without explicit user instruction.
