# Drillbit / Mirage, refined

Study 03 · 23 September 2026. Current artifact: [paired screens and interactive flow](direction-studies.html). Browser prototype only; no native implementation, backend change, or framework migration.

## What changed

- **Dark:** preserve the original `#1F2430` foundation, lift surfaces to `#282F3D`, soften amber, and replace competing teal accents with a restrained slate-blue. Cool structural colors support one warm focal accent.
- **Light:** replace cream with cool white and pale blue-gray. Slate carries primary controls; amber identifies the key idea. The light theme has its own contrast roles rather than inverted dark values.
- **Identity:** one app mark in both themes, `#FFCC65` on a `#232834` tile. Theme-specific text accents never recolor it.
- **Welcome:** an interactive retry sketch replaces code rows. “First instinct” produces two receipts; “Refined” reuses one key and produces one. This is a labelled illustration, not personalized feedback.
- **Home:** one open practice canvas, a diagram integrated with the topic, and a circular launch control. Recall is a single typographic count/link; stacked cards are removed.
- **Interview:** the question leads, the previous thought is disclosed on demand, and the composer occupies the bottom surface. Remove the duplicate explanatory card and redundant metadata.
- **Setup and feedback:** focus choices sit side by side; the question preview loses its extra guidance card; feedback uses a concise inline annotation.

## Palette

| Role | Dark | Light |
| --- | --- | --- |
| Background | `#1F2430` | `#F2F5F9` |
| Surface | `#282F3D` | `#FFFFFF` |
| Primary text | `#E5E7EB` | `#263345` |
| Secondary text | `#A5AFBF` | `#596A80` |
| Text accent | `#F4C46B` | `#855900` |
| Action fill | `#F4C46B` | `#293B52` |
| Action text | `#282719` | `#FFFFFF` |
| Syntax/supporting accent | `#A8BCD1` | `#435F7D` |
| Diagram path | `#E4B865` | `#9B690B` |
| Selected surface | `#303A4A` | `#E3EAF2` |
| Divider | `#404C5E` | `#C5CFDD` |
| Added/next-step text | `#B3C99F` | `#466333` |
| App mark / tile | `#FFCC65` / `#232834` | identical |

The original editor samples are the starting point, not a constraint to reproduce every pixel in this refinement. The earlier settings provenance is recorded in [study 02 notes](README-v2.md). The subtle static grain changes individual rendered pixels slightly.

## Design rules

System sans carries questions and actions; SFMono/Menlo carries code and compact metadata. An explicit branching-and-merging path is the signature device: it explains retries rather than decorating the UI. Monospace is reserved for the subject's technical vocabulary.

Use open space before adding a container. Show secondary context on demand. Each screen has one dominant action; Send and Finish remain separate. Native controls and accessibility requirements take precedence over illustrated browser geometry. Custom spacing follows 4-point increments and content surfaces use 12-point radii; marks, diagram nodes, and circular controls have their own geometry.

Texture is static, local, and subtle. Reduced transparency removes grain and blur. Reduced motion removes custom press scaling. Native Dynamic Type, VoiceOver, keyboard insets, focus order, and actual native controls remain acceptance work.

## Prototype boundaries

Welcome → focus and level → optional local rehearsal → simulated sign-in → simulated invitation → question preview → guided interview → example feedback. Recall is accessible from Home.

The retry comparison, context disclosure, goal/level selection, input rehearsal, answer draft, help, theme switch, Send, Finish, retry, and Recall reveal are interactive. Typed content stays in tab memory. Authentication, account access, questions, and AI responses are fixtures. Feedback is explicitly an example and does not evaluate the user's submitted text. Settings, Library, persistence, generation, and failure recovery are outside this mockup set.

## Verification

Visually inspected paired boards at desktop size and Welcome, focus selection, and Interview at 390 × 844 with reduced motion. No document or dialog horizontal overflow; no browser console errors or warnings. Exercised the retry comparison, context disclosure, onboarding, setup/input retention through Back, focus-specific question preview, empty-send guard, nudge, draft retention through theme change, Send, Finish, feedback, clean retry, Recall reveal/Back, and Escape. Computed mark colors are identical across themes.

Selected contrast ratios: dark secondary text on surface 6.06:1; dark action 9.29:1; light secondary text on background 5.06:1; light text accent 5.61:1; light action 11.40:1; shared app mark 9.88:1. Light diagram paths measure 4.35:1 against the background; diagram text uses the secondary text role. These are scoped token checks, not a full accessibility audit.

Screenshots are in `output/playwright/drillbit-design/`, prefixed `refined-`. No native build, expo-backdrop rendering, live AI/account call, or physical-device verification was performed. Existing implementation decisions remain in [architecture.md](../architecture.md); `legacy/expo` remains archived.

## Files and history

Current source: `direction-studies.html`, `study-base.css`, `mirage.css`, `refinement.css`, and `mirage.js`. All assets are local. Serve the directory, or open the HTML with its sibling files present.

[Study 02](direction-studies-v2.html) preserves the previous Mirage direction. [Study 01](direction-studies-v1.html) preserves the initial comparison. The [earlier Figma draft](https://www.figma.com/design/kpoYsnLG4GGc5dgRJCXIlV) remains incomplete and predates Mirage; it has not been updated.
