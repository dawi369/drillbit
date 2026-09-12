# Interviewer context engineering

Implemented 10 September 2026. Standard is the only active style; Quick and In-depth remain visible but disabled. Existing style values remain readable; new generation and new turns normalize to Standard.

## Voice source and interpretation

Inspected `/Users/dawi/dev/t23-dev/src/lib/chat-personality.ts`, its tests and `docs/chat-behavior.md`. Adopted its authored conversation mechanics: natural contractions, direct answers, specific observations, no routine praise, one useful question, remembering corrections, and restraint with humor. No studio biography, sales funnel or claims were imported. This is a Drillbit-specific interviewer voice, not a reproduction of Poke's private prompt.

The interviewer follows one decision into a concrete consequence. Clarification answers directly, hints give one direction, and examples are labelled assistance. Follow-ups do not grade or suggest finishing. Engineering level controls scope; style controls conversational approach.

## Context assembly

- Stable XML policy: `apps/api/src/prompts/interviewer.ts`, edition `interviewer-standard-v4`.
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

## Personality v3 — 11 September 2026

Research: [Poke's public product description](https://poke.com/) emphasizes a personal conversation in familiar messaging; [Cognition's first-party account](https://cognition.com/blog/interaction) emphasizes fun and familiarity. These describe product intent, not access to Poke's private prompt. [Google's conversation-design guidance](https://developers.google.com/assistant/conversation-design/learn-about-conversation) supports cooperative, concise, contextual turn-taking; its historical Actions platform is not a proposed voice dependency. Re-read T23's authored `src/lib/chat-personality.ts`: especially letting a reply land and not forcing banter back into a funnel.

Drillbit interpretation: a relaxed practice partner with light situational wit, no compulsory technical pivot after every greeting, no ridicule, no false praise for incorrect reasoning, and direct answers to inline questions. Pauses stop probing. The current action controls the response envelope, not the user's conversational intent. A follow_up can be an acknowledgement; the existing transcript supports it without schema changes. Social messages do not count as incorrect engineering evidence in reflections.

V3 moves the XML reference snapshot BEFORE conversation history, uses natural user/assistant text roles for committed turns, and puts the actual current utterance last. Policy and reference metadata stay XML; literal user text stays untrusted in user-role messages. Allowlisted action metadata in the system policy determines the existing output type. V2 policy and message assembly remain available for explicitly pinned queued jobs. Unknown prompt editions still fail. Prompt administration remains deferred.

Single model now Gemini 3.1 Flash-Lite, reasoning disabled. 2.5 remains accepted as a legacy settings value and normalizes to the active model. This trades token price and some latency for more consistent behavior in the synthetic evaluation; it is not a claim of flawless instruction following. Listed OpenRouter prices checked 11 September: [2.5](https://openrouter.ai/google/gemini-2.5-flash-lite) $0.10/$0.40 and [3.1](https://openrouter.ai/compare/google/gemini-3.1-flash-lite/tencent/hy3) $0.25/$1.50 per million input/output tokens. Provider routing prices can vary.

Reproducible evaluator: `bun scripts/evaluate-personality.ts` with an environment-provided key. `EVAL_MODEL`, `SKIP_BASELINE` and `EVAL_REASONING` are evaluation-only options. Synthetic outputs are written to ignored `.local/personality-evaluation.json`; no real candidate data is sent by this script.

### Product acceptance: partial

Reviewed multiple live batches, including the original screenshot's multi-turn exchange, banter, anxiety, hint requests, pauses, false exactly-once claims, corrections and XML-shaped instruction requests. The old prompt reliably reproduced forced task redirection. The latest 3.1 run returned 14/14 valid envelopes, with complete provider responses 745–1133 ms (not time to first token or end-to-end app latency). Greeting/small-talk turns and pauses improved; the tiny hint was useful and the response corrected the exactly-once misconception.

Known failures: an occasional joke still gets a technical pivot; routine praise persists; one response assumed a single table that the user had not committed to; 'retries guarantee at-least-once' is too absolute without availability/retry bounds. Some anthropomorphic phrasing and refusal copy remain awkward. Do not claim this meets the final personality bar. An experimental minimal-reasoning batch did not eliminate pivoting, so it is not enabled. No automatic paid repair calls or brittle keyword-to-canned-reply router were added.

## Current edition: V4

The V3 partial acceptance above is historical. V4 separates pure social context, uses a model-internal conversational move plus text, and assigns the existing public outcome server-side. Full context returns on substantive messages. Escaped reference XML is now marked untrusted inside the system message, while actual turns use native conversation roles. Low reasoning is enabled only for substantive V4 interview calls. See [V4 personality acceptance](personality-acceptance.md) for the two 24-turn candidate reviews, timing/cost tradeoff and limits. No new user-facing mode or model picker is added.
