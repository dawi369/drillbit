# Drillbit: app teardown → steal list → one HTML prototype

You are redesigning the flows and look of the Drillbit iOS app. This is a long task spread over several sessions. Most of the time goes into ONE HTML prototype page, where you and the user get the flows and the look right before any Swift changes. Work in four phases. Each phase ends at a checkpoint with the user.

## Context
- Drillbit is a native SwiftUI iOS app (apps/ios/Drillbit) with a Cloudflare Worker API (apps/api) and contracts in packages/contracts. It's system design interview practice with an AI interviewer, in text and live voice.
- Read first: AGENTS.md; docs/product-vision.md (short, read all of it); docs/architecture.md ("Interview room", "Bit, the mascot", "Taste pass"); docs/design/app-audit/notes.md.
- Positioning (already decided): "Other apps teach system design. We put you in the interview."
- History: nine HTML redesign studies were built and scrapped on 3–4 Oct 2026. The user's feedback on them is your best input.
  - Liked: light mode as the default. Animated system diagrams (a request travels, a node fails, a fix gets pinned on). Small, centred onboarding with very little text.
  - Rejected: white cards, gradient washes, coloured left-border stripes, glowing orbs, bento grids, tiny mono caps labels on every screen, text-heavy screens, stacks of identical rows, the Write it / Talk it through switch, and the mascot (Bit) everywhere ("less Bit, more serious"). Also rejected: a pre-drawn diagram that gives away the answer, and mocks that ignored how the app actually works.
  - Target: serious and focused, one job per screen, visibly different from a chat app.

## Inspiration: five products, five patterns
Products: ByteByteGo, Exponent, Excalidraw, Hello Interview, Brilliant. Patterns to steal:
1. Tiny steps with instant feedback (Brilliant). Each small step is answered in under a second.
2. Manipulable diagrams. The learner toggles a cache, kills a node or doubles the traffic, and watches the system respond.
3. A canvas with a component palette (Excalidraw; check how Hello Interview and Exponent handle drawing). The learner builds the architecture.
4. AI critique like a mock interview (Exponent, Hello Interview). Pushback during the answer, structured feedback after.
5. A visible path through a framework, with visible progress. Hello Interview's delivery framework is the obvious reference (roughly: requirements → core entities → API → high-level design → deep dives). Verify the exact steps.

## Phase 1: App teardown, screen by screen
Goal: notes detailed enough that someone could rebuild every screen from them.

How to see the screens:
- Build and launch: `sh scripts/check-ios-launch.sh <udid>` builds a signed debug build and launches dawi.drillbit. Unsigned builds can't be screenshotted. The user's simulator is "iPhone 17", UDID 32C4E22D-369B-4538-9816-96C7FF7FDCAE.
- Choose a state with launch arguments: `xcrun simctl launch <udid> dawi.drillbit --fixtures <flags…>`. `--fixtures` turns on seeded fixture data. Every other flag is a `--fixture-…` check; grep for `--fixture` in apps/ios/Drillbit to get the full list (onboarding, walkthrough, signed-out, coach, dashboard, home-rich, interview-history, voice, voice-connecting, voice-unavailable, recall, settings, gate, free-reps, long-question, generation-failure, slow-…). `--dark` gives dark appearance.
- Take a screenshot with `xcrun simctl io <udid> screenshot <file>.png`, then look at it.
- For states no flag reaches, write an XCUITest in apps/ios/UITests that attaches screenshots, or reconstruct the screen from code and say that you did.
- The code is your second source for every screen. Read each view and the model behind it.

Record for every screen:
- Name, Swift view(s) and file; how you get there; where it leads.
- Its one job, or the jobs it is juggling.
- Layout from top to bottom; every component, and whether it is a system or custom control.
- All copy, verbatim.
- States: empty, loading, streaming, error, offline, locked, first run vs returning.
- Interactions, gestures, motion, haptics.
- Accessibility: Dynamic Type, VoiceOver labels, reduced motion.
- Bit: present or not, what size, and why.
- The data it depends on (API endpoint, contract type, local persistence).
- Verdict: what works, what's weak, and which of the five patterns could land here.

Map these flows end to end: first run (Welcome → sign-in → setup → first rep → paywall gate), a daily rep in text, a rep in voice, finish → reflection/feedback, Recall, Library/Memory, Settings, paywall.

The interview turn model is load-bearing. Write it down exactly as it is implemented (read InterviewView, InterviewController, LiveVoice, InterviewVoiceRoom and the API side):
- The draft autosaves. Send creates a durable `answer` command. The interviewer replies with `follow_up` or `wrap_up`.
- A line ending in "?" is sent as a clarification, not an answer.
- Help: Nudge, Example, Guided choices, and GuidedPathBar / challenge.path.
- Session style can change mid-interview. Mock interviews show a clock. Finish leads to ReflectionView.
- Voice has its own phases; `blocksText` locks text while voice is live; transcript rows appear in the document when you return.
Every later design either rides this model or names the contract change it needs.

Output: docs/design/app-audit/notes.md, with screenshots in docs/design/app-audit/shots/.
Done when: every screen a user can reach has a section (internal views are listed with a reason), every flow has a map, every screenshot is referenced, and the turn-model section has been checked against the code.
CHECKPOINT: summarise the ten biggest problems and the assets worth keeping. Ask the user whatever you need to know.

## Phase 2: Steal list
For each of the five products: the concrete screens and moments that embody the patterns, how they feel, what Drillbit should steal and what it should leave. Use public sources: marketing sites, App Store screenshots and descriptions, docs, public demo videos, and Excalidraw's open-source repo. When a product needs an account, ask the user for screenshots rather than guessing. Mark every claim as observed (with a link) or inferred. Steal patterns, never assets or copy.
Done when: each product has at least 3 sourced patterns, and each of the five patterns has at least 2 reference examples.

## Phase 3: The cheap cut (discuss before building)
For each pattern, make a table with four columns:
- the full version;
- the cheap cut that still gets the value across;
- what the cheap cut needs (view-only work, content authoring, an API contract change, a model/prompt change, or a new native capability);
- the risk.

Seed ideas to evaluate (not conclusions):
- Manipulable diagram: one pre-authored diagram per question family, with 2–3 toggles and precomputed outcomes from a lookup table. No simulator.
- Canvas: fixed lanes or slots with tap-to-place from a palette, auto-layout, and tap two nodes to connect them. Compare with a freeform drag canvas, and with a PencilKit sketch read by a vision model.
- Instant feedback: deterministic checks (pick the failure point, order the steps, choose the component that fixes it), authored or generated and then validated, with no LLM wait. Use LLM grading only where free text matters.
- Framework path: a static step list per question, with the current step driven by the interviewer's phase. Start from what GuidedPathBar and challenge.path already do.
- Critique: reuse the interview turns and the reflection screen, add a rubric per framework step, and give the model the diagram as structured JSON rather than an image.
- Voice + diagram: diagram updates arrive with finalized turns, not word by word.

Raise these tensions explicitly:
- Positioning vs teaching. Brilliant and ByteByteGo teach; our positioning says we don't, and it rules out lesson decks, flashcards and daily multiple choice. Do tiny steps live inside the interview (each framework step is a small step with feedback) or in a separate warm-up?
- AGENTS.md mandates system fonts, semantic colours and system controls. A canvas, a custom palette and the Libron typeface (vendored at docs/design/fonts/libron, chosen earlier by the user) would need that rule changed. Propose wording; the user decides.
- Phone ergonomics: building diagrams with a thumb on a 6-inch screen.
- Bit's role: opening and arriving feedback only?
- Where free reps and the paywall sit in the new first run.

CHECKPOINT: present the table and the tensions, recommend a cut for each, and ask the user to choose. Phase 4 starts only after they decide.

## Phase 4: The HTML prototype (most of the time)
- One page: docs/design/prototype.html, with local CSS/JS files beside it if needed. Serve it with `cd docs/design && python3 -m http.server 8765`.
- Phone frames at 390×844, clickable flows, real copy, real states (loading, error, empty, offline), light by default with a dark toggle.
- Priority order:
  1. First run → first rep.
  2. A rep in text, with the framework path, canvas/palette and instant feedback.
  3. The manipulable-diagram moment.
  4. Feedback and critique.
  5. Voice.
  6. Home.
  7. Recall and Library.
- Label every screen with the Swift view it would replace, and tag anything that needs an API or contract change.
- Iterate in short loops: change it, screenshot it, show the user, adjust. Expect many rounds; this phase is where the work is.
- Write Swift only after the user signs off on a flow.
- Record any decision taken while the user was unavailable in a "Decisions" section at the bottom of the page.
Done for each round when: every screen in the round is screenshot-verified in the browser, nothing overflows the phone frame, reduced motion is handled, and the round's open questions are listed.

## Working rules
- One job per screen, and fewer words. Diagrams and interactions carry the meaning; text only names what the user just saw.
- Spacing on a 4-point grid, a 12-point radius on custom surfaces, one accent colour, unless the user changes AGENTS.md.
- Check every new string against the first Welcome screen in apps/ios/Drillbit/WelcomeView.swift (casual, direct, a fellow CS student).
- If the user doesn't answer at a checkpoint, take your recommended option, note it under Decisions, and keep going.
- Report what is verified (in the browser, in the simulator, on a device) separately from what is only proposed.

## Tooling gotchas
- The browser tool can't open file:// URLs; use the local server. Cache-bust with ?v=. If a page still shows old code, load about:blank, then the page, then reload.
- The browser tab counts as hidden, so requestAnimationFrame doesn't paint in screenshots. Use CSS animations or timers for anything you need to capture. When an overlay intercepts clicks, click with page.evaluate(() => el.click()).
- Simulator.app can't be opened from the remote shell; use simctl. In zsh, pass launch flags as separate words: a single $args string arrives as one argument.
- `xcodebuild test` can hang after the last test when given a long -only-testing list; run at most 4 tests per invocation. UI-test fixtures disable coachmarks unless you pass --fixture-coach.
