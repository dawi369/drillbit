# Verification — 23 September 2026

## September 25 · particle concept

- Preserved the existing contour screen and renderer. Added the separate Particle tab, palette, static/animated particle layers, narrow waveform and source selector.
- iPhone 18 Pro simulator, iOS 27: visually inspected the new concept against the supplied screenshot. Confirmed bundled interviewer speech animates the cloud and waveform, band-scan energy changes them across frequencies, stop resets playback, natural speech completion returns to play, and Close returns to the original Orb Lab.
- Checked `accessibility-extra-large` Dynamic Type: waveform, timer, source and transport stay visible; replaced a scaling close glyph with fixed vector strokes. Restored the simulator's original `large` setting.
- Hid the native tab bar while the particle concept is open, then verified Close restores the original tab bar and contour screen.
- Captured the native simulator view at `output/orb-lab/particle-concept-ios.png` for review.
- TypeScript, lint, 7 spectrum/motion tests and `git diff --check` pass.
- This is local playback proof. Microphone input, an AI conversation, Android, physical-device frame pacing and GPU timing remain unverified. The iOS simulator's status-bar region is darker than the drawn charcoal gradient.

## September 24 correction

- Removed contour highlights, directional surface shading, rim, texture, halos and blur passes. The renderer now uses a flat graphite surface and one amber stroke per frequency contour.
- Found the lab's temporary Reduce Motion override still enabled in the simulator. Relaunched the lab to reset transient test state; the default override is off and system accessibility preferences remain respected.
- Lint and TypeScript pass. Post-relaunch visual/motion acceptance could not be completed because the Mac locked; earlier iteration checks below do not certify this correction's frame pacing.

## Passed

- iPhone 18 Pro simulator, iOS 27.0, Xcode 27: SDK 57 development build compiled and installed. Final build reported **0 errors**, with two upstream build-script warnings.
- Native app launched through the SDK 57 scene lifecycle and loaded the Metro bundle from localhost:8083.
- Visually inspected the dark contour renderer and native navigation. Accessibility inspection exposed playback, source selection, each of the 12 frequency-band controls, theme toggle, loop, import, and tuning.
- Iteration 02: inspected light and dark palettes, the shaded/textured contour renderer, playback hierarchy and expanded tuning controls in the native simulator.
- Played the speech and band-scan fixtures; observed elapsed time, speaking state, changing FFT bars and peak-frequency labels. Pause, stop, contour focus/reset and the lab's reduced-motion toggle were exercised.
- Checked normal and accessibility-extra-large Dynamic Type. Fixed clipped labels after live text-scale changes, added wrapping controls, and simplified chart labels at accessibility sizes. Restored the simulator's original `large` text setting afterward.
- `npm run lint`: no warnings or errors.
- `npm run typecheck`: passed with TypeScript 6.
- `npm test`: **7 tests, 188 assertions**, including 44.1/48/96 kHz band routing, finite silence handling, logarithmic power addition, and matching envelope convergence at 60/120 Hz.
- `EXPO_OFFLINE=1 npx expo install --check`: installed packages match the SDK's bundled compatibility map.
- Root package manifest and lockfile were not changed.

## Remaining acceptance

- Resume, loop boundaries and natural completion.
- Sweep and the complete band scan traversing all 12 contours.
- OSS reference receiving the same audio.
- Tuning slider behavior and smaller physical screen sizes.
- Import/cancel, unsupported or oversized audio, rapid source changes, leaving the tab and backgrounding.

Physical-device frame pacing, GPU timing, audio latency, battery impact and Android have not been measured. The onscreen frame callback counter is diagnostic only.

## Dependency diagnostics

The online Expo doctor passed 20 of 21 checks before the final TypeScript update; its remaining check requested newer patch releases outside the configured seven-day npm release-age window. TypeScript was updated to the SDK recommendation. The older compatible Expo/router/constants/build-properties patches remain intentional and are not hidden using exclusions.

`npm audit` reports **13 moderate**, no high or critical findings, propagated from the `uuid`/`xcode` tooling chain and `decode-uri-component`/`query-string` router chain. No forced major-version downgrade or global security-policy change was applied. This is an isolated local experiment, not a release baseline.
