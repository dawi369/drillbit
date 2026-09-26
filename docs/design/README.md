# Drillbit / the AI interviewer

Study 04 · 23 September 2026. [Open the mockups](direction-studies.html). [Agent motion study](direction-studies.html#agent-lab). [Previous direction](direction-studies-v3.html).

## Product direction

**System design. Out loud.** An interviewer for short sessions during the day, with a practice loop that continues afterward.

The proposed selling point combines a low-friction spoken interview with a concrete learning outcome: relevant follow-ups, feedback grounded in what the learner said, and Recall from prior practice. The avatar is recognition and state feedback. It is not evidence that the product outperforms another assistant.

The existing architecture already describes WebRTC voice, teaching modes, shared text/voice context, durable transcript fragments, evidence-grounded reflection, and Recall. These are the foundation for differentiation; this study has not benchmarked quality against ChatGPT or verified current live-service behavior. See [architecture](../architecture.md) and [voice foundations](../voice-foundations.md).

“On a run / at the gym / on the metro” is proposed positioning in a design prototype. Before shipping that promise, validate locked-screen/background audio, Bluetooth and headphone controls, wind and gym noise, interruptions, route changes, patchy connectivity, transcript recovery, and battery/thermal behavior on real devices. Do not imply offline inference or flawless noisy-environment recognition.

## Screens and identity

- **Welcome:** introduce the interviewer and the everyday use case, with one action.
- **Home:** one short recommended conversation; voice is primary, typing remains directly available, Recall stays connected to prior practice.
- **Voice room:** one question, one presence, clear state, explicit Start, microphone control, text handoff, Finish, and optional transcript.
- **Agent lab:** manually preview ready, listening, thinking, speaking, muted, and reconnecting states.

The amber contour resembles a sound fingerprint rather than a face. Layered paths carry the state and the central bars suggest speech. The graphite medallion and amber app mark are identical in both themes. A textual status always accompanies active-session motion.

Ready is still. Listening breathes slowly; thinking rotates; speaking undulates; muted becomes still and subdued; reconnecting uses a broken contour. The browser's motion is illustrative and manually controlled, not driven by audio. Reduced motion freezes the shape while preserving the status and controls.

## Palette

Light mode drops tinted typography and cream/blue backgrounds. Neutral porcelain and graphite give the agent ownership of the warm accent. Dark mode uses close graphite tones, cooler white text, and a less saturated amber action fill.

| Role | Dark | Light |
| --- | --- | --- |
| Background | `#202530` | `#FAFAF9` |
| Surface | `#292F3A` | `#EFEFEC` |
| Primary text | `#EDEFF2` | `#292E35` |
| Secondary text | `#ADB4C0` | `#656C74` |
| Action fill | `#E8C17D` | `#292E35` |
| Action text | `#28261F` | `#FFFFFF` |
| Selected surface | `#343B47` | `#E3E4E2` |
| Divider | `#414957` | `#D2D5D6` |
| App mark / tile | `#FFCC65` / `#232834` | identical |
| Agent contour | `#FFE2A3` → `#D4A355` → `#A97838` | identical |

Static grain remains subtle. Text uses system sans; compact metadata uses system monospace. Motion, color, and technical detail should support the interview rather than compete with it.

## React Native component choice

**Recommend a small custom `AgentPresence` built with React Native Skia + Reanimated.** Skia supports runtime shaders and uniform inputs, and its Reanimated integration runs animations on the UI thread. It can start with these paths, then respond to smoothed input/output audio levels. This gives the design a controllable identity without coupling it to a voice vendor. Sources: [Skia shaders](https://shopify.github.io/react-native-skia/docs/shaders/overview/), [Skia animation integration](https://shopify.github.io/react-native-skia/docs/animations/animations/).

**Rive is the alternative for an authored character or richer choreographed states.** Current official documentation recommends its new Nitro runtime (`@rive-app/react-native`) with data binding and native rendering. It adds a Rive asset-authoring workflow. Verify the actual Expo/runtime compatibility during the native spike; no dependency has been installed here. Source: [Rive React Native](https://rive.app/docs/runtimes/react-native/react-native).

**ElevenLabs Orb is a visual reference, not a drop-in React Native component.** The published component is a Three.js orb from a shadcn-based web library. ElevenLabs separately offers an Expo/React Native voice SDK, but adopting a voice provider is independent of choosing a renderer; the existing voice architecture does not need replacing to build this presence. Sources: [Orb](https://ui.elevenlabs.io/docs/components/orb), [UI library](https://ui.elevenlabs.io/docs), [native voice guide](https://elevenlabs.io/docs/eleven-agents/guides/integrations/expo-react-native).

Proposed renderer boundary:

```ts
type AgentPresenceProps = {
  state: 'ready' | 'listening' | 'thinking' | 'speaking' | 'muted' | 'reconnecting';
  inputLevel: number;   // normalized real microphone level
  outputLevel: number;  // normalized real playback level
  reducedMotion: boolean;
  size: number;
};
```

Transport owns permissions, audio capture, interruption, billing, connectivity, and lifecycle. The renderer only projects state and levels. No session starts from mounting, animating, opening a sheet, or changing themes. Stop animation when hidden/backgrounded. Use a static fallback and cap complexity based on device/battery profiling. Reconnection must never be presented as listening.

## Browser verification and boundaries

Checked paired desktop boards and 390 × 844 mobile Welcome/voice screens. Exercised explicit Start, listening/thinking/speaking/muted states, microphone toggle, transcript disclosure, text handoff, draft retention across mode/theme switches, empty-send guard, text completion, and voice completion into illustrative feedback. Confirmed the speaking animation is present with motion enabled and absent with reduced motion.

Scoped contrast checks: dark secondary text on surface 6.44:1; dark action 8.91:1; light secondary text on background 5.09:1 and on surface 4.61:1; light action 13.67:1. Decorative contours are not used to convey state without a text label.

This is SVG/CSS motion in a browser prototype, not a Skia/Rive implementation. No microphone request, recording, playback, paid session, or inference occurs. Account access and feedback remain fixtures. No production application/backend code or native dependency changed. Physical-device, real audio, noisy-environment, screen-lock, and performance acceptance remain unverified.

Current files: `direction-studies.html`, `study-base.css`, `mirage.css`, `refinement.css`, `voice.css`, and `mirage.js`. All assets are local. Screenshots are under `output/playwright/drillbit-design/voice-*.png`. Earlier iterations remain archived, including their notes. The earlier Figma draft remains incomplete and has not been updated.
