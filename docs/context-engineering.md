# Interviewer context engineering

Implemented 10 September 2026. Standard is the only active style; Quick and In-depth remain visible but disabled. Existing style values remain readable; new generation and new turns normalize to Standard.

## Voice source and interpretation

Inspected `/Users/dawi/dev/t23-dev/src/lib/chat-personality.ts`, its tests and `docs/chat-behavior.md`. Adopted its authored conversation mechanics: natural contractions, direct answers, specific observations, no routine praise, one useful question, remembering corrections, and restraint with humor. No studio biography, sales funnel or claims were imported. This is a Drillbit-specific interviewer voice, not a reproduction of Poke's private prompt.

The interviewer follows one decision into a concrete consequence. Clarification answers directly, hints give one direction, and examples are labelled assistance. Follow-ups do not grade or suggest finishing. Engineering level controls scope; style controls conversational approach.

## Context assembly

- Stable XML policy: `apps/api/src/prompts/interviewer.ts`, edition `interviewer-standard-v2`.
- Server-owned history: latest eight completed/skipped attempts from the authenticated account, excluding the current attempt. Includes scenario, level, concepts, status, date and capped prior feedback (240 characters per field). No raw historical answers or inferred skill scores. Missing assistance evidence is explicitly unknown; skipped questions carry no feedback-based ability inference.
- Each interview job stores that snapshot and prompt edition with its existing revision-checked input. Retries reuse that captured context.
- Committed conversation uses real user/assistant roles, inspired by T23's context handling. Current action and history remain escaped XML data. Completed assistant outputs retain their JSON structure; current output still uses the existing strict JSON schema and streaming protocol.
- `boundedContext` preserves current work, drops oldest conversation entries when necessary, and exposes omitted-turn counts. The existing 40,000-character logical context budget is not an XML byte or token budget. XML escaping may expand serialized size.
- Question generation receives the same historical snapshot for variety, plus the existing deterministic concept selection. History never silently changes the requested engineering level or introduces hidden grading criteria.

## Editing and future prompt switching

Keep policy/voice, style-specific instructions, history assembly and public response schemas separate. Add an immutable prompt edition to the resolver when changing a deployed style; do not remove editions used by queued jobs. Select the edition server-side when accepting a turn, then persist it in the job. A future authenticated configuration selector can change the edition for subsequent turns without changing transcripts, streaming or the response contract. Runtime prompt administration and user-configurable prompts are not implemented yet.

Legacy jobs without an edition use the current Standard fallback. Unknown explicit editions fail instead of silently substituting a prompt. Historical style records remain decodable; new requests currently normalize to Standard.

## Evaluation

Synthetic live evaluator: ignored `.local/evaluate-interviewer-context.ts`; output `.local/interviewer-context-evaluation.json`. Cases cover a concrete follow-up, direct clarification, nudge, correction, skipped-history interpretation, XML-shaped injection, a greeting/stuck answer and an already-addressed topic. No real candidate answers were submitted for this evaluation.

Reviewed successive batches, not just schema validity. Early replies repeated a resolved retention question and appended a question to clarification. Stronger action boundaries and native conversation roles improved those cases, but repetition, canned refusal phrasing and occasional multi-question wording remain model-quality limits. Do not interpret these samples as a comprehensive interview-quality benchmark or prompt-injection guarantee. Provider failures are recorded separately from valid replies.
