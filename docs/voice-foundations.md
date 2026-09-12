# Voice foundation audit — 11 September 2026

Live voice remains disabled. This audit covers the existing text-first transcript boundary, not a working audio experience.

## Ready to reuse

- FinalizedInterviewAnswer carries a stable UUID, account, attempt and prompt identity. Finalized turns use the same durable pending command, revision checks, streaming response and ordered database transcript as typed turns. Reconnect replays the original command; exiting voice must not import another copy of the conversation.
- A typed draft cannot silently be overwritten by voice. Duplicate IDs with different text and stale accounts/prompts are rejected. Provisional recognition is deliberately absent from this API.
- The same versioned personality and reference snapshot serve both modalities. No second voice persona or independent agent transcript is needed.

## Gaps closed

Finalized text trims edge whitespace before duplicate checks, matching durable submission. Late input is rejected after completion or while the workspace is hidden/inactive. This admission flag is transient UI lifetime state, not persisted authorization; server ownership, revision and lifecycle checks remain authoritative. Existing replay, conflicting-draft and restoration tests now cover whitespace duplicates and closed/finished admission.

## Required before enabling the button

1. Audio session/permissions and explicit user entry/exit; interruption, route change, Bluetooth and background handling. No microphone transport or entitlement is added here.
2. A voice-session identity and cancellable adapter: keep provisional speech local, commit finalized utterances in order, discard stale adapter callbacks after exit, and bind every event to the current prompt. Text-first admission is not a full audio-session state machine.
3. Endpointing and user-yield detection, silence handling and barge-in. Stop playback when interrupted without deleting committed interviewer text or falsely claiming it was heard.
4. Separate answer dictation from discussion intent and Ask actions. This implementation exposes finalized answers only; a future adapter must explicitly select destinations without silently appending discussion to a written draft.
5. Spoken-delivery receipts distinct from generated/displayed text, partial playback and uncertain exposure, frozen at completion. Existing unknown-exposure semantics must stay conservative.
6. Accessible voice controls, permission denial, offline recovery, real-device latency and interruption tests. Typing, existing history, and drafts remain available after leaving voice.

No iOS speech framework choice or provider voice transport has been locked in. Validate those against current Apple APIs when implementing audio.

## Native implementation — 12 September 2026

This section supersedes the earlier disabled-transport audit. A native WebRTC adapter (pinned stasel/WebRTC 153.0.0) now negotiates GPT-Live through an authenticated Worker endpoint. The provider API key and startup instructions never enter the app. `VOICE_ENABLED=false` is the default: live startup remains unavailable until an OpenAI project key and audio acceptance are verified. Gemini remains the technical reasoning backend; GPT-Live is the separate speech/conversation provider.

### Product and persistence

- Voice replaces the floating composer controls with one compact bottom panel, leaving the interview scrollable. Mute and End voice are explicit; ending does not complete the interview. Accessibility sizes use icon controls with spoken labels. No animated orb, fake activity or haptics.
- Each voice session reserves one ordered block in the existing interview transcript. Timestamped input/output fragments are stored without trimming or inventing spaces, both locally before display and incrementally in D1. Stable event IDs and sequence numbers deduplicate replay. Display groups use a 1.5-second same-speaker interval heuristic; it is not a semantic turn boundary or inference trigger. Overlapping speakers remain independent. Rows support the same disclosure component as typed history.
- Typed drafts are flushed and revision-checked before startup, then remain separate and untouched. Text submission, help, skip and completion are disabled while voice is running or its outbox needs synchronization. The backend separately rejects text/finish races with an active voice reservation.
- Exiting/backgrounding/audio interruption stops capture and playback, requests graceful provider close, and waits up to five seconds for terminal events. Missing finalization is recorded as uncertain. No session automatically reconnects or starts another paid request. Relaunch restores pending transcript work, not microphone activity.
- GPT-Live currently emits transcript fragments without authoritative turn-completed events or exact word-to-playback alignment. All voice exposure remains `unknown`; terminal session confirmation is not proof every word was heard. Do not label a generated reply as fully delivered or trim it to a fabricated heard-word boundary.
- Completion freezes the stored fragments atomically with the answer. Voice transcripts are included in Library conversation detail, exports, subsequent text-model context and feedback evidence validation. No raw audio recording is persisted by Drillbit; provider session `store` is false.

### Operational bounds and open acceptance

Paid startup requires the server flag and `OPENAI_API_KEY`. Startup reserves an account-scoped session before provider I/O; six starts per account/day, forty reasoning delegations/day, and the existing shared provider-attempt limit apply. Native sessions close after ten minutes; D1 reservations expire after fifteen minutes. The native timer is not a provider-side hard billing cap. Hard server-enforced duration termination and authoritative provider-side usage reconciliation are required before general availability. Client usage receipts are operational hints, not billing authority.

No blind paid retries: a lost handshake/delegation remains uncertain or failed. Technical delegation uses the persisted conversation and historical snapshot, returns at most 256 model tokens, and never generates an additional transcript turn; only speech transcript events enter history.

Simulator fixtures validate panel/mute/end, transcript grouping, draft preservation and restoration. Actual GPT-Live access, microphone/audio quality, latency, Bluetooth, interruption behavior, VoiceOver interaction and physical iPhone acceptance remain unverified. Live voice must remain gated until those checks pass.

References: [GPT-Live WebRTC](https://developers.openai.com/api/docs/guides/voice-webrtc?api=live), [session and transcript semantics](https://developers.openai.com/api/docs/guides/live-conversations), [client delegation](https://developers.openai.com/api/docs/guides/live-delegation?delegation-mode=client).
