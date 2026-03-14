# drillbit

Minimal, widget-first interview prep for software engineers.

The product direction is centered on system design, distributed systems, trade-offs,
and high-level verbal reasoning instead of code-first drilling. The app is
OpenRouter-first, supports both light and dark themes, and is built so the widget
becomes the primary daily touchpoint.

## Current foundation

- Expo SDK 55 with `expo-router`
- `expo-widgets` and `expo-dev-client` for widget-ready native builds
- `heroui-native` + `uniwind` for the main app UI layer
- `expo-sqlite`, `expo-secure-store`, `expo-updates`, `expo-haptics`
- `zustand` for lightweight app state
- OpenRouter as the default model provider
- No custom deployed backend; app data stays local and network calls go directly to providers

## Notes

- Widgets should stay on `@expo/ui` primitives only.
- Main app screens should use HeroUI Native components styled with Uniwind.
- Prefer native Expo and React Native capabilities before web or DOM-based fallbacks.
- The initial widget scaffold lives in `src/widgets/drillbit-widget.tsx` and is wired through `app.json`.
- Widget development requires a dev build or EAS build, not Expo Go.
- The app architecture is local-only by default: SQLite/App Groups for app data, SecureStore for secrets, direct calls to OpenRouter and RevenueCat.
- Challenge history stays local, skipped items are deduped out of future prompts, and expired untouched challenges can be pruned.
