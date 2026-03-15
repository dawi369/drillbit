A minimal, widget-first app called drillbit — designed for software engineers preparing for SWE interviews, with a strong emphasis on system design, architecture, distributed systems, scalability, trade-offs, fault tolerance, and other high-level conceptual topics that are best reasoned about and discussed in English rather than pure code (e.g., "How would you design a live collaboration document editor like Google Docs? Walk through consistency models, conflict resolution strategies, offline support, partitioning, latency vs durability trade-offs…"). Algorithmic/LeetCode-style questions are fully supported if the user specifies them in their focus prompt, but the app's default DNA favors verbal, discussion-heavy problems that mirror real senior/staff-level interviews.

Customizable home-screen widget lets users choose their preferred interaction mode at a glance:

- Solo: Clean problem statement + space for personal notes/thinking (no AI interference).
- AI Coach: Gentle, Socratic guidance — the AI probes with thoughtful questions ("What consistency guarantee would you prioritize here, and why?"), provides step-by-step directional hints, highlights key trade-offs, encourages articulation of reasoning, and nudges toward discovery — without ever spoiling or directly giving the full answer unless the user explicitly requests it.
- Reveal: Instant access to a structured full model answer, including components, alternatives, trade-offs, gotchas, and common pitfalls.

AI-native with a local-first product shape and OpenRouter-first model access. OpenRouter is the default integration from day one — giving users seamless access to high-quality frontier, reasoning, and fast models through one API with free tiers and pay-as-you-go credits. Advanced users can still opt into BYOK (Bring Your Own Key) to point to fully local models (MLX/CoreML/Ollama bundles), self-hosted endpoints, or custom remote APIs for maximum privacy/control.

Architecture note: drillbit ships with no custom deployed backend/API of its own. App data, challenge history, summaries, and personalization stay on-device. The only network calls are direct client calls to third-party services such as OpenRouter for model access and RevenueCat for subscriptions/billing.

Runtime prompts are bundled with the app as markdown assets and loaded at startup. The default focus prompt comes from the same runtime prompt library unless the user has already saved their own focus prompt.

Users set their focus once (or tweak anytime) via a free-form prompt (e.g., "system design medium-hard: live collaboration tools, payment gateways, recommendation engines, URL shorteners; probe deeply on consistency, latency, partitioning; avoid basic CRUD and easy arrays"). The app maintains rich local memory to:

- Avoid repeating exact challenges while still allowing fresh similar ones later.
- Track struggles/weak areas (e.g., "consistency models: 3 fails").
- Boost weak topics in future feeds.
- Personalize every problem generation and AI Coach interaction.

Style: Pure X-inspired minimalism with both light and dark themes — crisp white/light-gray surfaces in light mode, deep black/charcoal surfaces in dark mode, subtle #1D9BF0 accents, generous whitespace, 16px rounded cards, system fonts, haptic feedback, glanceable and calm.

Implementation bias: native first wherever practical. Prefer Expo and React Native native capabilities, platform components, and device APIs before reaching for web-style abstractions. Use web-only or DOM-based fallbacks only when they unlock something clearly worth it.

After one-time setup in the Params tab (focus prompt editor, explicit difficulty setting, OpenRouter-first model picker backed by a local editable model catalog with qwen 3.5 flash as the default, one shared preferred mode, first challenge time, and a cadence picker limited to divisors of 24h), users live almost entirely in the widget:

Daily flow:

1. Home-screen widget refreshes (per schedule, e.g., every 6h, cap 5/day) → shows fresh problem teaser (title, difficulty pill, 1-2 line description, topic badges) + tappable actions such as Solo | AI Coach | Reveal | Skip. Tiny struggle badge (e.g., "Consistency: 2 fails") appears in corner if relevant.
2. User taps preferred mode → haptic + deep-link opens Answer Modal directly (fast/minimized launch).
3. Answer Modal:
    - Fixed top strip: problem title/teaser + brief past-performance context ("Last similar: 58% · 3 attempts on CRDTs vs OT · AI Coach used 4× · Weak: conflict resolution").
    - The lower header row places the model picker on the left, the collapse handle in the middle, and the mode picker on the right, with the topic/difficulty pills centered beneath them.
    - A thin collapse handle sits at the bottom of the header so the prompt can shrink away and give more room to the solving surface.
    - A second thin assistant header appears only in AI Coach and Reveal; it surfaces one short guidance line at a time and opens a capped-height coach/reveal modal with prior AI history when tapped.
    - The main body is one large answer area that stays central in every mode so the user always works in one consistent solving surface.
    - AI guidance lives in the thin assistant header and separate ask-AI entry point, not inside the main answer surface.
    - In AI Coach: streaming chat starts with gentle opener, then back-and-forth probing/hints ("How would offline merges impact your chosen model? Any latency trade-offs?") + quick-reply chips ("Deeper probe", "Trade-offs?", "Next component", "Stuck").
    - Session state owned by the modal: `selectedMode`, `notesDraft`, `conversationSummary`, `updatedAt`.
4. Answer actions live inline beside the answer label as small right-aligned pills: Skip | Save | Done.
   - There is at most one active challenge in the live app flow: prefer an `in_progress` challenge if one exists, otherwise the newest non-expired `ready` challenge.
   - Generating a new challenge clears older untouched `ready` challenges so the active flow stays singular and predictable.
   - Every fresh `ready` challenge gets an `expiresAt` based on the current schedule, and changing schedule settings refreshes expiry for still-untouched ready challenges.
   - Completed and skipped challenges leave the active flow and become resolved memory, while untouched expired `ready` challenges may be pruned as stale.
   - `save` means "keep this as my active in-progress challenge exactly where I left it"; it persists notes, mode, and assistant conversation history without resolving the challenge.
5. Summary Page (brief & rewarding):
   - AI-generated completion percentage (e.g., "82% — strong partitioning, explore optimistic locking more").
   - Concise personalized feedback ("You nailed CRDT fit but hesitated on merge conflicts — next time push resolution strategies").
   - Quick toggles: Mark mastered / Boost tag / Save note.
   - "View full chain" link → this problem's Memory Card.
   - Close → app backgrounds; widget refreshes next problem soon after.

Memory stores every interaction as a rich card locally (SQLite + shared widget state):

- Full conversation chain (user notes/responses + AI messages) for active or completed challenges that are still retained.
- Performance metrics (completion %, modes used, AI usage count, detected struggle patterns/tags).
- Challenge rows store the generated prompt artifact (`title`, `teaser`, `topic`, app-owned `difficulty`) plus lifecycle metadata like created/started/completed/skipped timestamps, while help mode stays on the session record.
- Completed and skipped items keep a short blocked summary used to tell the model which exact challenge shapes not to repeat.
- Similar challenges are still allowed later; repeat blocking targets exact prior challenge shapes, not the whole topic area.
- Untouched expired challenges may be pruned entirely to save space and allow future similar prompts again.
- Skipped challenge rows may be cleaned up after a retention window, while their blocked summaries remain preserved so exact skipped prompts do not return.
- Accessible in Mem tab: thin progress graph (drag/scrub days, replay past sessions), accordion cards for deep review, bulk forget/re-enable.

System prompt for every new problem generation and AI Coach response is dynamically constructed from:

- App core description & goals.
- User's current focus prompt.
- Relevant memory slice (weak areas, blocked exact-repeat summaries, recent performance).
- Specific problem's past context (for continuity in modal sessions).

Result: a truly adaptive, non-repetitive, guiding experience that feels intelligent and evolves with the user — all local/privacy-first, widget-heroic, and X-clean.

Developer builds also expose a Dev tab for local-only tooling like wiping SQLite, adding/selecting/deleting locally available model ids, seeding widget state, previewing model context, and other fast debug actions.
