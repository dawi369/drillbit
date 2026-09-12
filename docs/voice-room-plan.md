# Voice room — experience, 12 September 2026

Status: dedicated room implemented locally. The button opens a restrained bottom-leading page transition; no giant waveform morph. Simulator evidence and remaining device checks are recorded in docs/acceptance.md.

## Decision

One interview, two ways to work: writing and talking. Tapping Voice opens a dedicated room within the current attempt. It owns no separate question, draft, transcript or completion state. The voice button is the visual origin of the transition; the session is owned above both pages.

The user reports live voice works well. This is encouraging user feedback, not a comprehensive device/audio acceptance result. The supplied screenshot and source show an empty reserved voice block drawing a divider next to the draft divider before speech. Hide empty blocks, retaining their persistence identity.

## Council and adjudication

Three independent, interpretive lenses proposed directions, then completed one cross-critique round:

- Steve Jobs-inspired: make the question the useful centre of the room; avoid turning empty space into an ornamental AI display.
- Jony Ive-inspired: stationary controls, one canonical question component, and a presentation transition independent of paid session startup. Reject a second question modal and unreliable turn-state indicators.
- Brian Chesky-inspired: entering should feel inviting and leaving safe. Preserve context and draft; give users access to conversation without disorienting navigation.

Choose Question / Conversation as two in-page views over shared state. Reject separate question and transcript sheets because they hide controls or require duplicated controls. Defer an additional recent-caption overlay: it would create a third reading surface before evidence shows it is needed. All members agree on the quiet default; this is a design judgment, not user validation.

## Screen and flow

### Enter

1. Tap the existing waveform button. Dismiss the keyboard and immediately begin a restrained native, source-anchored transition to the room. Expand the surface, not a giant stretched waveform glyph. Reduced Motion crossfades.
2. Keep the current draft intact. Synchronize and check its revision before paid startup. Show Connecting and an available Cancel action; microphone permission occurs only on explicit entry.
3. Show connected/microphone state only from real session and local capture state. View appearances, animation completions and toggles never start another request or replay a greeting.
4. Continue the current conversation. Do not automatically reread the question or deliver a new onboarding speech on every entry.

### Question view: default

- Small top navigation context uses the current scenario. An ordinary Question / Conversation selector changes the main content; controls stay in place.
- The existing question component is the visual anchor: title, short description, explicit expand/collapse affordance, full requirements on expansion. It uses the same canonical data and disclosure state as writing; only the active page renders it. No additional question modal.
- The body scrolls naturally when expanded, especially at accessibility text sizes. Content never sits behind controls without sufficient safe-area clearance.
- No score, countdown, chat avatar or continuously animated orb. An optional small level indicator may be added only if driven by measured audio; it communicates audio activity, not thought or understanding. The first implementation does not depend on it.
- The interviewer provides the personality: brief acknowledgement, room to think, natural interruptions, playfulness when appropriate. Silence does not automatically trigger a hint or a visual warning.

### Conversation view

- Replace the reference body with the shared voice/text history, retaining the same bottom controls. Switching views leaves audio running and keeps microphone state visible.
- Preserve raw fragments and stable row IDs; group them for reading without claiming semantic turn boundaries or exact heard-word alignment. Both speakers may accumulate text independently.
- Follow new content only while the reader is at the bottom. Manual scrolling stops following; a small Latest action restores it. No karaoke highlighting or automatic switch to this view when speech arrives.
- Preserve each view's reading position. No duplicated transcript ingestion or second storage layer.

### Fixed controls

- Mute / Unmute: toggles microphone capture. It does not pause the interviewer or claim to end the billable connection. Show muted state using label and icon, not colour alone.
- End voice: stops capture and playback immediately, then returns to the writing document. End voice never means Finish interview.
- During connecting, Cancel occupies the exit role. During a connection failure, present Retry and Back to writing; Retry is explicit and creates a new connection only after old state is reconciled.
- At accessibility sizes use a compact arrangement with 44-point targets and full VoiceOver labels. Transcript fragments are not automatically announced over the conversation.

### Exit and recovery

The room's back gesture and End voice have identical audio semantics. Returning restores the document/draft and makes the voice block available for review without automatically opening the keyboard. The native page transition must not wait for network finalization. Retain a session owner while the close receipt/outbox settles; only conflicting operations remain gated if synchronization fails.

Backgrounding, audio interruption or route loss stops audio. Return requires an explicit new start; do not secretly resume capture or paid sessions. A failure can return the user to writing with a compact recovery action and their transcript intact.

## Implementation sequence

1. Move session lifetime above document/voice routing. Current document `onDisappear` ends voice, so it cannot remain the route-level teardown hook. Introduce one owning interview shell and one explicit route; keep account and attempt lifetime guards authoritative.
2. Reuse the canonical question, reading state and history projections. Add the room, Question / Conversation selector and fixed controls. Keep persistence and backend contracts unchanged unless lifecycle testing identifies a real gap.
3. Add source-anchored entry/exit motion only after route and audio semantics work. Returning to writing cannot restart or cancel the wrong session.
4. Validate no second paid start on toggling, redraw, cancellation or navigation; no invisible active microphone; no draft overwrite; graceful and uncertain closure; offline return; long text, dark mode, largest Dynamic Type, Reduced Motion and VoiceOver.
5. Test real conversations requiring repeated reference to requirements. Measure unnecessary transcript toggles and whether users lose their place. If people repeatedly need both views simultaneously, adopt a persistent compact reference header in Conversation before adding a separate captions mode.

## Main tradeoff

A dedicated room focuses attention on speaking but moves history one action away. The chosen design earns that cost by keeping the problem visible, navigation reversible and audio controls stationary. If users spend most of a realistic session reading history, the quiet default should change. Visual novelty alone is not success.
