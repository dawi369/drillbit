# A companion beside the answer

Implementation specification · 9 September 2026

The native companion replaces the help-menu-first workspace. The answer remains central. The implementation uses the existing durable help jobs, account-scoped SwiftData store, revision-checked insertion flow and Finish confirmation. See [acceptance](acceptance.md) for observed evidence and remaining limitations; implementation is not a claim of exhaustive product acceptance.

## Modes and navigation

| Mode | Workspace | Entry |
| --- | --- | --- |
| Solo | Question, editor, save status and neutral mode menu. No companion or automatic inference. | Immediately blocks pending presentation. Earlier assistance remains recorded. |
| Coach | One compact bottom thought, grounded in the question and current reasoning. | Arms change/pause checks; does not immediately make a model call. |
| Guided | The same companion, collaborating on one decision. | An explicit selection queues one initial collaboration request. Restoration/reopening only reconciles state. |

Tap the companion to open the existing help sheet. It contains current guidance, manual help, a natural question field, pause/dismiss controls and Earlier help. Stale results are labelled “Earlier draft or context” and are excluded from the current thought. Guided additionally offers a starting paragraph, an alternative, a full example and an optional plan of at most three decisions. Selecting a plan decision changes user focus; it does not mark a checklist complete. Model-suggested focus, user focus and committed discussion remain separate data.

Generated writing uses preview → append/replace → server revision check → undo. Discussion never silently edits the answer. Speak remains visibly disabled. Keyboard dictation remains available through iOS.

## Appearance and accessibility

- System fonts, semantic foreground colours, SwiftUI regular material, 12-point corners and 4-point spacing increments.
- A fixed 100-point companion allocation while assisted, independent of response length. Accessibility sizes use an 80-point compact button with a full accessibility label. The editor therefore does not resize on hint arrival.
- Restrained blue/violet border illumination. No screen-wide effect, looping gradient, orb, fake scanning, streamed tokens, sound or automatic haptics.
- Completed guidance enters over 350 ms with at most 4 points of movement. Replacements use 200 ms; border illumination settles over 600 ms. Results are held while typing or a sheet/alert is open.
- Quiet: mode and subdued availability copy. Requesting: illumination only after a real request starts; delayed native progress after one second. Suggestion: one thought, tap to expand. Paused: explicit Resume. Unavailable: compact connection copy and preserved writing; no automatic inference retry.
- Reduced Motion removes movement/animated illumination; Reduced Transparency selects an opaque semantic background. No focus requests or VoiceOver announcements occur on arrival.

## Deterministic intervention policy

The pure `InterventionPolicy` receives time explicitly. `CompanionCoordinator` accepts an injectable clock and holds session state. The workspace forwards events and renders state; network/persistence integration lives in `PracticeCompanion`.

| Trigger | Starting configuration |
| --- | --- |
| Meaningful change | 20 inserted/removed words **or** 100 inserted/removed characters since the last checked answer, then four seconds of settled input. Substitutions and deletions count. |
| Pause | 30 seconds without content interaction in the foreground. No edit is required; a blank answer can receive one opening hint. |

Both paths require a synced, unconflicted draft, no request in flight, no composition, modal, adoption or completion, and active foreground presentation. Content touch/drag and text activity reset inactivity, without rearming a consumed cycle. Backgrounding, leaving the workspace and modal transitions reset timing.

A normalized answer change or committed discussion creates a new cycle. Cosmetic whitespace, mode toggles and reopening sheets do not. The backend tracks normalized content transitions so returning to an earlier answer after a real change is still a new cycle. It exposes consumed-cycle state for other devices. Guided entry consumes its unchanged cycle without using the automatic-request budget.

Automatic requests share a 45-second cooldown and a six-request limit per attempt across assisted modes. A check returning `no_intervention` consumes its cycle. Failed/uncertain automatic submissions are not retried automatically. Subsequent edits coalesce while an inference is running. Manual help remains available under existing account limits. “Let me think” pauses until Resume; Dismiss suppresses the current suggestion.

## Context, identity and recovery

Migration `0005_companion.sql` adds context, idempotent context commands, captured requests and delivery receipts. API additions:

- `PUT /v1/challenges/{id}/companion`: revision-checked mode, pause, focus or committed discussion; idempotency key required.
- `POST /v1/challenges/{id}/deliveries`: idempotent receipts with their own UUIDs.
- Help requests optionally carry trigger, answer digest, context revision, mode epoch and interaction cycle. Existing explicit-help clients remain compatible.
- Challenge detail includes companion state, capability, result capture, outcome, suggested focus/plan and delivery history.
- Completion accepts pending receipts and freezes exposure with the final answer in the same D1 transaction. A stale completion cannot record its pending receipts.

Native presentation additionally checks the local edit generation. A result must match the account-bound controller, attempt, normalized answer, context and mode. Switching to Solo or confirming Finish blocks pending presentation. Previously shown, still-current guidance can reconcile on restoration; previously pending results remain conservatively historical unless produced in the current local generation. Reopening never creates another paid request.

Account-scoped cached payloads persist scheduling recovery, pending context/help commands, delivery intents and the existing adoption command. Per-keystroke activity/composition and edit generations remain transient. Unknown help submissions are reconciled by reading their durable job identity; automatic inference is never blindly resubmitted.

Delivery distinguishes generated, uncertain, shown, dismissed/superseded and adopted. The client persists uncertain delivery intent before presentation, then records shown exposure. A missing acknowledgement remains uncertain. Receipts are acknowledged without deleting newer queue entries; completion resubmits pending receipts. Adoption remains a separate revision-checked event. Summaries must never equate missing delivery acknowledgement with independent work. Older clients/history remain conservatively unknown.

## Model and voice boundary

`google/gemini-3.1-flash-lite` is the sole model. `companion-v1` prompts require grounded, incremental help and permit silence. Coach has a stricter output schema: no plan, no suggested focus, no suggested answer. Companion thoughts are limited to 240 characters; expanded examples retain the existing longer schema. Live product review is required in addition to schema checks.

Modality-neutral events are defined for committed answer changes, committed discussion, activity, yield, mode/visibility changes and delivery. A future voice adapter must feed finalized turns through these boundaries; provisional transcripts cannot trigger coaching. Answer dictation and discussion remain distinct destinations. Recording and speech transport are not implemented.

## Rollout and deferred work

Back up development D1, apply the additive migration, deploy the compatible Worker and install the signed native build. `COMPANION_AUTO_ENABLED` is the server rollback switch; disabling it preserves explicit help. Do not roll the database back or remove exposure records.

Live voice, selection-specific replacement and linked retry/revision attempts remain deferred. Physical-device dictation/composition, full VoiceOver navigation and broader live-model quality remain explicit acceptance work, not implied by simulator tests.
