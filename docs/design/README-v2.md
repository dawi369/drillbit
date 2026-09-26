# Drillbit / Mirage

Design study 02 · 22 September 2026. Browser mockups, not a native implementation or framework migration. Existing architecture remains in [architecture.md](../architecture.md).

## Review

- [Updated mockups and interactive flow](direction-studies.html): six screens, paired dark/light themes, onboarding, interview, feedback, and a Recall reveal interaction. Serve this directory or open the HTML with its CSS/JS siblings present. No dependencies or remote assets.
- [Previous comparison](direction-studies-v1.html) and [its design notes](direction-studies-v1.md) are archived for comparison.
- The [earlier Figma draft](https://www.figma.com/design/kpoYsnLG4GGc5dgRJCXIlV) is incomplete and predates Mirage. It has not been updated; the browser mockups are the current artifact.
- Screenshots: `output/playwright/drillbit-design/mirage-dark.png`, `mirage-light.png`, `mirage-feedback.png`, `mirage-recall.png`, and `mirage-mobile.png`.

## Direction

An editor-inspired practice environment: quiet grain, syntax accents, aligned gutters, an inline change, and diagrams that explain the problem. Large system typography carries the main thought; monospace identifies metadata and code. Short copy leaves room for the learner's thinking.

The design has a specific visual grammar:

- **Welcome:** an edge-to-edge code example introduces a useful change. One promise and one primary action.
- **Home:** an unboxed topic leads into a delivery diagram. Recall becomes a layered deck rather than another dashboard row.
- **Interview:** turn numbers and a vertical gutter distinguish the learner's thought from the follow-up. A fixed composer separates drafting from sending.
- **Feedback:** a quoted answer followed by an insertion-style “next time” annotation. Production must ground this in the submitted answer; the mockup is explicitly illustrative.
- **Recall:** one question, an explicit reveal, and a concise explanation. Scheduling and grading remain outside the prototype.

Texture is a local SVG noise tile at low opacity, a faint grid in the code example, and a stippled diagram field. It is static and subordinate to text. Reduced-transparency mode removes noise and blur. Most content remains opaque; native material rendering is still an implementation decision.

## Palette provenance and tokens

The matching editor configuration was found in `~/Library/Application Support/Cursor/User/settings.json`: `workbench.colorTheme: One Dark Pro`, `oneDarkPro.editorTheme: Ayu`, bold enabled, and an object-key syntax override of `#56B6C2`. The conventional VS Code settings path was absent. The three user-sampled colors below are used verbatim; remaining roles are selected for the mockup. This is not a claim to reproduce every editor token.

| Role | Dark | Light |
| --- | --- | --- |
| Background | `#1F2430` | `#F5F2EA` |
| Surface | `#232834` | `#FFFCF5` |
| Primary action fill | `#FFCC65` | `#FFCC65` |
| Action text | `#302719` | `#302719` |
| Primary text | `#E2E3DE` | `#303849` |
| Secondary text | `#A4ADBD` | `#646C78` |
| Amber text/accent | `#FFCC65` | `#946000` |
| Syntax teal | `#56B6C2` | `#287681` |
| Added/next-step text | `#B8D58A` | `#52722E` |
| Selected surface | `#303643` | `#EAE6DC` |
| Divider | `#3D4555` | `#D6D2C8` |

Light mode uses warm paper and pale cream, with ink-colored text. Amber remains consistent on buttons; inline amber and teal are darkened for reading contrast. The grain overlays the base palette, so sampled rendered pixels can vary slightly.

## Component and interaction rules

- System sans for prose, SFMono/Menlo fallback for syntax and metadata. Display hierarchy uses 48/40/26 px in the board; native implementation must map to scalable text styles rather than copying fixed mockup dimensions.
- Custom spacing follows 4-point increments and content surfaces use 12-point radii. Native controls retain platform geometry. Mock device frames and pill navigation do not define a custom card radius.
- One dominant action per screen. Secondary assistance is explicit. Send sends; Finish is separate. A theme change preserves the draft.
- Start with static texture and short press feedback. Reduced motion disables the custom press transform. No idle AI animation.
- In native implementation, validate Dynamic Type, VoiceOver, reduced transparency, keyboard insets, focus order, and 44-point targets. Browser illustrations of controls are not native acceptance.

## Onboarding and trust

Welcome → focus and level → optional local input rehearsal → sign-in → invitation access → question preview → guided interview → feedback. Existing account access skips invitation redemption in the proposed production flow.

No anonymous AI evaluation is implied. The rehearsal stays local and is not automatically submitted as a practice answer. Account and invitation actions are simulated. The goal/level, rehearsal input, answer draft, and theme live in tab memory only. Questions, nudges, diagrams, and feedback are fixtures. Settings, Library, account errors, offline recovery, and real navigation are outside this mockup set.

## Verification

Browser inspection covers the paired boards, interactive feedback/Recall screens, and 390 × 844 mobile onboarding with reduced motion. The document and dialog have no horizontal overflow at that viewport. All six comparison screens render; computed dark palette tokens match the supplied samples. JavaScript syntax check passes and the browser reports no console errors or warnings. The local interaction check exercises goal and level selection, Back preserving setup and rehearsal input, simulated authentication/access, focus-specific question preview, empty-send guard, explicit nudge, draft retention across themes, Send, Finish, feedback, clean retry, Escape, Recall reveal, and Recall Back.

Selected contrast checks: dark secondary text on surface 6.52:1; dark teal on surface 6.22:1; light secondary text on background 4.74:1; light amber on background 4.77:1; light teal on surface 5.13:1; action text on amber fill 9.84:1. This is a scoped token check, not a complete accessibility audit.

No production app/backend code changed for this redesign. No native build, real account/AI request, expo-backdrop rendering, or physical-device verification was performed. The earlier Expo migration evaluation remains separate; `legacy/expo` stays archived.
