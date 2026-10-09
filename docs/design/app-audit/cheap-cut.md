# Phase 3: the cheap cut

For each of the five patterns: the full version, the cheap cut that still gets the value across, what the cheap cut needs, and the risk. "Needs" uses five buckets: **view** (SwiftUI only), **content** (authoring per question family), **API** (contract change: OpenAPI + fixtures + DTOs), **model** (prompt/schema change), **native** (new capability: PencilKit, vision, etc.). Recommendations at the end; the user decides.

Grounding: [notes.md](notes.md) §3 "Interview turn model" and "Contract constraints", [steal-list.md](steal-list.md).

## 1. Tiny steps with instant feedback

| | Full version | Cheap cut | Needs | Risk |
|---|---|---|---|---|
| What | Every framework step is a micro-exercise: order these four steps, pick the failure point, choose the component that fixes it, name the missing requirement. Each answered in < 1 s with a deterministic check and a one-line "why". LLM grades only free text. | **Deterministic checks inside the interview, generated with the question.** The question generator already writes `path` (3–5 steps), `opener`, and per-turn `choices` (≤ 3). Extend the generated question with 2–3 authored-at-generation "moves" per step: a `choose` (one of 3, one correct, each with a 1-line why) or `order` (4 items). The client checks locally; the result is sent as a normal `answer` turn so the interviewer reacts to what you picked. | **model** (generation schema: `moves[]` per step, validated like `path`), **API** (declare `path` and `moves` in wire.ts; they're additive), **view** (a move row in the document, Guided choices already exist). | Generated checks can be wrong or trivially guessable; needs validation (`scripts/evaluate-questions.ts`-style) and a "that's not it" escape to free text. Positioning: a move must read as the interviewer asking, not as a quiz; no score, no streak. |
| Alt cut | Reuse `GuidedChoices` only (already built): 2–3 tappable answers after every follow-up, in every mode, not just Guided. | **model** (choices for coach_me too), **view**. | Choices sent as answers already work; the "feedback" is still a model round-trip (2–8 s), so it isn't instant. |

Cost of the recommended cut: one generation-schema change, one wire declaration, one new row type. No simulator, no new native capability.

## 2. Manipulable diagrams

| | Full version | Cheap cut | Needs | Risk |
|---|---|---|---|---|
| What | A live simulator: the learner's own diagram runs; toggle a cache, kill a node, 2× traffic, and watch requests flow, queues fill, latency climb. | **One pre-authored diagram per question family with 2–3 toggles and precomputed outcomes.** Each family (job queue, URL shortener, chat, feed, rate limiter, file sync…) ships a small scene (5–8 nodes, 6–10 edges) as JSON plus a lookup table: toggle state → which edge animates, which node fails, one-line outcome, one metric. The interviewer uses it as a *probe*: "Kill the worker mid-job. What happens?" The learner predicts (a tiny step), then the scene plays the outcome. Never shown before the learner has committed a high-level design. | **content** (one scene + table per family; ~10 families to start), **view** (a `SystemScene` SwiftUI/Canvas renderer, CSS/JS in the prototype), **model** (interviewer gets `scene.state` as structured JSON in context so pushback refers to the toggled state), **API** (additive: `challenge.family`, `scene` reference). | Pre-drawn scenes can leak the answer, the exact thing the user rejected. Mitigation: the scene is the *interviewer's* probe after the learner's design exists, and it is clearly labelled as such; or the probe scene is derived from the learner's canvas (pattern 3) when it has the needed nodes. Authoring 10 families is real work. |
| Alt cut | Welcome-style scripted "receipt" animation, no diagram: a request row travels, a node fails, a fix is pinned. Already proven in `RetryExample`. | **view/content** only. | Reads as onboarding, not as interview content; limited to 1–2 concepts. |

## 3. Canvas with a component palette

| | Full version | Cheap cut | Needs | Risk |
|---|---|---|---|---|
| What | Freeform Excalidraw-style canvas: drag, resize, bind arrows, labels, zoom/pan, libraries. | **Lanes and slots, tap-to-place, auto-layout, tap-two-to-connect.** Three fixed lanes (Clients · Services · Data) or a 3×N grid. A palette of ~8 generic nouns (client, API/service, worker, queue, cache, DB, blob store, external). Tap a palette item → it lands in the next free slot in the right lane; tap two nodes → a directed edge with an optional 1-word label; long-press → rename/delete. Auto-layout, no drag. The canvas serialises to `{nodes:[{id,kind,label}], edges:[{from,to,label}]}` and is sent **with** the answer text as structured JSON (the interviewer sees the graph, not an image). | **API** (answer gains an optional `diagram` object; versioned, ≤ a few KB; stored with the turn and frozen at completion), **model** (interviewer prompt reads the graph; critique refers to node ids), **view** (palette + lanes + edge picker; Canvas or plain SwiftUI). | Phone thumbs: slots must be ≥ 44 pt; a 390-pt-wide screen fits 3 lanes × ~6 rows before scrolling. Free text + diagram doubles the "what am I supposed to do" load; the framework path (pattern 5) has to tell the learner *which* step is a drawing step (high-level design) and which is text. Contract: today the answer is a string ≤ 20,000 chars; adding `diagram` is additive but touches completion freeze, retry and conflict paths. |
| Compare | Freeform drag canvas | **view** heavy (gesture system, hit testing, zoom), same API | Hard with a thumb; most of the time goes to fighting the editor, not designing. |
| Compare | PencilKit sketch read by a vision model | **native** (PencilKit), **model** (vision call per sketch, slow and costly), **API** (image upload) | Fast to draw, slow and unreliable to interpret; critique can't point at a node id; no accessibility story. |

## 4. AI critique like a mock interview

| | Full version | Cheap cut | Needs | Risk |
|---|---|---|---|---|
| What | Pushback during the answer (interrupting in voice), plus a rubric-scored, step-by-step report with transcript and diagram evidence. | **Reuse turns + reflection, add a rubric per framework step, give the model the diagram as JSON.** Pushback already exists (every reply is a follow-up). Change the *shape* of the reply so the interviewer names the step it is probing (`step` already exists) and, in Mock, flags a curveball (`curveball` exists server-side, not in the native DTO). Reflection: keep one strength / one gap quoted from evidence, then a per-step table (covered / thin / missed, one quote each). Drop Strong/Mixed/Weak. | **model** (reflection schema: `steps[] {name, status, evidence}`; interviewer prompt uses diagram JSON), **API** (DTO adds `curveball`, `steps`), **view** (Reflection re-layout). | Rubric status can read as a score; keep it to three honest states with a quote each and no total. Evidence grounding already drops unmatched quotes, so thin answers get "not enough to judge" rather than invented praise. |
| Also | The `wrap_up` beat ("Finish & review / Keep going") | **model + API** (interviewSchemaFor allows wrap_up for answer/continue again; `interviewWrapUp()` returns a result) | Small server change; without it Mock has no ending beat. |

## 5. A visible path through a framework

| | Full version | Cheap cut | Needs | Risk |
|---|---|---|---|---|
| What | A step tracker that is itself the workspace: each step has its own artefact (requirements list, entities, API table, canvas, deep-dive notes), progress is visible, and the report maps onto it. | **A fixed step list, current step driven by the interviewer's `step`, with one artefact type per step.** Fixed path for every question: Requirements · Entities · API · Design · Deep dive (Hello Interview's published framework, verified; Data Flow optional, folded into API). The interviewer's reply carries `step`; the bar advances. Per step the composer changes shape: bullets for Requirements/Entities, a 2-column line for API, the lane canvas for Design, free text for Deep dive. Mock shows the step clock split from the framework's published proportions (15/50/85/100 already in `roundTiming`). | **model** (teaching prompt: fixed path replaces generated `path`; `step` index 0–4 for every mode, not only Guided), **API** (declare `path`/`step` in wire.ts; `path` can stay generated for Guided's finer steps), **view** (StepBar for all modes; step-shaped composer). | Loses the per-question 3–5 generated steps that exist today (Guided). Keep them as sub-steps under Design/Deep dive, or accept the loss. The model must be allowed to go back a step; the bar must not imply "done" because the model moved on. |

## Tensions to decide

1. **Positioning vs teaching.** Brilliant and ByteByteGo teach; our line is "we put you in the interview", which rules out lesson decks, flashcards and daily multiple choice. So: do tiny steps live **inside** the interview (each framework step is a small, checked move the interviewer asks for, pattern 1's cut) or in a **separate warm-up**? Inside keeps the positioning and reuses the turn model; separate is cleaner to build but is a quiz. Consequence for Recall: the authored 15-card catalog (Swift/SQL/TLS…) is a flashcard deck and should go; evidence-minted personal cards can stay as "things you said you'd fix".
2. **AGENTS.md: system fonts, semantic colours, system controls.** A lane canvas, a component palette and the Libron typeface (vendored at docs/design/fonts/libron) all break that rule. Proposed wording: *"Native UI uses system controls and semantic colours. The interview workspace (framework bar, lane canvas, palette, system scenes) is a custom surface and may use the Libron display face for titles and the diagram's own geometry; body text, forms, sheets and settings stay system. Custom spacing uses 4-point increments; custom surfaces use a 12-point radius; one accent colour."* The user decides.
3. **Phone ergonomics.** Building diagrams with a thumb on a 6-inch screen: slots, not drag; palette as a bottom strip above the keyboard; edges by tapping two nodes; rename by long-press; no zoom. Landscape is not a plan.
4. **Bit's role.** Proposal: opening (Welcome example, as the speaker) and arriving feedback (one hop on Reflection). Off Setup, Home, preview, interview, voice. App icon stays.
5. **Free reps and the paywall in the new first run.** Three options: (a) gate after the first rep's feedback, before the second rep (current); (b) gate after two reps so the "what to fix" can be acted on once; (c) a 5-minute voice taste inside the first rep as the hook, then gate. The free-rep ticket needs a CTA either way ("See plans").
6. **Voice and the diagram.** Diagram and step updates arrive with **finalized turns**, not word by word. Today voice turns are `kind: "voice"` rows that never produce an interviewer `follow_up`, so no `step`, no critique. Making voice ride the turn model (`receiveFinalizedAnswer` exists, unused) is the contract change; until then, voice shows the canvas read-only and updates it on End.

## Recommendation

| Pattern | Cut | First prototype round? |
|---|---|---|
| 1 Tiny steps | Generated per-step moves inside the interview, checked locally, sent as answers | yes (round 2) |
| 2 Manipulable diagram | One authored scene per family, 2–3 toggles, lookup table; used as the interviewer's probe after the learner's design | yes (round 3), one family (job queue) |
| 3 Canvas | Lanes + slots + tap-to-place + tap-two-to-connect; JSON with the answer | yes (round 2) |
| 4 Critique | Per-step rubric in Reflection with quotes, no ratings; `curveball` in DTO; restore `wrap_up` | yes (round 4) |
| 5 Framework | Fixed 5-step path for all modes, interviewer-driven `step`, step-shaped composer | yes (round 2) — this is the spine |

Decision on tensions if the user doesn't answer: 1 inside; 2 adopt the proposed wording; 3 slots not drag; 4 opening + feedback only; 5 (a) current gate plus a CTA, voice taste deferred; 6 read-only canvas in voice, finalized-turn boundary tagged as API work.
