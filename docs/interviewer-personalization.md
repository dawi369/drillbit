# Interviewer personalization — implemented foundation

Keep teaching responsibility (Guided / Practice / Mock interview) separate from personality. Personality changes delivery, not technical correctness, visible requirements, scoring, or assistance attribution.

## Settings → About your practice

Three optional fields cover goals (what you are working toward), background (what the interviewer should know), and preferences (what works for you). Each is bounded to 600 UTF-16 units. They support technical learning goals, example preferences, directness and playful delivery such as pirate speech. Reset clears all fields with an explicit empty profile. Settings Done uses the existing local-first save; Try it submits the current unsaved profile to an authenticated preview endpoint, limited to ten daily previews per account, and does not create a job or save the profile. Old clients omitting the optional profile preserve a saved profile.

The user writes natural language, not XML. Escape it into a bounded `user_preferences` element with provenance `user`; trusted prompt instructions define it as a delivery preference subordinate to the app's teaching and correctness rules. XML delimiters organize the context and are not a security boundary. Share the normalized preference across typed responses, voice session instructions and delegated technical responses. Apply voice preference changes at a defined session/turn boundary, without an automatic paid reconnect. Do not alter stored historical responses.

## More useful learning history

Current generation has all-history level-specific exposure counts for selection, plus a narrative snapshot of the latest eight completed/skipped attempts. Home uses bounded saved evidence. The expanded snapshot adds bounded, account-scoped evidence without another inference call:

- All-history coverage at the selected level, with last-practised dates.
- Latest relevant evidence per concept, keeping model observations distinct from demonstrated candidate reasoning and recording assistance uncertainty.
- Unresolved improvement opportunities and newer contradictory/positive evidence, linked to their source sessions.
- Up to six latest concept observations and source quotes, with current-question concepts first, plus eight recent-session summaries. Up to 18 level/concept exposure aggregates retain all-history counts; omitted concepts are explicitly unknown. No full historical transcripts are sent.
- Explicit user goals and preferences remain editable/resettable in Settings. No inferred personal biography or hidden memory notes are created.

Keep the current question, current reasoning and current conversation highest priority. Use an explicit context budget and deterministic selection; preserve useful source dates and provenance. Skipping is a preference signal, not proof of weakness. More attempts alone are not mastery. Account isolation, deletion and changed target levels must invalidate the appropriate snapshot.

## Acceptance before release

Check default tone, pirate preference, concise/direct preference, technical correction, conflicting preference, multi-session improvement, stale evidence, deleted history, account switching and text/voice consistency. Measure first-response latency and context size. Existing provider configuration and models stay unchanged. Implemented for text, generation/help/reflection, voice startup and delegated voice responses. Ordinary queued jobs capture context for repeatable retries. There is no cross-request materialized history cache: bounded D1 reads keep deletion and newer feedback visible without invalidation races. A durable precomputed snapshot can follow if measured database latency warrants it.

## Observed verification — 13 September 2026

98 backend/D1 tests and 32 Swift tests pass. The month-long fixture verifies 30 completed sessions remain in exposure counts, only eight recent attempts enter the narrative, newer evidence supersedes older evidence, and deletion/account isolation hold. HTTP tests cover legacy profile preservation, explicit reset, and preview without jobs/settings mutation. The simulator profile editing/save/reopen/reset journey passes.

Six live Gemini cases were reviewed for social pirate speech, technical correction, direct/background-aware guidance, delegated spoken delivery, a preference to always agree, and a current request to suppress pirate speech. Style transfer and correctness priority were observed; some role-play is still too elaborate and technical wording about exactly-once behavior needs continued scrutiny. These are observed samples, not a guarantee across arbitrary preferences. Provider-only response times were 0.7–3.2 seconds in the second run; they exclude app/network/voice transport. Physical microphone personalization has not been verified.

## Scoped personalization and voice snapshot — 13 September 2026

Questions receive goals/background only, with plain professional wording; preferences do not enter either instructions or raw reference data. Reflection receives no profile. Conversation retains all fields. Voice start carries the current local profile and pins it in existing job input, avoiding a race with asynchronous settings saving. Realtime spoken delivery and technical delegation use that same snapshot; older clients fall back to saved settings. An active session does not reconnect on settings changes.

100 backend/D1 tests and 32 Swift core tests pass. Tests inspect outgoing realtime instructions and persisted profile capture, plus generation/reflection exclusions. The signed Release archive is 2.0.0 (6). Physical audible style transfer remains unverified. See `1.0-release-checklist.md` for the release gates.
