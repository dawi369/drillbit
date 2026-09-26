# Orb Lab — implementation decision

Research and package-source inspection: 23 September 2026.

| Candidate | What it supplies | Decision |
| --- | --- | --- |
| [React Native Skia](https://github.com/Shopify/react-native-skia) · MIT | Native vector drawing and direct Reanimated shared-value support | Use for the contour renderer. |
| [Reanimated](https://github.com/software-mansion/react-native-reanimated) · MIT | UI-thread worklets and frame callbacks | Use for phase, attack/release envelopes, and geometry updates. |
| [React Native Audio API](https://github.com/software-mansion/react-native-audio-api) · MIT | Local playback, decoded PCM, native FFT analyser | Use as the common audio source for both renderers. Requires a development build. |
| [expo-thinking-orbs](https://github.com/mahdidavoodi7/expo-thinking-orbs) · MIT | Skia dotted shell, voice lifecycle transitions, amplitude and three-band inputs | Install the actual component as a live OSS comparison. Its published 0.2.1 source supports `outputLevels`; it is not amplitude-only. |
| [ElevenLabs UI Orb](https://ui.elevenlabs.io/docs/components/orb) · [MIT source](https://github.com/elevenlabs/ui) | Web/Three.js orb | Visual reference only. Not a React Native drop-in. |
| [Rive React Native](https://rive.app/docs/runtimes/react-native/react-native) | Authored state-machine animation | Defer. Procedural frequency contours do not need an animation-file authoring pipeline. |

The custom contour geometry is original code, not copied from an OSS orb. Third-party implementations remain package dependencies with their licenses intact. Audio API includes additional third-party notices in its repository; its MIT package label is not a substitute for reviewing bundled codec notices before distributing a product.

## Signal and rendering boundary

`buffer source → native analyser → speaker gain → destination`

The analyser uses a 4096-sample FFT at 48 kHz (about 85 ms of signal and 11.7 Hz per bin). Twelve logarithmic bands span 70–9000 Hz. Each band sums linear spectral power before conversion to a bounded dB-derived visual value. These are visual energy estimates, not calibrated loudness measurements. The scan fixture exercises each band's geometric-center frequency.

FFT reads run at up to 30 Hz on the JS side. Twelve scalars cross to Reanimated; geometry and interpolation run on the UI thread at display cadence. Initial envelopes use 45 ms attack and 260 ms release. Bass maps to the inner contour and treble to the outer contour. A shared phase prevents independent lines from losing the overall form. Speaker gain follows analysis, so muting playback does not erase the diagnostic signal.

The OSS reference receives the same FFT data, grouped approximately into low/mid/high bands. It retains its own package animation and smoothing. That is a visual comparison, not an identical-envelope benchmark.

The renderer accepts motion values without owning audio transport. This allows later live-agent integration without putting microphone permissions, interruptions, networking, or reconnect policy inside the orb.

## Palette

| Role | Dark | Light |
| --- | --- | --- |
| Background | `#191F2B` | `#F5F7FB` |
| Surface | `#252E3E` | `#FFFFFF` |
| Primary ink | `#F4F6FC` | `#202A3C` |
| Secondary ink | `#ABB8CD` | `#5D6C83` |
| Action | `#FFD071` | `#FFD071` |
| Active signal | `#FFD071` | `#A26A08` |
| Live status | `#75DECA` | `#167B69` |
| Agent substrate | `#232834` | `#232834` |
| Agent mark | `#FFCC65` | `#FFCC65` |

Contours use a uniform `#FFD071` stroke on matte `#232834`. The September 24 correction removes the glare, rim lighting, texture and all blur passes from the orb following visual feedback. Audio changes contour geometry and opacity without introducing lighting effects. Cooler backgrounds give the amber more separation; light mode uses deeper amber for small foreground details. The agent keeps one identity in both themes. Filled gold is reserved for playback, with quiet outlined secondary controls and tinted selections.

Orb size responds to viewport height and text scale. Controls wrap at accessibility sizes; spectrum numbers yield to the full accessible frequency labels. A text-scale change remounts the scroll content to avoid stale native text measurements while transport state remains outside that subtree.

## Evidence and limits

The onscreen counter measures UI frame callback cadence and p95 interval. It is not measured GPU render time, dropped-presented-frame instrumentation, or physical-device proof. A debug simulator build is useful for interaction and signal validation, not final animation acceptance.

Reduced motion freezes contour geometry and pauses the reference renderer while retaining textual state and live diagnostic bars. Leaving the lab or backgrounding the app stops local playback. No microphone capture, AI connection, background playback, backend changes, or production-client migration is included.

## Primary implementation references

- [Skia animation integration](https://shopify.github.io/react-native-skia/docs/animations/animations/)
- [Audio API analyser](https://docs.swmansion.com/react-native-audio-api/docs/analysis/analyser-node/)
- [Audio API setup and native-build requirement](https://docs.swmansion.com/react-native-audio-api/docs/fundamentals/getting-started/)
- [Expo SDK 57 support matrix](https://docs.expo.dev/versions/v57.0.0/)
- [Official SDK 57 scene-lifecycle backport for Xcode 27](https://github.com/expo/fyi/blob/main/ios-scene-lifecycle.md#staying-on-sdk-57-with-xcode-27)
- [Expo native tabs](https://docs.expo.dev/router/advanced/native-tabs/)
