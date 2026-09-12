# Product completeness pass

Scope: strengthen text practice, not voice or a visual redesign. Preserve existing lifecycle, account isolation and cached Home/Library. Simulator rollout only unless explicitly requested otherwise.

Acceptance ledger:
- Appearance/accessibility: semantic colors, system/light/dark preference, Dynamic Type and reduced motion journeys.
- Recovery: existing durable draft/outbox/stream retry/conflict tests; repair any failures found. Physical interruption/device switching acceptance must be recorded separately.
- Personality: retain versioned V4 and repeatable live synthetic evaluation; no new persona until evidence warrants it.
- Feedback: grounded concept observations with answer evidence, conservative assistance and one actionable next exercise; preserve legacy reflections.
- History/progress: immutable session context, searchable library, skipped recovery; concept evidence separate from completion counts.
- Selection: deterministic exploration/revisit/feedback rotation; explicit topic overrides; skips never imply weakness.
- Follow-through: reuse preparation with source reflection and focused next exercise.
- Daily loop: fixed IANA zone, no backlog, reminder permission recovery, notification/widget Home routing.
- Account/data: paginated account export without credentials; retain deletion and sign-out pending-work protections.
- Operations: content-free request/provider timing, failure and prompt-version evidence; no private text in telemetry.

This ledger distinguishes implementation from test evidence. Unverified physical-device behavior must not be marked complete.

## Implemented — 11 September 2026

| Area | Delivered behavior | Evidence / boundary |
|---|---|---|
| Appearance | Persistent System/Light/Dark preference; semantic native surfaces; presented interview inherits appearance | Preference survives relaunch; dark keyboard, large-text Library and Settings screenshots inspected/tested. Full VoiceOver spoken navigation and physical-device contrast remain unverified. |
| Session reliability | Retained durable draft/outbox, revision conflicts, streaming retry, restoration and cache-first Home; deleted sessions invalidate Library caches | 25 native tests plus D1 lifecycle suites and restoration/late-response journeys pass. Cross-device network interruption needs physical acceptance. |
| Personality | Retained V4 versioned interviewer; 24 live synthetic turns reviewed | Social exchange, humor opt-out, evidence recall and technical correction sampled. No universal tone/correctness guarantee. |
| Feedback | `feedback-v2` uses XML and low reasoning; optional improvement when sufficient; required next exercise and up to two exact-quote concept observations | Four final live samples reviewed. Earlier failures (scolding social answers, invented gaps, malformed/oversized output) prompted revisions; runtime schema rejection/retry remains necessary. |
| Evidence | Server validates quote occurrence in candidate work and allowed question concepts; stored with reflection; cached in memory response | Assisted or unknown attribution only, never certified independence. Social-only recognized answers have no strengths/gaps/evidence. Legacy reflections stay unchanged. |
| Progress/history | Library Practice evidence groups attributed observations by concept with source-session links; session detail has level/date and follow-up preparation | Last 100 completed-session observations, not an exhaustive lifetime skill profile. Coverage counts remain lifetime practice counts. No numeric mastery score. |
| Selection | Three-slot rotation between less-practised concepts, latest feedback and concepts not practised for 14 days; avoids last two generated primary concepts | Same engineering level only; explicit choice wins; newer evidence supersedes older evidence on the same concept. Skips excluded from skill signals. Feedback and revisit are fallbacks, not promises of a particular distribution. |
| Follow-through | Finish and Library session detail open source-linked preparation; prior improvement/next exercise is generation context; source weakness concept selected when available | Fresh immutable question/attempt; global level unchanged. Model relevance remains subject to evaluation. |
| Daily loop | Reminder/widget links land on Home without starting an attempt; reminders reconcile after successful bootstrap in the saved IANA zone; denied-permission recovery link | Existing no-backlog backend scheduler retained. Apple notification/widget delivery and DST behavior on physical phones not certified by Simulator. |
| Account/data | Paginated authenticated JSON export of cloud sessions and immutable questions/pool eligibility, no credentials/private rubric; native Files export waits for local sync | D1 pagination/isolation/eligibility tests. Creation watermark excludes new records during export; updates/deletions can still occur, so this is not a transactional database snapshot. Existing deletion/sign-out safeguards retained. |
| Operations | Actual prompt edition in `ai_runs`, including paid invalid structured outputs; content-free HTTP duration/status/request ID; existing inference timing; MetricKit crash/hang counts in local OSLog | No private payloads, stack dumps or credentials logged. Native MetricKit callback delivery requires physical-device observation; no new remote crash collection service. |

## Verification record

- Backend: 77 tests / 10 files passed, including D1 account isolation, lifecycle/receipts/concurrency, export and selection tests. Typecheck and contract generation passed.
- Native: 25 unit tests passed. Nine targeted UI journeys passed across `/tmp/drillbit-completeness-ui.xcresult`, `/tmp/drillbit-completeness-release-check.xcresult` and `/tmp/drillbit-completeness-appearance.xcresult`. Final simulator build succeeded.
- Live provider: 24 V4 turns (`/tmp/drillbit-completeness-personality.log`, $0.013462) and four final feedback samples (`/tmp/drillbit-completeness-feedback7.log`, $0.0026255). Synthetic data only. Final feedback accepted the valid retention policy, kept assisted attribution, avoided social grading and corrected unsafe retries.
- No destructive migration, no TestFlight upload, no voice recording/transport. Physical-device acceptance remains open rather than inferred from simulator success.
