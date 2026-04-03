# Answer Flow

## Scope

The answer route is the focused challenge workspace behind [src/app/answer.tsx](/Users/dawi/dev/drillbit/src/app/answer.tsx). It owns one active challenge at a time and switches between three user modes:

- `solo`
- `coach`
- `reveal`

## Bootstrap

On mount, the controller resolves the working mode in this order:

1. Route mode
2. Persisted session mode
3. Saved preferred mode
4. `solo`

The screen then loads:

- the selected challenge
- any persisted challenge session
- the selected model list

If the challenge is no longer `ready` or `in_progress`, the screen resets to an empty state.

## State Model

There are three main state groups:

- Challenge state: active challenge, loading state, selected model
- Draft state: notes draft, assistant draft, selected mode, conversation history
- Assistant state: coach field status, reveal field status, assistant history, current request sequence

## Assistant Lifecycle

Both coach and reveal requests follow the same sequence model:

1. Begin request and allocate a sequence id
2. Stream partial output into the active assistant field
3. Ignore stale updates if a newer request invalidated the sequence
4. Commit the final assistant turn into conversation history
5. Persist the updated session snapshot

Statuses move through:

- `idle`
- `thinking`
- `streaming`
- `done`
- `error`

Changing challenge or switching away from a mode invalidates any in-flight request for that mode.

## Persistence

Draft persistence is local and debounced.

- Notes and assistant drafts auto-persist after a short delay
- Explicit actions like save, done, and assistant completion force persistence
- Cleanup flushes happen on unmount or challenge switch if there are unpersisted draft changes

## Mode Rules

- `solo`: hides assistant history and disables automatic coach/reveal behavior
- `coach`: enables auto-coach after enough note progress and cooldown checks
- `reveal`: loads a persisted reveal answer if available, otherwise streams a new reveal

## Terminal Actions

- `save`: persist the current session and mark the challenge `in_progress`
- `skip`: skip the challenge, reset local answer state, return to params
- `done`: persist, complete the challenge, return to params, and kick off background summarization

## Current Refactor Shape

The control plane now lives in [src/components/answer/use-answer-controller.ts](/Users/dawi/dev/drillbit/src/components/answer/use-answer-controller.ts). The screen component should stay mostly presentational, with only local UI concerns like the collapsible header and assistant sheet visibility.
