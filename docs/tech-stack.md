Drillbit Tech Stack – March 2026

Core Framework
• Expo SDK 55 (required for expo-widgets interactive iOS widgets)

Widgets & Widget UI
• expo-widgets (alpha) – interactive home-screen widgets + Live Activities
• @expo/ui primitives – VStack, HStack, Text, Button, Toggle (widget-only, no RN libs inside widgets)

App Navigation & Routing
• expo-router (~v7) – file-based routing, deep-links from widget to Answer Modal

Styling & UI
• uniwind (Tailwind v4 binding) – utility-first className styling
• HeroUI Native v3 – polished, accessible components (Card, Button, Badge/Pill, Input, SegmentedControl, Modal, Accordion, etc.)
→ Composed with uniwind className props for a clean light/dark native UI

State & Data
• zustand – lightweight global state where ephemeral UI state needs it
• expo-sqlite + expo-widgets App Groups – rich local memory cards, challenge history, blocked exact-repeat summaries, and shared widget sync
• expo-sqlite models table – editable local catalog of available models plus selected model id in settings
• Challenge/session split – generated challenge content lives on challenge rows, while selected help mode and notes live on challenge sessions
• Active challenge flow – the app resolves one active challenge at a time by preferring `in_progress`, then the newest valid `ready`; ready rows get schedule-based `expiresAt` values and stale untouched rows fall out of the active path
• expo-secure-store – OpenRouter API key / BYOK credentials
• Scheduling model – first challenge time plus cadence values restricted to divisors of 24h

Architecture
• No custom deployed backend/API – challenge state, memory, summaries, and personalization stored locally on device
• Direct third-party calls only – OpenRouter for AI, RevenueCat for billing/subscription state

LLM / AI Backend
• OpenRouter – primary model provider (default from the start, with qwen 3.5 flash as the seeded default)
• BYOK support – user-configurable endpoint + key (local Ollama/MLX/CoreML or remote)
• Bundled markdown prompt library – runtime system prompts and the default focus prompt load from bundled `.md` assets at app startup, then render with structured tags like `<focus_prompt>`, `<blocked_challenge_shapes>`, and `<task>`
• Local model catalog – seeded starter models plus user-added model ids stored in SQLite, with soft deletion and one selected model id in settings

Animations & Polish
• react-native-reanimated – smooth expands, graph scrubbing, button haptics
• expo-haptics – tactile feedback on widget taps / mode switches
• expo-blur – blurred backgrounds for Focus Prompt modal & overlays

Builds & Dev
• EAS Build / EAS Submit – iOS & Android builds
• expo-dev-client – custom dev builds (required for expo-widgets testing)
• expo-updates – OTA updates for non-widget code

Dev Tools / Extras
• lucide-react-native – subtle icons
• react-native-svg – thin progress graph line (if needed beyond Reanimated)
• Dev-only app tab – local reset/debug actions such as wiping SQLite, seeding widget payloads, and inspecting future model context

Key Constraints / Notes
• Widget UI limited to @expo/ui primitives (no HeroUI / uniwind inside widgets)
• Main app screens: HeroUI Native components styled via uniwind className
• Prefer native implementations first – Expo/React Native APIs and platform primitives before web/DOM fallbacks
• No Expo Go for widgets – dev builds / EAS only
• Bundle goal: tree-shake HeroUI imports, keep app lean (widget as hero surface)
• Completed and skipped challenges are excluded from future exact-repeat generation via short blocked summaries sent with generate prompts
• Similar challenges are still allowed later; repeat blocking targets exact prior challenge shapes, not broad topic bans
• Untouched expired challenges may be deleted locally to save space and allow similar future prompts
• Skipped challenge rows may be pruned after a retention window while their blocked summaries remain preserved
• Params scheduling uses a first-time anchor plus cadence options that divide evenly into 24h
