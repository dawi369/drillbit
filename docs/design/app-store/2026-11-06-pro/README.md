# Pro screenshot set — 6 November 2026

Five captioned App Store images, in upload order, are in `ready/`. Unmodified simulator captures are in `raw/`. `contact-sheet.png` previews the full sequence.

| Order | Image | Headline |
|---|---|---|
| 1 | `01-interview.png` | Get better at system design. |
| 2 | `02-feedback.png` | Know what worked. Know what to fix. |
| 3 | `03-example.png` | Stuck? See one worked example. |
| 4 | `04-knowledge-map.png` | See what you actually know. |
| 5 | `05-recall.png` | Make the lesson stick. |

Suggested promotional text:

> Your answer is the start. Practise system design with an AI interviewer that pushes back, shows you what to fix, and helps the lesson stick.

Knowledge map requires Pro. Other pictured features are also available subject to the app's free allowance. Pro has fair-use limits; no unlimited-use or hiring-outcome claims are made.

## Capture provenance

- Source: local HEAD `1db473d860a43bbf10ee068e06acf2a61c455118`, version **1.0 (19)**; screenshot test arguments additionally enable Pro for every signed-in scene.
- Device: dedicated **iPhone 17 Pro Max**, iOS **27.0**, simulator `C5811F7F-0B18-4F6E-BE39-E30DC7E5715E`.
- Dark appearance, English, status bar 9:41, full battery; `--fixtures --fixture-customer --fixture-pro` uses synthetic practice content and hides developer controls. No account upgrade, purchase, or production data change.
- Existing `StoreScreenshots/testStoreScreenshots` walks the actual current app UI. Welcome, Home and Library are captured as alternatives but excluded from the final five.
- Voice is excluded because its simulator fixture exposes a debug speech control; no live voice session is implied by these captures.

## Creative and validation

Applied [alexszczurek/before-skills — aso](https://github.com/alexszczurek/before-skills/blob/main/skills/aso/SKILL.md): benefit first, short captions, then differentiation and concrete feature proof. All five show the app in use: **English / iPhone large display: 5 of 5 in use — pass** (minimum 3).

Final images: **1320 × 2868**, opaque RGB PNG, sRGB. This is an accepted large-display size in [Apple's screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications). Each whole screen is scaled proportionally under its headline; no UI text is replaced, and no primary feature is covered by marketing overlays. The rounded surround is decorative, not a hardware rendering.

Simulator fixtures verify UI presentation; they do not verify live AI, billing, or physical-device behavior. Files are prepared locally and have not been uploaded to App Store Connect.

Verification: the fresh Xcode build and `StoreScreenshots/testStoreScreenshots` passed (1 test, 0 failures); see `test-summary.json`. All five output PNG headers were checked for exact dimensions, 8-bit RGB, and no alpha. `manifest.json` records their SHA-256 hashes. `Drillbit-App-Store-Pro.zip` contains the five upload images, contact sheet, manifest and this caption sheet.

## Regenerate

Run `StoreScreenshots/testStoreScreenshots` on the device above with `xcodebuild test`, exporting the result bundle attachments with `xcrun xcresulttool export attachments`. Rename exported files using `suggestedHumanReadableName` in its manifest. Then:

```sh
swift docs/design/app-store/2026-11-06-pro/render.swift \
  docs/design/app-store/2026-11-06-pro/raw \
  docs/design/app-store/2026-11-06-pro/ready
```

Use files `01` through `05` from `ready/` for upload. The contact sheet is for review only.
