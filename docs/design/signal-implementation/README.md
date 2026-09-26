# Signal native implementation

Simulator captures from the SwiftUI implementation of the [Signal direction](../figma-comparison/drillbit-signal-app-board.svg), on iPhone 18 Pro with iOS 27.0. These are local fixture and UI-test states, not live-service or device captures.

- `home-dark.png` and `home-light.png`: same hierarchy with the graphite and warm-light palettes.
- `welcome-dark.png`: static particle texture and waveform in onboarding.
- `recall-empty-dark.png`: empty Recall state.
- `voice-connecting-dark.png`: static voice-room texture while connection is pending.
- `onboarding-open-dark.png` and `onboarding-open-light.png`: open onboarding hierarchy with inset selection and an unboxed action.
- `settings-dividers-dark.png`: settings rows on the page floor, separated by rules.

The particle and waveform graphics are decorative and static. They do not visualize microphone input; motion and the agent orb are deferred.
