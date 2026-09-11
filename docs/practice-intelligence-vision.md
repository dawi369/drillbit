# Practice intelligence: question library, skills and progression

Status: the working library/metadata/selection foundation was implemented on 10 September 2026. See architecture and acceptance records for actual behavior. Skill assessment, adaptive review cadence and advanced context assembly below remain future vision; they are not implemented claims. The user chose a clean development practice reset instead of historical enrichment.

## Product promise

Help someone reason through unfamiliar system-design problems independently, explain decisions and trade-offs, and revisit weaknesses until the improvement survives a different scenario. The durable asset is a searchable record of questions, attempts, discussions and evidence. Tags organize this record; they are not a proficiency score.

Current implementation already retains account-owned completed/skipped challenges and supplies the latest 20 such records plus reflections to generation (`apps/api/src/jobs.ts`). It does not yet provide the taxonomy, independent repeat attempts or evidence-based selection described here.

## Minimal interface

Keep two tabs: Home and Library (proposed replacement for Memory). Home retains counts and one current/recommended practice card, with a short factual reason such as “Revisit retry safety in a different system.” Prepare continues to allow temporary focus and level overrides without changing Settings. No skill dashboard or curriculum setup is required before starting.

Library defaults to chronological attempted questions, with search and a native filter sheet. Rows show title, recorded level, last activity/status and up to three concept tags. Filters cover concept, engineering level, practice format, date, outcome and help exposure. Skipped questions live under Library's … menu, with a count; they do not crowd the default completed list. An optional Revisit filter groups deliberately saved/recommended work. Search spans title, prompt and tags initially; transcript search is a later extension with explicit scope.

Question detail holds the original immutable question, tags, dated attempts and their transcripts/reviews. Selecting an old attempt is read-only. “Try again” previews the exact question and creates a new attempt only on Start. “Practise this concept” produces a different scenario with the same target concept. These are deliberately separate actions.

A compact progress section shows coverage and specific evidence: “Retry safety: demonstrated without help in two different systems; last practised 12 days ago.” Unobserved skills say “Not enough evidence.” No percentage ready for Senior, invented percentile, company-equivalent level or universal mastery score.

## Metadata: separate what a question asks from what a person demonstrated

### Question metadata (versioned, stable for each generated question)

| Field | Meaning / allowed content | Origin |
|---|---|---|
| questionId, version, familyId, variantOf | Exact identity, version and explicit repeat/variant relationships; family may remain unknown until validated | Server |
| title, prompt, constraints | Immutable original specification and all assessable requirements | Validated generation |
| focus | Existing software-engineering focus; default target remains system design | User/request |
| engineeringLevel | Intern, Junior, Mid-level, Senior, Staff, Principal; recorded intended scope, not measured user ability | User/request |
| format | system_design, focused_decision, debugging, design_review, migration | Selector/request; align with existing question-kind contract during implementation |
| primaryConceptId | Exactly one central teachable concept | Selector chooses; generator must satisfy |
| secondaryConceptIds | Zero to two concepts materially exercised by visible requirements | Generator selects from allowed IDs |
| competencyTargets | One to three reasoning dimensions, with a reference to the visible requirement exercising each | Validated generation |
| scenario | Short search label, e.g. notification delivery, file storage, feature flags; does not create a new skill | Generation |
| constraintsProfile | Optional stated values: load, latency, durability, consistency, geography, cost/security limits. Unknown stays absent | Extracted from visible specification |
| provenance | Created time, source kind, source question IDs, taxonomy/prompt/model/selector versions, selection reason, source snapshot ID | Server |

Do not let the LLM invent free-form canonical tags. Each concept has a stable ID, label, concise definition, parent category, aliases, examples and exclusion examples. Merge/rename through a versioned mapping, not silently rewriting historical evidence. Return primary/secondary IDs and short references to relevant requirements; reject invalid IDs, duplicate IDs, redundant synonyms and counts outside 1–3. A weak association is insufficient for a secondary tag. Tag generation uses the existing question call, not another paid request.

### Initial concept vocabulary

The groups below are navigation categories, not additional question tags. Start with these 24 concepts; add narrower concepts only when real history needs them.

| Group | Canonical concepts |
|---|---|
| Data | Data modeling; Indexing & access patterns; Transactions; Consistency; Replication; Partitioning |
| Traffic & performance | API design; Caching; Load balancing; Rate limiting; Capacity planning |
| Async & coordination | Queues & streams; Retry safety & idempotency; Ordering & coordination; Scheduling |
| Reliability & operations | Fault tolerance & recovery; Overload & backpressure; Observability; Deployment & migration |
| System boundaries | Authentication & authorization; Tenant isolation; Data lifecycle & privacy; Multi-region design; Cost efficiency |

Redis, Kafka and PostgreSQL are optional technology mentions/search aliases, never evidence that someone understands caching, delivery semantics or data access. Likewise “URL shortener” is a scenario, “Senior” is scope, and “In-depth” is interview style; none belongs in the concept-tag list.

Tagging must not leak the intended solution before the attempt. Library and completed reviews can show all concept tags. Prepare/preview uses only neutral metadata or concepts explicitly requested/stated in the problem. A question designed to test whether the user discovers retry safety must not display “Idempotency” as a pre-answer hint. The full hidden classification cannot introduce hidden grading criteria: only visible requirements may be assessed.

### Reasoning competencies (independent of concepts)

1. Clarify requirements and assumptions.
2. Estimate scale and identify bottlenecks.
3. Define boundaries, interfaces and data flow.
4. Model data and preserve correctness.
5. Compare alternatives and justify trade-offs.
6. Reason about failure, recovery and operations.
7. Evolve a design through rollout/migration.
8. Explain decisions clearly and respond to changed constraints.

A concept indicates what was practised. A competency indicates how the reasoning went. For example, a candidate may know partitioning vocabulary but not explain how a chosen key creates a hotspot. Higher question levels broaden ambiguity and responsibility; they never create secret expected buzzwords or require a predetermined architecture.

### Attempt and evidence metadata

Attempt fields: attemptId, questionId/version, status, started/completed/skipped timestamps, recorded interview-style changes, durable transcript, exposure facts, completion snapshot/revision and optional user feedback. Preserve abandonment/backgrounding separately from explicit Skip. Elapsed wall time is not active reasoning time; do not present it as a speed score.

Evidence observations attach to an attempt, concept and competency with exact turn/criterion references, observation text, assessor version and an evidence state:

- demonstrated: supported by the user's actual reasoning;
- developing: partially supported or corrected after prompting;
- needs_revisit: a material misconception or unresolved visible requirement;
- not_observed: absent/insufficient discussion, never an automatic failure.

Track help exposure separately: unassisted in the available record, prompted, example exposed, adopted text, or unknown. Normal interviewer questions are not automatically help; leading prompts/examples are. Generated/shown/acknowledged evidence stays conservative. Self-reported confidence, if added, is separately sourced and never substituted for observed evidence.

A follow-up can introduce an additional concept. Record it as encountered evidence in the attempt; do not rewrite the original question's tags or penalize its initial answer for a later constraint. Responses after an example are useful learning, but are not proof of independent recall. Repeated citations from one attempt must not count as multiple independent successes.

## Skipped questions and the pool

Skipping is preference/scheduling information, not a failed assessment. Preserve any draft and discussion. An optional, non-blocking reason can be added from the skipped item's menu: Not now; Too familiar; Too hard; Not relevant; Problem unclear. Never require another questionnaire to exit a question.

Keep attempt status and future eligibility separate. Skip records a historical event and excludes that exact question from automatic selection. A reason can create a bounded preference signal; it must not silently blacklist an entire concept or downgrade the user's engineering level.

Skipped library actions:

- Preview: read the original without starting/reinstating it.
- Add back to pool: make the exact question eligible; it remains historically skipped until another attempt is started/completed.
- Practise now: normal preview → Start. Existing active work is preserved; do not replace it silently.
- Resume saved attempt: available when a skipped attempt has meaningful saved work, explicitly restoring it with an audit event. This requires a deliberate lifecycle addition, not editing a completed attempt.

The pool is a logical selection set, not hundreds of pregenerated questions. It combines eligible saved questions, due concept targets and fresh-generation candidates. Adding a question back does not immediately incur generation costs or replace today's work.

## Selecting the next useful question

A deterministic server selector chooses a learning intention; the generator authors the problem within that brief. Do not ask an LLM to invent the entire progression policy from a transcript dump.

Order of authority: explicit one-question user request; existing active/ready-work protection; exact-question exclusions and eligibility; target-level scope; due/recent evidence and coverage; diversity among equally useful candidates. The selector cannot silently change global focus or level. Restored pool items compete rather than always jumping the queue.

Three intentions are sufficient initially:

- Revisit: test a previously identified issue after a gap, preferably in a different scenario and without revealing the old answer.
- Broaden: cover a relevant underpractised concept, using prerequisites as a recommendation rather than a gate.
- Stretch: deepen ambiguity or introduce one changed constraint within the selected level when evidence supports it.

Use a simple transparent starting cadence: across a rolling ten automatically selected questions, aim for about five revisits, three coverage questions and two stretches when eligible. This is a product hypothesis, not an evidence-backed optimum. Never manufacture a weakness to fill a quota. Cold starts emphasize broad fundamentals at the requested level; explicit focus overrides the mix. Allow a lighter follow-up after difficulty without forcing a downgrade.

Initial review intervals may be 2, 7 and 21 days after supported independent demonstrations, shortened after unresolved reasoning and left uncertain after substantial help. These are tunable hypotheses for conceptual practice, not a claimed validated system-design memory model. A due review is an opportunity, never a debt or compulsory daily queue. Skips/missed days do not create a backlog of punishments.

Within an interview, follow-ups use the same selected learning intention but stay grounded in what the user said. They should probe one relevant decision, request a justification, or change one explicit constraint; not recite a taxonomy checklist. Afterward, one concrete observation and a useful next practice intention are enough.

## Bounded generation snapshot

Build the snapshot from trusted account-scoped records at job execution, preserve its revision and persist the bounded selection inputs for debugging. Include:

- requested focus, level, format and optional instruction;
- selected intention, primary concept, allowed secondary concepts, and factual reason;
- up to five relevant cited evidence summaries with help exposure and dates;
- latest ten question signatures (title, concepts, scenario, level, completion/skip status);
- compact per-concept coverage counts, distinct attempts and last demonstrated dates;
- relevant skip preferences and eligible restored question candidates;
- recent selection mix, near-duplicate exclusions and unknown/missing-history markers.

Use an initial maximum of roughly 2,000–3,000 input tokens for personalization, retaining the explicit request and most relevant evidence first. Older relevant evidence is retrieved by concept rather than disappearing merely because twenty newer questions exist. Free-form user text and model summaries are untrusted data, never instructions to override policy.

Exact exclusions must be enforced in the database, not solely inside this limited prompt. Dedupe exact IDs/content hashes; compare structured signatures for likely near-duplicates, with explicit repeat/variation intentions allowed. Start with these deterministic checks. Add embeddings only if evaluation demonstrates scenario paraphrases defeating them. Limit regeneration attempts; a failed replacement preserves the existing ready question.

## Data model and operational boundaries

Conceptual entities: Question (immutable), Attempt (repeatable lifecycle), TranscriptTurn, Concept/TaxonomyVersion, QuestionConcept, SkillObservation, QuestionEligibility, SelectionSnapshot. Derived learner summaries are projections rebuilt from immutable attempt evidence, not a second untraceable truth store. All private entities are account scoped.

The current challenge combines question and attempt. Introduce the distinction additively: retain challenge IDs as compatible attempt identities and add a linked immutable question record. Backfill existing questions without changing text, dates, level or completed transcripts. Old unknown tags/evidence remain unknown until a versioned enrichment job is explicitly run. Enrichment cannot rewrite old feedback or invent evidence from a final answer alone.

Atomic completion freezes transcript and conservative exposure before observations are produced. Reflection failure does not lose the attempt; progress says review pending and generation can fall back to coverage-based selection. Idempotent projections prevent duplicate evidence on retries. Race tests cover add-back versus skip/start, two devices selecting work, completion versus reflection, account deletion versus enrichment and duplicate jobs. Revision-check eligibility writes. Existing one-active-attempt policy remains until intentionally changed.

New APIs and native DTOs require additive contract/fixture changes for library pagination, filters, eligibility actions, tags, observations and recommendation reasons. Server-side pagination/counts must cover the whole library, not the currently loaded hundred items. Index account/status/date and account/concept joins; full-text search is separately scoped. No vector service or extra provider is necessary for the first release. Generation tags and post-attempt evidence share existing generation/reflection calls where possible.

Deleting an account deletes source content, observations and personalization snapshots. If per-attempt deletion is offered, rebuild dependent summaries and remove their citations. Avoid logging prompts, drafts or private evidence during selection diagnostics.

## Delivery and product acceptance

1. Library foundation: explicit question/attempt relationships, paginated history, skipped menu, add-back and preserved draft/retry paths. No automatic intelligence required to make it useful.
2. Controlled metadata: taxonomy, validated 1–3 concepts, question filters, conservative historical enrichment and concept detail pages. Verify solution tags are not exposed as accidental hints.
3. Evidence: cited per-attempt observations, exposure distinctions and basic coverage view. Human review must establish grounded feedback before it drives recommendations.
4. Adaptive selection: bounded snapshot, explainable revisit/broaden/stretch policy, explicit override and nonrepetition checks. Roll out behind a capability flag with the current generator as fallback.

Acceptance requires representative questions across all six engineering levels; stable tag choice on paraphrases; invalid/overbroad tag rejection; mixed good/weak/unobserved answers; helped versus independent answers; transfer across scenarios; skipped history/add-back without data loss; cross-account isolation; low-history/offline/reflection-failure behavior; and duplicate/concurrency handling against D1. Evaluate resulting practice usefulness and justified progression with human review, not JSON validity alone. Track changed-scenario independent demonstrations and user corrections to recommendations rather than maximizing time spent or raw completion count.

The foundation uses spacing/retrieval as a learning principle, not a promise of hiring outcomes. The Learning Scientists summarize supporting research and limitations: https://www.learningscientists.org/faq and https://www.learningscientists.org/learning-scientists-podcast/2017/10/4/episode-4-spaced-practice . The taxonomy includes concrete operating concerns reflected in engineering references such as AWS Well-Architected failure handling: https://wa.aws.amazon.com/wellarchitected/2020-07-02T19-33-23/wat.question.REL_5.en.html . Neither source validates this product's proposed cadence, taxonomy or assessment quality.
