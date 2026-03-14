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

## Notes

- Widgets should stay on `@expo/ui` primitives only.
- Main app screens should use HeroUI Native components styled with Uniwind.
- Prefer native Expo and React Native capabilities before web or DOM-based fallbacks.
- Widget development requires a dev build or EAS build, not Expo Go.
