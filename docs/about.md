A minimal, widget-first app called drillbit — designed for software engineers preparing for SWE interviews, with a strong emphasis on system design, architecture, distributed systems, scalability, trade-offs, fault tolerance, and other high-level conceptual topics that are best reasoned about and discussed in English rather than pure code (e.g., "How would you design a live collaboration document editor like Google Docs? Walk through consistency models, conflict resolution strategies, offline support, partitioning, latency vs durability trade-offs…"). Algorithmic/LeetCode-style questions are fully supported if the user specifies them in their focus prompt, but the app's default DNA favors verbal, discussion-heavy problems that mirror real senior/staff-level interviews.

Customizable home-screen widget lets users choose their preferred interaction mode at a glance:

- Solo: Clean problem statement + space for personal notes/thinking (no AI interference).
- AI Coach: Gentle, Socratic guidance — the AI probes with thoughtful questions ("What consistency guarantee would you prioritize here, and why?"), provides step-by-step directional hints, highlights key trade-offs, encourages articulation of reasoning, and nudges toward discovery — without ever spoiling or directly giving the full answer unless the user explicitly requests it.
- Reveal: Instant access to a structured full model answer, including components, alternatives, trade-offs, gotchas, and common pitfalls.

AI-native with a local-first product shape and OpenRouter-first model access. OpenRouter is the default integration from day one — giving users seamless access to high-quality frontier, reasoning, and fast models through one API with free tiers and pay-as-you-go credits. Advanced users can still opt into BYOK (Bring Your Own Key) to point to fully local models (MLX/CoreML/Ollama bundles), self-hosted endpoints, or custom remote APIs for maximum privacy/control.

Architecture note: drillbit ships with no custom deployed backend/API of its own. App data, challenge history, summaries, and personalization stay on-device. The only network calls are direct client calls to third-party services such as OpenRouter for model access and RevenueCat for subscriptions/billing.

Users set their focus once (or tweak anytime) via a free-form prompt (e.g., "system design medium-hard: live collaboration tools, payment gateways, recommendation engines, URL shorteners; probe deeply on consistency, latency, partitioning; avoid basic CRUD and easy arrays"). The app maintains rich local memory to:

- Avoid repeating near-duplicate questions.
- Track struggles/weak areas (e.g., "consistency models: 3 fails").
- Boost weak topics in future feeds.
- Personalize every problem generation and AI Coach interaction.

Style: Pure X-inspired minimalism with both light and dark themes — crisp white/light-gray surfaces in light mode, deep black/charcoal surfaces in dark mode, subtle #1D9BF0 accents, generous whitespace, 16px rounded cards, system fonts, haptic feedback, glanceable and calm.

Implementation bias: native first wherever practical. Prefer Expo and React Native native capabilities, platform components, and device APIs before reaching for web-style abstractions. Use web-only or DOM-based fallbacks only when they unlock something clearly worth it.

After one-time setup in the Params tab (focus prompt editor, explicit difficulty setting, OpenRouter-first model picker, one shared preferred mode, first challenge time, and a cadence picker limited to divisors of 24h), users live almost entirely in the widget:

Daily flow:

1. Home-screen widget refreshes (per schedule, e.g., every 6h, cap 5/day) → shows fresh problem teaser (title, difficulty pill, 1-2 line description, topic badges) + tappable actions such as Solo | AI Coach | Reveal | Skip. Tiny struggle badge (e.g., "Consistency: 2 fails") appears in corner if relevant.
2. User taps preferred mode → haptic + deep-link opens Answer Modal directly (fast/minimized launch).
3. Answer Modal:
   - Fixed top strip: problem title/teaser + brief past-performance context ("Last similar: 58% · 3 attempts on CRDTs vs OT · AI Coach used 4× · Weak: conflict resolution").
   - Segmented pills to switch modes freely (Solo / AI Coach / Reveal) — state preserved.
   - In AI Coach: streaming chat starts with gentle opener, then back-and-forth probing/hints ("How would offline merges impact your chosen model? Any latency trade-offs?") + quick-reply chips ("Deeper probe", "Trade-offs?", "Next component", "Stuck").
   - Large text area for notes, reasoning outlines, ASCII diagrams — no heavy code editor needed.
4. When finished → tap Done (bottom blue pill).
5. Summary Page (brief & rewarding):
   - AI-generated completion percentage (e.g., "82% — strong partitioning, explore optimistic locking more").
   - Concise personalized feedback ("You nailed CRDT fit but hesitated on merge conflicts — next time push resolution strategies").
   - Quick toggles: Mark mastered / Boost tag / Save note.
   - "View full chain" link → this problem's Memory Card.
   - Close → app backgrounds; widget refreshes next problem soon after.

Memory stores every interaction as a rich card locally (SQLite + shared widget state):

- Full conversation chain (user notes/responses + AI messages) for active or completed challenges that are still retained.
- Performance metrics (completion %, modes used, AI usage count, detected struggle patterns/tags).
- Challenge lifecycle metadata, including completed and skipped items, with a dedupe key so skipped challenges never reappear.
- Expired untouched challenges may be pruned entirely to save space and allow future similar prompts again.
- Accessible in Mem tab: thin progress graph (drag/scrub days, replay past sessions), accordion cards for deep review, bulk forget/re-enable.

System prompt for every new problem generation and AI Coach response is dynamically constructed from:

- App core description & goals.
- User's current focus prompt.
- Relevant memory slice (weak areas, avoided similars, recent performance).
- Specific problem's past context (for continuity in modal sessions).

Result: a truly adaptive, non-repetitive, guiding experience that feels intelligent and evolves with the user — all local/privacy-first, widget-heroic, and X-clean.

Developer builds also expose a Dev tab for local-only tooling like wiping SQLite, seeding widget state, previewing model context, and other fast debug actions.
