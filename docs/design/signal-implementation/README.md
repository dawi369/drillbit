# Signal native implementation

Simulator captures from the SwiftUI implementation of the [Signal direction](../figma-comparison/drillbit-signal-app-board.svg). These are local fixture and UI-test states, not live-service or device captures.

Refreshed 27 September 2026 on iOS 27.0 after the motion and onboarding polish (iPhone 18 Pro Max unless marked iPhone 17):

- `welcome-dark.png`: signed-out walkthrough with the step track, presence orb and pinned footer; sign-in follows the fourth page (iPhone 17).
- `onboarding-intro-dark.png` and `onboarding-intro-light.png`: the personal setup introduction (iPhone 17).
- `onboarding-open-dark.png`: a setup page with inset selection, a checkmark mid-arrival and rules hidden around the selection.
- `home-dark.png` and `home-light.png`: Home with the next question, journey, Revisit links and Explore.
- `recall-empty-dark.png`: empty Recall state.
- `voice-muted-dark.png`: the voice room while muted — the orb contracts and dims (iPhone 17).

Earlier captures (iPhone 18 Pro, 25–26 September) that predate this pass:

- `onboarding-open-light.png`: open onboarding hierarchy in light appearance.
- `settings-dividers-dark.png`: settings rows on the page floor, separated by rules.
- `voice-connecting-dark.png`: voice room while connection is pending, before the presence became animated.

Presence motion is ambient on Welcome, setup and the idle voice room, and follows WebRTC audio levels during live voice. Still images cannot show it; Reduce Motion renders the same still texture seen here. Live-level behaviour has not been verified on a physical device.
