# Drillbit direction studies

Status: exploratory design proposal, 22 September 2026. No framework, navigation, API, or persistence migration has been approved or implemented by this study. Existing implementation decisions remain in [architecture.md](../architecture.md).

## Review artifacts

- [Nine-screen comparison and clickable onboarding](direction-studies.html): self-contained HTML, no dependencies or remote assets. Open directly in a browser, or serve this directory locally. Includes Precision, Studio, and Depth versions of Welcome, Home, and Interview, plus a seven-stage storyboard and eight-screen prototype.
- [Figma draft](https://www.figma.com/design/kpoYsnLG4GGc5dgRJCXIlV): **incomplete**. The Starter-plan MCP limit interrupted composition. Contains exploratory tokens, three Welcome studies, partial Home studies, and unfinished Interview frames. Use the HTML as the complete review artifact. Do not treat the Figma draft as a handoff-ready library.
- Browser screenshots live in `output/playwright/drillbit-design/`: `precision.png`, `studio.png`, `depth.png`, `onboarding.png`, and prototype checkpoints.

The HTML is editable source. Browser controls and SVG icons illustrate native intent; they are not a verified reproduction of iOS controls or the expo-backdrop renderer.

## Product brief

Audience: software engineers preparing for interviews or building a deliberate practice habit. The first session should make the product's teaching value understandable without configuration overhead.

Promise: **Practice a difficult conversation, understand what to improve, and return with a clear next step.**

Premium means readable hierarchy, specific feedback, a predictable interaction model, and recovery that respects the learner's work. AI is expressed through the quality and provenance of an observation. Its repeated visual signature is **quote → observation → next action**.

## The comparison

All three directions use the same screen responsibilities, content, actions, and Home / Recall / Library navigation. The comparison intentionally changes visual treatment without changing the product proposition.

| Direction | Background / surface | Primary / secondary text | Accent / accent surface | Character and tradeoff |
| --- | --- | --- | --- | --- |
| Precision | `#F6F8FB` / `#FFFFFF` | `#152337` / `#59677B` | `#285ED4` / `#EAF0FC` | Crisp hierarchy and restrained blue. Strongest starting point for clarity; identity relies on typography and evidence rather than decoration. |
| Studio | `#F3F6F3` / `#FFFFFF` | `#233C38` / `#556B65` | `#306F63` / `#E3ECE5` | Softer rounded headings and tonal groups. Approachable, with less visual urgency. |
| Depth | `#111923` / `#1C2835` | `#F0F4F8` / `#ABB9C9` | `#A9C9FF` / `#283C55` | Dark tonal layers and translucent navigation. Material requires opaque fallbacks and device performance checks. |

Initial recommendation: Precision's hierarchy with selected Depth-style navigation treatments. This is a review recommendation, not a selected direction. Depth is a visual-direction sample, not the completed dark theme for Precision; the chosen direction will need its own paired light and dark themes.

## Shared design rules

- System type. Display 36/40, screen heading 28/32, content heading 24/29, body 17/25, supporting text 15/22. Native implementation maps these roles to scalable platform text styles; fixed browser sizes are mockup dimensions.
- Custom spacing in 4-point increments; 24-point screen gutters and 12-point custom surface radii. Native controls retain platform geometry. Phone masks and pill controls are not custom card-radius precedents.
- One dominant action per screen. Home prioritizes the next practice, then Recall. Advanced preparation stays behind a deliberate action.
- Interview keeps the question reference, conversation, and composer distinct. Send always sends; Finish is a separate action. Assistance is explicit.
- Name actions plainly. Remove the current mixed “boss fight” framing from this proposed direction. Avoid artificial mastery scores and unsupported performance claims.
- Motion should communicate an actual transition. Start with short 140–220 ms transitions; preserve reduced-motion alternatives. No idle AI animation is needed.
- Materials belong at navigation and scroll boundaries. Content must remain readable when blur and transparency are disabled. Browser CSS blur is illustrative only.
- Every interactive target must reach at least 44 points in native implementation. Large text, keyboard insets, contrast, VoiceOver reading order, and reduced transparency remain device acceptance work.

## Proposed onboarding and trust boundaries

1. **Welcome:** one promise and labelled illustrative feedback replace the four-page product introduction. Existing users can sign in directly.
2. **Goal and level:** choose practice focus and current level. An unsure level is allowed. Defer detailed weak areas, schedule, reminders, and interview date until relevant.
3. **Local input preview:** a short prompt lets the learner try typing or system keyboard dictation. Skip is allowed. Do not evaluate it, send it to an AI provider, or imply that it received personalized feedback.
4. **Authentication:** use system provider flows. Preserve pending goal, level, and preview when returning. Do not submit the preview as an actual practice answer without a separate explicit action.
5. **Invitation access:** authenticated accounts with access skip this stage. Otherwise redeem an invite. Invalid, consumed, and unavailable states retain setup and offer clear retry/recovery.
6. **Question preview and first session:** generate only after confirmed account access, preserve the existing bounded generation rules, and show the question before starting. Match focus and level; the initial session is guided.
7. **Feedback and return:** show a quote from the submitted answer, a grounded observation, and a focused next action. Offer retry, Recall, or completion without making feedback availability block session completion.

Prototype scope: the goal/level selection, local text entry, provider/access transitions, writing, an illustrative nudge, explicit finish, feedback, retry, direction switching, and Back are interactive. Authentication, invitations, questions, and feedback are fixtures. The two practice-focus choices use illustrative question variants; they are not a curriculum implementation. Settings, Recall detail, and Library detail are intentionally outside this mockup set. All entered text lives in tab memory; there is no persistence or external request.

## Verification

- Browser-rendered and visually inspected all three direction boards and mobile onboarding at 390 × 844.
- Completed the interactive journey: goal/level selection, Back preserving setup and preview, simulated authentication and invitation access, focus-specific question preview, empty-send guard, explicit nudge, draft preservation across direction changes, explicit completion, illustrative feedback, and a fresh retry.
- Confirmed nine comparison screens, no document horizontal overflow at 390 pixels, and Escape dismissing the prototype dialog. Exercised the narrow layout with reduced motion enabled.
- Measured selected text/button contrast pairs. Precision secondary text on background: 5.41:1; button text: 5.77:1. Depth secondary text on surface: 7.49:1; button text: 9.45:1. Studio secondary text was darkened from `#596F69` to `#556B65`, improving its tonal-surface contrast from 4.46:1 to 4.73:1. This is a scoped contrast check, not a full accessibility audit.
- Only design artifacts were added. No production tests, native compilation, live-service validation, or physical-device validation were required or performed for these mockups.

## Next design gate

Select the direction using the three screens together: first-use trust, daily action clarity, and long-form readability. Then extend the selected system to Recall, Library, settings, and recoverable loading/error/offline/conflict states. Validate paired light/dark themes, larger text, keyboard-visible layouts, and opaque material fallbacks before calling the design implementation-ready.

The subsequent Expo evaluation should be one isolated first-session journey against the current backend. Preserve contracts and account scope. Explicitly assess local-draft and outbox migration, conflict recovery, credentials, authentication redirects, voice/native integrations, reminders, and widgets before replacing the SwiftUI client. Keep `legacy/expo` as reference.

`expo-backdrop` remains a candidate material adapter. Its documented requirements include a development build, no Expo Go or web support, and Android 12+ for Gaussian child blur. Pin and test the actual dependency before adoption. Source: [repository documentation](https://github.com/rit3zh/expo-backdrop).
