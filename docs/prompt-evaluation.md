# Practice prompt evaluation — 9 September 2026

Model: `google/gemini-3.1-flash-lite`. Prompt family: `practice-v2`. These are synthetic live OpenRouter checks, separate from the deterministic D1/API tests and simulator fixtures.

Run `bun scripts/check-practice-model.ts` for generation, hint, reasoning check, direct question, outline, example, suggested draft and reflection. Run the same command with `--edges` for empty, wrong and vague answers, frustration, injected instructions and missing personal context. Both commands require the configured provider key and incur model usage. Results are saved under ignored `.local/` files.

## Observed results

All eight actions and six edge cases passed their output schemas and the insertable-draft field boundary. Human inspection found that wrong-answer checking identified the outage/availability contradiction; missing-context handling did not fabricate an interviewer conversation; an injected request did not obtain a complete solution or a false authorship claim.

The first run exposed examples being placed in the suggested-draft field despite a prompt instruction. Action-specific schemas now require that field to be null except for draft suggestions. Outline/example adoption uses the explicit, displayed result body, never an implicit suggested-draft field. Separately generated rubric excerpts were unreliable; the backend now derives its evaluator checklist directly from visible prompt requirements.

## Calibration still needed

Schema validity is not factual correctness or conversational quality. Some responses remain formal, overlong or too eager to diagnose missing details. The frustration case introduced an ungrounded performance-bottleneck claim. An early draft suggested decreasing a version number for rollback, which is unsafe for clients that enforce monotonic versions. The first prompt pass asks for direct answers, one observation, concise reviews and checks for ordering/failure contradictions; these are instructions, not a guarantee.

Prioritize conditional language for speculative risks, concrete support from the question/answer, technically coherent rollback examples, and a warmer response to frustration. Compare changes against this same evaluation set; do not report scores or independent proficiency from schema success. Representative user-approved tone examples and physical-device conversation review remain valuable calibration inputs.
