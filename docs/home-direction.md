# Home: a useful practice hub

Implemented first Home pass — 13 September 2026. The activity strip and later ideas remain deferred.

## What makes it worth returning to

Home should answer three questions immediately: what can I do now, what have I been practising, and what would be useful to work on next? Its value comes from connecting a conversation to another deliberate attempt. A fuller screen should still take only seconds to understand.

Keep the native Home / Library structure, cached startup and minimal appearance. Preserve the earlier decision to omit a Last session summary. Start with useful hierarchy and evidence; a branded visual system can follow.

## Reading order

### 1. Your next session

Make the current question the main item, above the statistics. Show the short scenario, enough title to distinguish it, and recorded engineering level. A single primary action says Resume for an active draft or Preview question when ready. Full requirements stay in preview/the workspace.

Keep Regenerate, Choose focus or level and Skip in the existing question menu. Preparing a replacement retains the current ready question until success. An active draft is never silently replaced. Closing the workspace returns to this same Home.

When no question exists, show preparation here. Loading and failure belong inside this area, without shifting the rest of the page. Automatic generation still happens only under the existing first-visit/no-question policy; no new inference on every Home visit.

### 2. This week

A compact horizontal summary gives the existing completed total and last-seven-days count. Those numbers remain secondary to starting a session.

Later, a seven-day activity strip can show actual practice days. Its purpose is recognizing rhythm, with no broken-streak guilt. It must use complete timezone-aware aggregates; the current first Library page and eight-attempt model snapshot are not sufficient to calculate it. No invented effort minutes, readiness percentage or mastery score.

### 3. Revisit

One optional learning opportunity, not a feed of past sessions. For example: “Retry safety — try explaining what happens after a lost acknowledgement.” Provide Review reasoning and Practise this concept actions.

The opportunity must come from a completed, persisted reflection linked to its original evidence. Model feedback is fallible: let the person inspect the source and dismiss a suggestion. Exclude greeting-only sessions and empty/generic feedback. Do not present assisted work as independent mastery. If there is no useful evidence, omit this section.

This is the strongest proposed premium feature: the app helps turn feedback into something the person can practise, rather than leaving it buried in a completed interview. A short retrieval exercise could follow later; it is not part of this first Home pass.

### 4. Explore system design

Show at most three compact topic rows, using the existing taxonomy and coverage data—e.g. Data modeling, API design, Queues & streams—with See all leading into topic browsing/Library.

A row can show a factual practice count or “Not explored yet.” Coverage describes exposure, not proficiency. Tapping a topic opens preparation with that topic selected for one question; global preferences remain unchanged. Do not generate or skip the current question merely by browsing a topic.

## States and navigation

- New user: next session and topic discovery; no empty progress charts or invented recommendations.
- Returning user: next session, small statistics, at most one grounded revisit, three topics.
- Active interview: Resume remains visually dominant. Exploring another topic does not discard work.
- After completion: keep the brief existing celebration; update cached statistics and any revisit suggestion after durable feedback is available. No permanent motivational banner.
- Offline: keep cached content, readable history and drafts. Explain inability to prepare only when that action is attempted.
- Voice remains an option inside the interview. Home starts the complete text experience and does not request microphone permission.

## Delivery order

1. Reorder/refine the existing question area and compact statistics; add a few topic entry points using existing APIs and account-scoped cached coverage. Validate the small-screen viewport, all question states and preserved drafts before adding more sections.
2. Add one evidence-linked Revisit opportunity. Derive it deterministically from persisted feedback, cache it with its source/version and invalidate on completion, deletion or account change. No extra LLM request to render Home. Generation only follows an explicit practice action and existing replacement protections.
3. Add a weekly activity strip only with an additive daily-count aggregate in the saved IANA time zone, complete historical coverage and matching cache semantics. An optional weekly goal or interview date should wait until it clearly improves recommendations.

Success means a person can resume or preview immediately, understand one useful next learning action, and see believable progress. Every section needs a clear action or a concrete piece of evidence. Decorative analytics, a large greeting, a second voice entry point and another Last session block do not earn space in this pass.

## Implementation boundaries

The current question is the leading neutral surface; existing total/rolling-seven-day statistics follow. Revisit chooses one `needs_practice` observation with a nonempty source quote and completed reflection. Its dismissal is account-scoped on this device and changes to the underlying feedback can resurface it. Coverage is cached alongside Library warm-up and restored before publishing Home. Unknown coverage omits a count until available. Explore opens coordinated preparation; active interviews disable replacement and explain why. No generation, entitlement or public API contract changes were needed.
