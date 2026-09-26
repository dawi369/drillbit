# Drillbit Orb Lab

Isolated Expo development app for tuning an audio-reactive agent. It is outside the production workspace and does not touch the SwiftUI app, accounts, backend, or archived Expo client.

Two design directions can be compared in the same development build: **Orb Lab** retains the original contour experiment; **Particle** is a separate voice-presence concept anchored to the supplied charcoal/silver/coral reference. See [PARTICLE_CONCEPT.md](./PARTICLE_CONCEPT.md) for its palette and motion rules.

## Run

```sh
cd /Users/dawi/dev/drillbit/experiments/orb-lab
npm ci
npm run ios
```

After the first native build, use `npm start` for JS-only iteration. Metro uses port **8083**. Open **Drillbit Orb Lab** in the simulator and connect to that local server. This uses custom native audio code and therefore cannot run in Expo Go. Native projects are generated and ignored by Git.

For a simulator build with an already-running Metro server:

```sh
npx expo run:ios --no-bundler
xcrun simctl openurl booted 'drillbit-orb-lab://expo-development-client/?url=http%3A%2F%2Flocalhost%3A8083'
```

The baseline is Expo **57.0.23**, RN **0.86.3**, Skia **2.6.2**, Reanimated **4.5.1**, Audio API **0.13.3**, and expo-thinking-orbs **0.2.1**. Dependencies were selected from the installed SDK's `bundledNativeModules.json` while respecting the machine's seven-day npm release-age policy. Commit the local lockfile; do not blindly accept the CLI's newer remote patch suggestions if they violate that policy.

Xcode 27 requires UIKit scene support. This lab enables the official SDK 57 backport using `expo-build-properties` **57.0.20**, `ios.enableSceneSupport: true`. Keep that configuration when regenerating iOS. See [Expo's migration note](https://github.com/expo/fyi/blob/main/ios-scene-lifecycle.md#staying-on-sdk-57-with-xcode-27).

If npm reports Skia's install script pending approval, inspect and allow the package's `scripts/install-libs.js` before building. It copies the installed Skia platform binaries into their expected library paths; it does not need a global policy change.

## Evaluate

- **Voice:** original system-design question, synthesized locally using macOS Samantha; useful speech pauses and transient consonants.
- **Band scan:** twelve tones, one second per band including a silence gap. Peak energy should move from the inner contour outward.
- **Sweep:** continuous logarithmic 70 Hz–9 kHz sweep.
- **Import:** local audio, up to 30 MB and three minutes; no upload.
- Tap a spectrum band to visually focus its corresponding contour. It does not solo or filter the audio.
- Compare **Contours** with the installed **OSS reference** using identical playback.
- Tune sensitivity, attack/release, contour response, volume, loop, light/dark, and reduced motion.

The tone fixtures can be regenerated with `python3 scripts/generate-audio.py`. The speech source is `assets/audio/interviewer.txt`; its committed WAV keeps the lab independent of OS voice availability.

```sh
npm run typecheck
npm run lint
npm test
```

Read [RESEARCH.md](./RESEARCH.md) for source links, licensing, palette, signal flow, and renderer boundaries. Read [VERIFICATION.md](./VERIFICATION.md) for the exact tested boundary.
