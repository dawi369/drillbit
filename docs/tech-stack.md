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
• zustand – lightweight global state (focus prompt, model config, schedule)
• expo-sqlite + expo-widgets App Groups – rich local memory cards, challenge history, dedupe keys, and shared widget sync
• expo-secure-store – OpenRouter API key / BYOK credentials
• Scheduling model – first challenge time plus cadence values restricted to divisors of 24h

Architecture
• No custom deployed backend/API – challenge state, memory, summaries, and personalization stored locally on device
• Direct third-party calls only – OpenRouter for AI, RevenueCat for billing/subscription state

LLM / AI Backend
• OpenRouter – primary model provider (default from the start, strong reasoning models)
• BYOK support – user-configurable endpoint + key (local Ollama/MLX/CoreML or remote)

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

Key Constraints / Notes
• Widget UI limited to @expo/ui primitives (no HeroUI / uniwind inside widgets)
• Main app screens: HeroUI Native components styled via uniwind className
• Prefer native implementations first – Expo/React Native APIs and platform primitives before web/DOM fallbacks
• No Expo Go for widgets – dev builds / EAS only
• Bundle goal: tree-shake HeroUI imports, keep app lean (widget as hero surface)
• Skipped challenges are stored in local history and excluded from future generation
• Untouched expired challenges may be deleted locally to save space and allow similar future prompts
