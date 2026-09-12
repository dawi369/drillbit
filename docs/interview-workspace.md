# Interview workspace — text first, voice alongside it

Implemented 12 September 2026. This supersedes the Question/Conversation selector and oversized End button in the earlier voice-room proposal.

## Text

Start opens the existing writing document with no keyboard focus; restored interviews retain reading state. The canonical question collapses to its title and three description lines. Each answer stays paired with its response. One-line content has no disclosure control. Local durable acceptance triggers the existing 300 ms coordinated collapse once; subsequent response updates cannot re-collapse a manually reopened answer.

The inline field is “Your reply”, with “Talk through your approach, or ask a question…” as placeholder. Send always submits, never finishes. The menu exposes Give me a nudge, Show an example, Interview style, Finish interview and separated Skip question. Legacy wrap-up sessions retain their Continue recovery action. Quick help uses existing explicit request kinds, preserves unfinished text and streams into the document; no separate Ask sheet remains. Historical assistance remains conservative rather than treating ordinary conversation as independent work.

## Voice

The same owning interview shell retains the connection and outbox. Entry shows the canonical question component in a compact disclosure and the latest conversation exchange. Voice disclosure is presentation-local, initially collapsed; it does not overwrite the writing document’s saved disclosure state. History/Live changes the projection over shared data, with independent scroll positions and manual scrolling taking precedence. No duplicate transcript store or second question modal exists.

Latest voice rows retain the most recent row from each speaker and subsequent rows, preserving overlap and immutable fragment IDs. This is a reading projection, not a claim of finalized speech turns. Prior history remains accessible; text uses the latest existing interview turn when there is no new voice text.

Mute/Unmute is the single primary bottom control: a centred 72-point circle, icon only. The live microphone uses an inverse semantic foreground/background; muted uses a red slashed microphone on a secondary surface. Shape and VoiceOver action/value also communicate state, so colour is not the sole signal. Routine microphone on/off captions are absent; connection and failure messages remain. Use text appears only in the top-left navigation position; while connecting it reads Cancel. That exit stops local capture/playback synchronously and returns without waiting for receipt synchronization. No keyboard focus is requested. Closing, retry and interruption keep the existing lifecycle guards; switching projections never starts a connection.

## Availability

Bootstrap adds optional `capabilities.voice = { available, reason?, checkedAt }`; old DTOs/clients remain accepted. The existing `voiceInterview` boolean now reflects configured service availability instead of being permanently false. The structured field additionally reads the account’s existing six-start UTC-day usage limit without incrementing it. No entitlement, price, migration or provider change is introduced.

The native client uses a capability for less than 60 seconds. Missing, invalid, future-dated or expired data is unknown and refreshed on explicit voice entry. Account identity is checked after refresh. Old servers still lacking the field fall through to the authoritative Start endpoint. Unavailable/check-failed entry explains the reason with Done and leaves the reply/focus intact; it does not request microphone permission or start paid inference. Start still enforces limits in races after the read-only check.

## Accessibility and delivery

System text/colours, scrollable content, 44-point text actions, 72-point microphone and 52-point recovery controls, Reduced Motion opacity transitions and stable row labels remain. Voice fragments are not live-region announcements. Errors are contextual; routine synchronization is not shown. See acceptance.md for simulator evidence and unverified device/assistive-technology boundaries. No TestFlight upload.

App icons use the shared `AppIcon` SF Symbols catalog in `DesignSystem.swift`, keeping native sizing, weight and rendering rather than adding an external icon font. Cuelume was evaluated as a Web Audio sound library, not a SwiftUI dependency. UI sound playback remains deferred; any native cues must coexist with the voice audio session and respect user sound preferences.

### Explicit voice Start and text handoff — 12 September 2026

Opening the voice room is presentation only. Its primary 72-point control starts as a play button; explicit Start requests microphone permission if needed and opens one paid session, then replaces the symbol with the live mute control. Returning from text requires Start again. Reduced Motion removes symbol replacement movement.

Use text stops WebRTC's manually managed audio unit synchronously, latches the transport against late reactivation, and cancels pending startup. The data channel may drain final transcript/usage receipts for up to five seconds with audio disabled. Server refresh cannot replace the locally projected transcript while voice or its outbox is active.

Question loading may prepare local SDP/ICE only when microphone permission is already granted and a fresh account capability allows voice. No microphone permission prompt, audio capture/playback, backend session reservation or paid provider connection occurs during preparation. Prepared offers older than 60 seconds are discarded at Start; leaving/backgrounding discards preparation. GPT-Live sessions are duration billed, so provider connection remains an explicit Start operation.
