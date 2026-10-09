# Drillbit design steal list

Research snapshot: 2026-10-04

## Scope and evidence rules

- Public web evidence only: product marketing pages, public course pages, App Store listing, public product/docs pages, and Excalidraw's public repository.
- **Observed** means the fetched page itself exposed the described text, hierarchy, image alt description, or control. A written description of a diagram is evidence of an illustration, not evidence that the diagram is manipulable.
- **Inferred** means a design reading or a hypothesis from the visible evidence. Each inference names its basis and is not represented as verified behavior.
- **Needs user screenshots** marks a product surface that could not be inspected without an account, or that the available public fetch did not expose. No account-gated behavior is guessed.
- The user's design objective is an interview practice app: “Other apps teach system design. We put you in the interview.” That positioning is treated as a product constraint supplied in the request, not as a claim about competitor marketing.
- Price and availability are region- and promotion-sensitive. Prices below are copied only where a fetched public page displayed them; missing prices are not estimated.

## ByteByteGo

### Screens and moments

1. **Observed — course outline and completion state.** The System Design Interview page presents a numbered, linked chapter list and a visible `0/31 completed` state, with individual rows marked “Not started.” The user scans the path and chooses the next chapter. The list is dense but scannable; progress is explicit rather than hidden in a profile. This is a public outline, not evidence that a learning action is saved without signing in. [Course outline](https://bytebytego.com/courses/system-design-interview)

2. **Observed — architecture grows in successive diagrams.** “Scale From Zero To Millions Of Users” starts with a single-server setup and then introduces separate web/data tiers, a load balancer, replicas, cache, CDN, stateless tier, data centers, queues, and sharding. The user reads a short explanation and compares each numbered diagram with the prior system. The feeling is cumulative: complexity is added in chunks, with a fairly high information density. These are static illustrations in the fetched page, not toggles or a live simulation. [Scale From Zero To Millions Of Users](https://bytebytego.com/courses/system-design-interview/scale-from-zero-to-millions-of-users)

3. **Observed — one request path is unpacked as numbered actions.** The same chapter explains the cache hit/miss sequence and pairs that explanation with a diagram. The user traces a request from web server to cache, then to the database on a miss, and back. The visual numbering reduces the effort of decoding a busy architecture drawing. It remains a read-and-follow moment; changing traffic or disabling a component is not shown. [Cache tier chapter](https://bytebytego.com/courses/system-design-interview/scale-from-zero-to-millions-of-users)

4. **Observed — mock dialogue precedes a reference architecture.** “Design A Rate Limiter” opens with candidate/interviewer clarification, summarizes requirements, then moves through a high-level design and deep dives. Later diagrams depict allowed requests, a rejected request with 429, token-bucket states, middleware, Redis, and distributed concerns. The user can move from interview conversation to algorithm comparison to architecture. The tone is explanatory and comprehensive, more reference chapter than timed interview. [Design A Rate Limiter](https://bytebytego.com/courses/system-design-interview/design-a-rate-limiter)

5. **Observed — framework taught as a four-step course chapter.** The chapter's own structure is: understand the problem and establish scope; propose high-level design and get buy-in; design deep dive; wrap up. It includes sample candidate/interviewer dialogue, diagrams, and rough time allocations. The page encourages asking questions and collaborating rather than racing to a solution. [A Framework For System Design Interviews](https://bytebytego.com/courses/system-design-interview/a-framework-for-system-design-interviews)

### What Drillbit should steal

- **Steal:** show a tiny path and a persistent completion state. Make the next interview move legible without turning the product into a broad video/course catalog.
- **Steal:** introduce architecture as a sequence of deltas. Keep a stable baseline, then make each interviewer follow-up visibly alter one thing: cache added, node lost, traffic doubled.
- **Steal:** number the request flow and connect each visual change to a concrete sentence the candidate could say aloud.
- **Steal:** make sample interviewer dialogue teach pacing and clarification, but keep the real practice turn-taking authentic and candidate-led.
- **Leave:** long reference-chapter density, exhaustive technology catalogs, and “read the answer” as the main interaction. Those optimize learning the material, while Drillbit's supplied position is practicing the interview.
- **Leave:** prebuilt final architectures as the default canvas state. A completed diagram gives away the answer; start blank or with only the prompt's stated constraints.
- **Leave:** lengthy prose and tiny diagram labels on a phone. Translate the sequential explanation into short spoken prompts, a focused canvas, and optional detail sheets.

### Pricing and gate

- **Observed:** the public pricing page shows an “Unlock All” offer, lifetime and yearly options, and a displayed price pair of £379 / £759 in the fetched UK-region rendering. The page links to all-in-one interview-prep courses. [Pricing](https://bytebytego.com/pricing)
- **Observed:** the course landing page says preview chapters and curriculum are available before purchase, and that free content can be tried. This places the taste before the paid course gate. [Course landing page](https://bytebytego.com/)
- **Not verified:** the fetched content did not expose a complete current checkout breakdown or establish which exact chapters are free. Do not treat the promotion or regional price as globally stable.

## Exponent (now redirecting to Aced)

### Public evidence boundary

- **Observed:** the requested Exponent URLs redirect from `tryexponent.com` to Aced routes. The fetched Aced homepage, AI interview, course, and pricing routes returned HTTP 503; the public YouTube channel/search routes redirected to consent or returned 401. [Exponent home](https://www.tryexponent.com/) · [AI interview route](https://www.tryexponent.com/ai-interview) · [Pricing route](https://www.tryexponent.com/pricing)
- **Needs user screenshots:** no current product screen, course screen, interview whiteboard, scorecard, or paywall was returned by the public fetches. The product name and URL path are not evidence of the detailed UI or its behavior.
- The following three items are **not product claims**. They are the minimum screens needed to complete this audit, inferred only from the requested topics and route labels; each needs user screenshots or another fetchable official public source.

### Screens to verify

1. **Inferred — AI interview setup and first prompt. Needs user screenshots.** The route label `/ai-interview` exists, but the fetched destination failed. Unknown: whether the user chooses role, difficulty, question, voice/text, or session duration; unknown: density, tone, and whether the prompt arrives as chat or a simulated interviewer. [Redirected route](https://www.tryexponent.com/ai-interview)

2. **Inferred — system-design answer surface / whiteboard. Needs user screenshots.** No public evidence fetched confirms whether Exponent/Aced provides a canvas, component palette, freeform board, or a third-party whiteboard. The request identifies this as a research question; it is not verification. [Redirected home](https://www.tryexponent.com/)

3. **Inferred — feedback or rubric after a mock. Needs user screenshots.** No fetched page confirms pushback during an answer, transcript review, score dimensions, written critique, or a final report. Do not copy a presumed scorecard or AI-interviewer interaction until a screen is supplied. [Redirected AI interview route](https://www.tryexponent.com/ai-interview)

4. **Observed — public access failure, not a product moment.** Aced's pricing route returned 503, so the location of any gate, free taste, subscription terms, and current price could not be established. [Redirected pricing route](https://www.tryexponent.com/pricing)

### What Drillbit should steal / leave

- **Steal only after verification:** the potentially useful category is mock-interview practice, but no particular mechanic is substantiated by the fetched pages. Capture an account-free demo or user screenshots before making a product decision.
- **Leave for now:** any supposed Exponent screen, AI pushback pattern, score rubric, whiteboard library, or pricing claim. Filling the holes from memory would violate the source constraint and risk designing against an outdated Exponent product after its redirect to Aced.
- **Phone constraint:** if screenshots later show a desktop-oriented canvas, inspect the actual phone layout separately; don't assume its controls transfer ergonomically.

### Pricing and gate

- **Not publicly verified in this audit.** The official pricing URL redirected to Aced and the destination returned 503. No price, trial, free tier, or paywall placement is asserted. **Needs user screenshots** or a working public pricing page.

## Excalidraw

### Screens and moments

1. **Observed — blank canvas with compact tool row.** The public editor exposes a large drawing canvas, a “Shapes” tool area, canvas actions, zoom, help, live collaboration, and a Library entry. The user begins with an open surface rather than a prewritten answer. The UI is tool-forward and intentionally sparse; on a phone, the number of tools and the canvas-to-palette balance need a purpose-built adaptation. [Editor](https://excalidraw.com/)

2. **Observed — select a primitive, then place it.** The editor's tool strip includes numbered shortcuts `1` through `0`; the repository README lists rectangle, circle, diamond, arrow, line, free-draw, and eraser. A user can choose a shape tool and draw the corresponding primitive. This is a reusable creation vocabulary, not a curated system-design lesson. [Editor](https://excalidraw.com/) · [Repository README](https://github.com/excalidraw/excalidraw)

3. **Observed — architecture-specific library.** The public library index offers “Software Architecture,” “System Design Components,” “Architecture diagram components,” and “System Design Template” libraries. Library descriptions mention microservices, databases, caches, event buses, servers, APIs, and fill-in-the-blank design structures. The user can add a reusable shape set rather than redraw every symbol. The catalog is expansive; discovery is a separate task from interview reasoning. [Public libraries](https://libraries.excalidraw.com/)

4. **Observed — move the view without switching context.** The editor says to pan with the scroll wheel or Space while dragging, or use the hand tool; it also shows zoom percentage and canvas actions. This keeps the canvas spatially navigable. Those are desktop affordances; touch gesture behavior was not documented by the fetched sources. [Editor](https://excalidraw.com/)

5. **Observed — autosave and explicit export warning.** The editor says drawings are saved in browser storage and warns that browser storage can be cleared unexpectedly; it offers open/help and collaboration controls. The user gets a quick-return workspace, but is told to save a file regularly. The repository describes local-first autosave and export to PNG, SVG, clipboard, and `.excalidraw` JSON. [Editor](https://excalidraw.com/) · [Repository README](https://github.com/excalidraw/excalidraw)

### What Drillbit should steal

- **Steal:** a blank-first canvas, direct placement, a small set of high-frequency primitives, undo/redo, and stable zoom/pan. Let candidates author the answer rather than rearrange a pre-solved diagram.
- **Steal:** a compact, interview-specific palette with text, service, database, cache, queue, client, and connector. Excalidraw's public libraries show that reusable component vocabularies can be additive rather than forcing every user to sketch from scratch.
- **Steal:** attached arrows, labels, and predictable selection. The README explicitly lists arrow-binding and labeled arrows; this is the valuable mechanic for moving components without losing their relationships.
- **Steal:** preserve a structured scene and replay meaningful changes. The open format and `onChange` API offer a model for storing canvas state as structured data, not a flattened image.
- **Leave:** an unconstrained, infinite general-purpose editor as the whole interview UI. A blank canvas is useful, but a phone interview also needs prompt context, turn state, and a way to review what changed.
- **Leave:** a giant third-party icon library as the primary palette. A candidate should spend time reasoning about a cache or queue, not searching hundreds of branded logos.
- **Leave:** hand-drawn styling and web desktop shortcuts as assumed Drillbit styling/interaction. Drillbit's native system-font, semantic-color, SF Symbols, and system-control conventions take precedence; adapt the behavior, not the visual assets.

### Pricing and gate

- **Observed:** the open-source editor is described as free and MIT-licensed; the hosted editor is usable publicly and offers a sign-up link for Excalidraw+. [Repository README](https://github.com/excalidraw/excalidraw) · [Editor](https://excalidraw.com/)
- **Observed:** the public README distinguishes the editor/package from Excalidraw+ and describes the hosted app's offline support, collaboration, local-first storage, and shareable read-only links. [Repository README](https://github.com/excalidraw/excalidraw)
- **Not verified:** current Excalidraw+ pricing, exact plan limits, or whether any particular collaborative feature is gated. No price is stated here.

## Hello Interview

### Screens and moments

1. **Observed — Guided Practice is framed as choose, work, review.** The public overview shows three named stages: choose a common problem, work through it, receive personalized feedback. The user selects a question, narrates the answer step by step, then sees feedback tuned to each design step. The progression reads like a mock, not a chapter list; copy is direct and interview-focused. [Guided Practice overview](https://www.hellointerview.com/practice/overview)

2. **Observed — diagram-first practice is explicitly advertised.** The same page says “Whiteboard-first,” says the AI reads the drawing, and describes step-by-step prompts that mirror a real system-design loop and instant per-step rubric-based coaching. This is strong public evidence for the promised mechanic. It does not expose the live canvas tool palette or establish the exact latency of feedback. The working screen is account-gated. [Guided Practice overview](https://www.hellointerview.com/practice/overview)

3. **Observed — problem library is arranged by recognizable interview problem and difficulty.** The public system-design practice page lists named problems such as Bitly, Dropbox, Yelp, Ticketmaster, Instagram, WhatsApp, and Uber, with Easy/Medium/Hard labels and “Mark as read” / “Start History” affordances. The user can choose by familiarity and challenge rather than browse generic topics. The dense list favors quick scanning over a long editorial introduction. [System Design Guided Practice](https://www.hellointerview.com/practice/system-design)

4. **Observed — a worked problem connects steps to a final design.** The public Uber breakdown walks through functional/non-functional requirements, core entities, API, high-level design, and potential deep dives. It describes the system one functional requirement at a time and then shows “Bad,” “Good,” and “Great” solutions in deep dives. The user sees a reasoned progression and tradeoffs rather than only a final architecture. It is public instructional content, not evidence that the practice canvas itself mutates live. [Uber problem breakdown](https://www.hellointerview.com/learn/system-design/problem-breakdowns/uber)

5. **Observed — gated practice entry.** Opening the public Bitly Guided Practice route produced a “Sign in or sign up” form rather than a working session. The user can reach the named exercise from the overview, but the fetched page gates the actual activity at authentication. This is the decisive point where a public promise becomes an account requirement. [Bitly Guided Practice](https://www.hellointerview.com/practice/system-design/bitly)

### What Drillbit should steal

- **Steal:** a choose → answer → receive feedback loop with small, explicit milestones. Give one prompt at a time, let the candidate speak or write, then coach the answer they just gave.
- **Steal:** rubric-based feedback tied to the exact stage, not a generic “good job” score. Keep examples concrete: missing requirement, entity ambiguity, API mismatch, unaddressed scaling constraint.
- **Steal:** coach from the evolving diagram and keep the diagram in view. If the interviewer asks a follow-up, point to the affected node or arrow instead of opening an unrelated answer panel.
- **Steal:** expose difficulty and problem history in a compact library so candidates can resume deliberate practice.
- **Leave:** a website-shaped whiteboard session unchanged. The entry page promotes whiteboard-first use, but the real interaction requires sign-in; request user screenshots before copying layout or palette details.
- **Leave:** tutorial answers that lead with a polished solution. Drillbit's differentiator is the attempt and interviewer turn, so reveal reference material only after the candidate has committed an answer.
- **Leave:** long pages of deep-dive text inside the live interview. Keep the mock moving; place reference explanations after the turn or behind a deliberate “review” action.

### Pricing and gate

- **Observed:** the public overview lets users start free and advertises “Try 'Design Bitly' Free,” but the direct Bitly route fetched to an account sign-in form. This indicates a free taste followed by an account gate; it does not prove that the practice session itself is paid. [Overview](https://www.hellointerview.com/practice/overview) · [Bitly route](https://www.hellointerview.com/practice/system-design/bitly)
- **Observed:** public pricing lists month, year, and lifetime Premium access. The fetched page showed $47 monthly (discounted from $59), $79 yearly (discounted from $99), and $279 lifetime (discounted from $349); prices may be promotion-sensitive. The Premium package includes Guided Practice, courses, question library, and AI tutor. [Pricing](https://www.hellointerview.com/pricing)
- **Observed:** the paywall is presented on overview/pricing pages and the specific practice URL requires sign-in; the exact in-session premium limit or checkout interruption was not established.

## Brilliant

### Screens and moments

1. **Observed — lesson path is visibly chunked into levels.** The public “Thinking in Code” course displays nine levels, each with a short sequence of lessons and a Level Review. The user moves from Taking the First Steps through loops, branching, variables, lists, logic, and building programs. At 48 lessons and 618 exercises, the path has scale, while level boundaries make the immediate next step visible. [Thinking in Code](https://brilliant.org/courses/thinking-in-code/)

2. **Observed — an exercise sequence moves from example to reasoning.** The public “Algorithmic Thinking” outline groups lessons into four levels, including scheduling problems, alternative criteria, testing algorithms, counterexamples, and optimization, followed by Level Reviews. The user is led from instances to general rules and limitations. The tone is playful but task-centered; the listed outline alone does not show a one-second correctness response. [Algorithmic Thinking](https://brilliant.org/courses/algorithms-greedy-dp/)

3. **Observed — domain course connects short exercises to one system concept.** “Search Engines” is organized into Big Search, Effective Search, and Implementing Search, with 20 lessons and 101 exercises. The public description progresses from crawling and query logic to building an index and improving search. The course promise is to explore and construct, not just watch. Actual answer widgets and response timing were not visible in the fetched catalog page. [Search Engines](https://brilliant.org/courses/search-fundamentals/)

4. **Observed — tutor is described as guiding rather than supplying answers.** The homepage and App Store listing describe Koji as seeing a learner's screen, asking guiding questions, sketching, giving hints, and providing visual help. This supports a coached-at-the-point-of-stuckness pattern. It does not publicly substantiate the requested “right/wrong plus why in under a second” timing for each answer. [Brilliant homepage](https://brilliant.org/) · [App Store listing](https://apps.apple.com/app/brilliant-learn-interactively/id913335252)

5. **Observed — progress adapts to what the learner has mastered or missed.** The homepage describes progress tracking, personalized plans, mastery assessments, and targeted practice after a learner comes up short. It also advertises real-time progress dashboards. The user gets a route back to a gap, not merely a completion badge. These are public product claims; exact dashboard screen layout was not available in the fetched content. [Brilliant homepage](https://brilliant.org/)

### What Drillbit should steal

- **Steal:** tiny interview moves, not tiny quizzes for their own sake. Ask one scoped question, accept a short answer, and respond immediately with a specific why or follow-up.
- **Steal:** short step names and review checkpoints. A visible track can reassure a candidate that requirements, entities, APIs, high-level design, and deep dives are part of one bounded attempt.
- **Steal:** diagnose a gap and tailor the next prompt. For example, if the candidate skips read/write load, ask about traffic shape before suggesting a database.
- **Steal:** visual explanation when a verbal explanation is not enough. Let the interviewer point to a part of the candidate's own diagram or sketch a small counterexample.
- **Leave:** gamified course-path framing as the default interview. Streaks, broad subject exploration, and long lesson maps risk shifting the product toward “learn system design” rather than “perform an interview.”
- **Leave:** binary right/wrong grading for an inherently open-ended design. A design answer has tradeoffs; judge completeness, reasoning, communication, and response to constraints rather than whether it matches one canonical architecture.
- **Leave:** any oversized companion/mascot presence or school-age tone in the interview room. Borrow the patience and adaptive coaching, not Brilliant's audience framing or assets.

### Pricing and gate

- **Observed:** the course catalog is publicly viewable, while its sign-in and sign-up links are visible. The subscribe page says Premium unlocks unlimited access to 40+ courses and gives monthly, annual, and family plans. In the fetched UK rendering it showed £20/month, £12.50/month billed annually, and £25/month for six family seats. [Course catalog](https://brilliant.org/courses/) · [Subscribe](https://brilliant.org/subscribe/)
- **Observed:** the premium gate is positioned at broad course access, not in the public course outline. The fetched page describes Premium as required for unlimited course access; the exact free exercise limit and in-lesson interruption were not verified.
- **Not verified:** the specific step-by-step correctness UI, feedback animation, and sub-second latency. The public App Store/homepage copy supports interactive tutoring and feedback, not a precise response-time claim.

## Patterns × references

| Pattern | Reference example | Source status |
|---|---|---|
| Tiny steps with instant feedback | Hello Interview Guided Practice: named stepwise work and instant per-step rubric coaching | Observed marketing claim; live session needs user screenshots |
| Tiny steps with instant feedback | Brilliant: 20 lessons / 101 exercises and Level Reviews in Search Engines | Observed course outline; exact right/wrong timing not verified |
| Manipulable diagrams | Excalidraw: canvas, shape tools, arrows, and libraries | Observed public editor/repo capability; Drillbit's live simulation is a proposal |
| Manipulable diagrams | ByteByteGo: cache hit/miss, replicas, and rate-limit diagrams | Observed static illustrations only; not a live manipulator |
| Canvas + component palette | Excalidraw: tool strip plus public System Design Components and Software Architecture libraries | Observed editor and public libraries |
| Canvas + component palette | Hello Interview: public claim that practice is whiteboard-first and AI reads the drawing | Observed product claim; palette and actual controls need user screenshots |
| AI critique like a mock | Hello Interview: step-specific personalized feedback and rubric-based coaching | Observed marketing claim; account-gated practice screen needs screenshots |
| AI critique like a mock | Exponent/Aced: the requested AI interviewer route redirects, destination returns 503 | Not verified; needs a working public demo or user screenshots |
| Visible framework and progress | Hello Interview: exact Delivery Framework stages and timings | Observed public guide |
| Visible framework and progress | ByteByteGo: `0/31 completed` course outline and numbered course framework | Observed public course page |
| Visible framework and progress | Brilliant: levels, lessons, exercise counts, and Level Reviews | Observed public course outlines |

## Hello Interview delivery framework (verified)

Published on [Hello Interview's Delivery Framework](https://www.hellointerview.com/learn/system-design/in-a-hurry/delivery). The page gives these top-level sections in this order:

1. **Requirements (~5 minutes)**
   - Functional Requirements
   - Non-functional Requirements
   - Capacity Estimation
2. **Core Entities (~2 minutes)**
3. **API or System Interface (~5 minutes)**
4. **[Optional] Data Flow (~5 minutes)**
5. **High Level Design (~10–15 minutes)**
6. **Deep Dives (~10 minutes)**

The shorthand “requirements → core entities → API → high-level design → deep dives” is directionally correct, but it omits the three-part Requirements section, the optional Data Flow stage, and the published approximate timings. “API or System Interface” is the site's exact title; it is not simply “API.”

The same page says to use a simple complete high-level design before layering complexity in deep dives, and to update the design as constraints or bottlenecks surface. Its page navigation/next link progresses from Delivery Framework to Core Concepts; the framework itself is a public article, while the progress-login control says “Login to track your progress.”

## Excalidraw mechanics worth copying

### Palette and toolbar

- The public editor starts on a canvas and exposes a “Shapes” tool area, a Library entry, canvas actions, zoom, Help, and live-collaboration controls. [Editor](https://excalidraw.com/)
- The fetched editor text exposes keyboard labels `1`–`0` alongside the shape tools. The repository README identifies rectangle, circle, diamond, arrow, line, free-draw, and eraser among the tools. [Repository README](https://github.com/excalidraw/excalidraw)
- The React API allows hosts to customize canvas actions and hide the image tool; the docs show configuration for background color, clear, load, save, export, and theme actions. This is evidence that the editor surface can be reduced for a focused task. [UIOptions docs](https://docs.excalidraw.com/docs/%40excalidraw/excalidraw/api/props/ui-options)
- The `initialData` API accepts elements, app state, library items, and files. This supports a host app supplying a constrained starter canvas or a focused library without requiring an account. [initialData docs](https://docs.excalidraw.com/docs/%40excalidraw/excalidraw/api/props/initialdata)

### Arrows and shape binding

- The repository README explicitly lists “Arrow-binding & labeled arrows” as editor capabilities. It also lists undo/redo, zoom, and panning. [Repository README](https://github.com/excalidraw/excalidraw)
- The source-file URLs for element types and arrow binding could not be retrieved by the public page fetcher in this pass. Therefore this audit verifies the supported user-facing capability, but does **not** claim exact internal property names, endpoint modes, or mutation behavior.
- For Drillbit, the mechanic to prototype is semantic attachment: connect two existing nodes, keep the connector attached when either node moves, and allow an optional label. The suggested phone flow is tap a connector tool, tap a source node, then tap a destination node; this is a Drillbit interaction proposal, not an Excalidraw behavior claim.
- Keep the connector's direction and label distinct. A candidate should be able to show request direction or asynchronous/event flow without having to draw a perfect arrowhead by hand.

### Libraries of shapes

- The public library directory is an installable catalog with Add to Excalidraw and Download actions. It includes “Software Architecture,” “System Design Components,” “Architecture diagram components,” “System Design Template,” and many cloud/vendor icon sets. [Public libraries](https://libraries.excalidraw.com/)
- The “Software Architecture” library description lists microservices, databases, cache, event bus/pipeline, documents/code, browser, and mobile device. “System Design Components” is described as useful for interview high-level diagrams. [Public libraries](https://libraries.excalidraw.com/)
- The repository README confirms shape-library support. The `initialData` docs confirm a `libraryItems` input, and the API docs describe an `onLibraryChange` callback. [Repository README](https://github.com/excalidraw/excalidraw) · [initialData docs](https://docs.excalidraw.com/docs/%40excalidraw/excalidraw/api/props/initialdata) · [Props docs](https://docs.excalidraw.com/docs/%40excalidraw/excalidraw/api/props)
- Drillbit should curate a short native palette with generic, neutral components. Excalidraw demonstrates the reusable-vocabulary mechanic; its huge community catalog is not a phone-ready default.

### Keyboard, touch, and canvas movement

- The public editor says to pan with the scroll wheel or Space while dragging, or use the hand tool. It exposes zoom percentage and includes a hand tool as a no-keyboard path. [Editor](https://excalidraw.com/)
- The fetched sources substantiate desktop keyboard/mouse affordances only. **Touch gestures, one-handed reach, and phone-specific tool behavior are not verified here.** Do not assume pinch, drag, or double-tap details from the desktop page.
- For Drillbit, keep tap targets large, make drawing optional when voice is active, and reserve gestures for direct manipulation rather than hidden modes. Treat these as native design requirements, not claims about Excalidraw.

### Serialization and scene shape

- The repository describes `.excalidraw` as an open JSON export format and lists PNG/SVG/clipboard export. The hosted app also says it saves drawings in browser storage, warns about clearing that storage, and offers explicit file saving. [Repository README](https://github.com/excalidraw/excalidraw) · [Editor](https://excalidraw.com/)
- At a high level, the documented scene is an `elements` array plus `appState`; initial data may also include `libraryItems` and `files`. The API's `onChange` callback receives elements, app state, and files. [initialData docs](https://docs.excalidraw.com/docs/%40excalidraw/excalidraw/api/props/initialdata) · [Props docs](https://docs.excalidraw.com/docs/%40excalidraw/excalidraw/api/props)
- The docs' sample rectangle element shows a `type`, `id`, `x`, `y`, `width`, `height`, `angle`, stroke/background colors, fill/stroke styles, roughness, opacity, version metadata, and group IDs. This is a representative shape, not a complete serialization schema. [initialData docs](https://docs.excalidraw.com/docs/%40excalidraw/excalidraw/api/props/initialdata)
- The repo README separately lists the supported primitive categories. Exact complete JSON shapes for every element type were not verified because the linked source files did not load through the allowed fetch tool.
- For Drillbit, persist semantic board state rather than a screenshot: stable node IDs, node kind, position/size, text, connector endpoints, labels, and versioned edits. Store the interview transcript/turn reference separately and link relevant feedback to stable board element IDs.
- Keep the serialization contract small and versioned. Preserve enough scene history to replay candidate changes and compare before/after deep dives; do not couple interview state to Excalidraw's internal JSON unless the app actually embeds that library.

## Research gaps to close before visual copying

- **Exponent/Aced:** current AI interview, system-design canvas, rubric/report, and pricing screens were not publicly retrievable (official routes redirected and Aced returned 503). Needs user screenshots or a working official public demo.
- **Hello Interview:** overview and written examples are public, but the actual practice canvas, palette, voice controls, live pushback timing, and final scorecard layout are behind sign-in. Needs user screenshots for those visual details.
- **Brilliant:** public outlines and product claims establish progression and guided tutoring, but exact exercise input controls, correctness animation, and sub-second feedback latency were not exposed. Do not state a speed claim without a demo capture.
- **Excalidraw:** public editor and API docs establish tools, libraries, binding as a feature, and scene persistence. The attempted fetch of source files did not resolve, so low-level arrow binding fields and complete per-type JSON unions remain unverified.
- Across all five: the “double traffic / kill a node / watch the architecture respond” simulation is a Drillbit opportunity. None of the fetched public sources proves that a competitor offers this exact live manipulation mechanic.

## Translation notes for Drillbit

These are implementation directions inferred from the evidence above, not claims about competitor functionality.

### 1. Tiny steps and instant feedback

- Keep one active prompt visible at a time. A candidate should know what they are answering without scrolling through the whole framework.
- Accept a short spoken or typed response; do not demand a fully formed essay before feedback becomes possible.
- Return one concrete signal tied to the response: what was covered, what is missing, and why that matters to the design.
- Use an interviewer follow-up when the answer opens a meaningful branch. Use a concise explanation when the error is local and teachable.
- Treat “under a second” as a desired feedback feel, not a verified competitor benchmark or hard AI-service latency guarantee.
- For a slow model response, preserve the candidate's place and make the wait state feel like the interviewer is considering the answer, not like the session was lost.
- Do not mark a complex open-ended answer simply right or wrong. Separate correctness of facts from completeness of reasoning and fit to the stated constraints.
- A stage can advance when the answer is sufficient, while still allowing the interviewer to ask a probe or the candidate to revise it.
- Keep an explicit “continue” affordance when there is no single required answer. This avoids trapping a candidate in an ambiguous automatic grading rule.
- Let the final review replay the short steps, so the candidate sees exactly which answer led to each coaching note.

### 2. Manipulable diagrams and system response

- Start with a deliberately small system. Add or remove a cache, replica, queue, or node only when the prompt or candidate's design calls for it.
- Represent a change as an event with a cause: “traffic doubled,” “cache unavailable,” or “one database replica is unhealthy.”
- Animate only the affected request path. A complete network-wide animation would add noise and obscure the causal claim.
- Show before/after state in place. Preserve node positions and labels so the candidate can compare, rather than rebuilding the diagram after every prompt.
- For traffic changes, make the metric visible alongside the flow: requests per second, queue depth, latency, or failed requests.
- For a node failure, distinguish unavailable, degraded, and recovered states; color alone should not carry the meaning.
- Ask the candidate to predict the impact before showing the response. That keeps the tool in interview mode rather than turning it into a passive explainer.
- After the prediction, reveal a short event trace and invite a revised design. Make the candidate's changes visible as edits, not as a replacement canonical answer.
- Keep simulation controls outside the primary drawing surface so taps intended to select a node do not accidentally alter the scenario.
- None of the inspected competitor pages verifies this exact simulation. Treat this as a product opportunity to test, not as a pattern already validated by a reference app.

### 3. Canvas and component palette

- Keep the first palette to common generic nouns: client, API/service, database, cache, queue, worker, external dependency, and connector.
- Put text/label and connector actions within easy thumb reach; expose less frequent shapes in a secondary drawer.
- Make a tap on a palette item enter a predictable placement mode, then return to selection after placement unless the candidate intentionally pins the tool.
- For phone ergonomics, prefer tap-to-place and tap-two-nodes-to-connect over tiny drag handles. This is a Drillbit proposal; Excalidraw's fetched public page only confirms desktop controls.
- Provide a short visible connector preview between the source and destination before committing, so the candidate can correct a mistaken endpoint.
- When moving a node, preserve attached connectors and avoid changing the topology accidentally.
- Support concise labels without requiring text editing in a small modal. Keep keyboard focus and canvas state stable when the system keyboard appears.
- Offer undo and redo as native, discoverable actions. Do not require the user to memorize Excalidraw's web shortcuts.
- Make a diagram selectable and inspectable by VoiceOver; expose component type, label, and connected nodes as accessible names.
- Keep blank-first as the default. Offer a minimal starter only if the prompt explicitly includes an initial architecture.

### 4. AI critique as an interviewer

- During the answer, intervene only when a real interviewer would reasonably probe: ambiguity, a contradiction, an unstated assumption, or a missed requirement.
- Use short pushback in the candidate's current mode. In voice, one spoken question; in text, one concise message. Avoid stacking several coaching questions at once.
- Do not narrate every diagram edit. React to the consequence of the design, not the mere act of drawing.
- Separate live interviewer behavior from post-session coaching. The mock should stay conversational; the report can be more structured and specific.
- Organize the final report by the published interview stages and evaluate the reasoning demonstrated in this attempt, not how similar the architecture is to a reference answer.
- For each coaching point, include evidence from the candidate's own words or diagram and one concrete revision they could make.
- Distinguish “not asked,” “not answered,” and “answered but unsupported.” Those represent different interview signals.
- Include a small number of prioritized improvements. An exhaustive checklist is likely to be less usable than the next two high-leverage changes.
- Allow the candidate to challenge or correct a critique when the transcript or diagram was misunderstood.
- Hello Interview publicly advertises step feedback and rubric-based coaching; no inspected public page proves Exponent's exact rubric or live pushback behavior.

### 5. Visible framework and progress

- Keep the current stage and next stage visible during the mock, but let the interviewer bend the sequence when the candidate's reasoning calls for it.
- Use the verified Hello Interview sequence as a reference, not a rigid script: requirements, core entities, API/system interface, optional data flow, high-level design, deep dives.
- Let the candidate see which part is complete, still open, or intentionally skipped. Do not imply a stage is complete solely because the timer expired.
- Use time guidance as a quiet pacing signal. The public framework's approximate durations are a reference, not a universal countdown for every prompt or seniority level.
- Connect each step to the actual transcript and board state. “Core entities: done” should link to the entities the candidate named, not a generic completion tick.
- Show overall progress without importing course streaks or a gamified map into the interview room.
- In review mode, present the stage path as a compact timeline with jump-back points for transcript and diagram changes.
- Preserve optionality: data flow is optional in Hello Interview's published framework, and candidate answers may naturally combine or revisit stages.
- Use a stable label for each framework stage across onboarding, practice, session, and report. Changing names between surfaces makes progress feel arbitrary.
- Make the visible path reassure the candidate about scope: one complete design first, then selected deep dives, not an endless syllabus.

### Cross-pattern guardrails

- Optimize for an uninterrupted answer before optimizing for decorative animation or dense course metadata.
- Never make the reference diagram the visual default when the task is to design one. Keep examples behind a deliberate reveal after the candidate has tried.
- Keep source-derived claims and Drillbit hypotheses separate in product decisions; the audit labels are intended to survive into prototype review.
- Check the interaction in both voice and text modes. A control that works while typing may interrupt speaking, and a voice-only control may be inaccessible to a silent practice session.
- Keep the board, prompt, and current interviewer turn in a coherent relationship. The candidate should not have to remember which screen the AI is discussing.
- Prefer a handful of generic, understandable shapes over brand logos. The design signal is the candidate's system reasoning, not their icon-search speed.
- Make diagram edits reversible and preserve the attempt. The user should be able to explore a failure scenario without losing their original solution.
- Treat any automatically generated diagram interpretation as fallible; make it easy to correct a misread node or connector before critique is delivered.
- Measure practice quality by whether a candidate can explain, revise, and defend a design under new constraints, not by how many shapes they placed.
- The steal list is a pattern inventory, not permission to reproduce another product's artwork, wording, or branded component designs.