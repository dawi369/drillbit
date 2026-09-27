# Signal native implementation

Simulator captures from the SwiftUI implementation of the [Signal direction](../figma-comparison/drillbit-signal-app-board.svg). These are local fixture and UI-test states, not live-service or device captures.

Refreshed 27 September 2026 on iPhone 18 Pro Max, iOS 27.0, after the motion and onboarding polish:

- `welcome-dark.png`: signed-out walkthrough with the step track, living presence and pinned footer.
- `onboarding-intro-dark.png` and `onboarding-intro-light.png`: the personal setup introduction.
- `onboarding-open-dark.png`: a setup page with inset selection, a checkmark mid-arrival and rules hidden around the selection.
- `home-dark.png` and `home-light.png`: Home with the next question, journey, Revisit links and Explore.
- `recall-empty-dark.png`: empty Recall state.

Earlier captures (iPhone 18 Pro, 25–26 September) that predate this pass:

- `onboarding-open-light.png`: open onboarding hierarchy in light appearance.
- `settings-dividers-dark.png`: settings rows on the page floor, separated by rules.
- `voice-connecting-dark.png`: voice room while connection is pending, before the presence became animated.

Presence motion is ambient on Welcome, setup and the idle voice room, and follows WebRTC audio levels during live voice. Still images cannot show it; Reduce Motion renders the same still texture seen here. Live-level behaviour has not been verified on a physical device.
