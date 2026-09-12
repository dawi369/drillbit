# Interviewer personality V4

Implemented 11 September 2026. This is the current development personality. V2/V3 remain available for jobs pinned to those editions.

## What changed

A practice partner can chat without demanding progress. An absurd design joke gets a little playfulness; a direct question gets an answer; a technical mistake gets a correction without praise first. A request to stop joking changes the tone. The interviewer asks about one decision at a time and does not turn acknowledgements into another quiz.

- Whole-message recognition for unambiguous English greetings and social acknowledgements supplies only the last three consecutive social exchanges. No keyword matching inside technical sentences. No generated answer is replaced with canned text. Unknown or mixed messages use full context. The next substantive turn gets the complete bounded transcript and question again; this never deletes stored history.
- Main V4 reference context is escaped XML inside an explicitly untrusted reference block. Actual conversation retains user/assistant roles. The model selects a small internal conversational move and generates text. The backend, not the model, assigns follow_up/reply from the validated request kind. Neither the move nor model-selected lifecycle state reaches the public API.
- Gemini 3.1 Flash-Lite remains the only model. Simple social turns keep reasoning disabled; substantive V4 turns use low reasoning. V2/V3 and other inference operations retain their earlier behavior. No second classification request, automatic paid repair, or delayed replacement of streamed replies.

## Reviewed live evidence

Two complete candidate runs of 24 synthetic turns each returned 48/48 valid response envelopes. These were reviewed for content, not just schema. Logs: `/tmp/drillbit-v4-release-a.log`, `/tmp/drillbit-v4-release-b.log`. A final targeted refusal check is in `/tmp/drillbit-v4-boundary.log`. The latter follows a small refusal-wording revision; the two candidate runs are not proof of every possible final conversation.

| Behavior checked | Observed result |
|---|---|
| Greeting → small talk → acknowledgement | No technical question or invitation to start in either final candidate run |
| Explicit readiness | Resumed the supplied comment-feed exercise |
| Hamster/pigeon banter | Played along without an appended technical pivot |
| “No jokes now” | Switched directly to the write-retry explanation |
| Anxiety and small hints | Reduced pressure and offered one manageable direction |
| False exactly-once claim | Corrected duplicate-side-effect risk without promising eventual delivery in the two final candidate runs |
| “Stop repeating pagination” | Acknowledged the correction without inventing a database choice |
| “What have I decided?” | Recalled cursor fields and correctly kept database selection open |
| Direct Postgres question | Answered directly rather than quizzing |
| Requested full example | Supplied a possible table design, distinct from user work |
| Pause | Short acknowledgement without more probing |

Actual generated examples:

> “The throughput is abysmal, but the debugging process is adorable.”

> “You've locked in the pagination cursor using a timestamp-ID pair, but you're keeping your database options open.”

> “Retries actually risk duplicates rather than guaranteeing exactly-once delivery. If the first attempt succeeds but the acknowledgement gets lost, the retry will trigger a second operation.”

The two runs cost $0.013803 and $0.015516 in reported provider usage. Median complete responses were 1,203 and 1,377 ms; maxima 2,702 and 2,993 ms. These are synthetic provider-completion timings, not app time to first visible token. Low reasoning adds latency and token cost but improved technical consistency over disabled reasoning in these experiments.

## Evaluation scope

This clears the sampled product behaviors that blocked V3. It is not universal personality or correctness certification. Greeting recognition is deliberately narrow and English-focused; other languages and ambiguous messages still rely on the model. Longer real sessions, very large histories, humor preferences and physical voice interaction are not established by these samples. The refusal check did not disclose the actual policy, but is not a prompt-injection guarantee.

Run `bun scripts/evaluate-personality.ts` with an environment-provided OpenRouter key. `EVAL_PROMPT` selects an edition, `EVAL_MODEL` selects a test model, `EVAL_REASONING` overrides the test effort, and `EVAL_CASE` narrows cases. Defaults use the production schema, parser and reasoning policy. Output is synthetic and saved to ignored `.local/personality-evaluation.json`; normal application logs contain no private practice content.
