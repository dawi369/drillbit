# Application Design System Guide

**Single source of truth for consistent, professional UI across web, mobile & hybrid apps**

This document defines the non-negotiable rules for typography, spacing, color, components and micro-details.  
All agents, developers and designers working on the product **must** follow these rules without exception.

Goal: Create interfaces that feel intentional, trustworthy and premium from the first glance — regardless of platform (web, React Native, Flutter, native iOS/Android, Electron, etc.).

---

## 1. Typography

**Rule:** One primary typeface family used application-wide. Maximum two weights in regular UI.

**Recommended choices by product type (pick once, never change):**

- SaaS / productivity / developer tools  
  → Inter, Geist, IBM Plex Sans, Manrope

- Consumer / social / lifestyle apps  
  → Plus Jakarta Sans, DM Sans, Poppins, Sora

- Finance, legal, enterprise, high-trust products  
  → Neue Haas Grotesk, GT America, Helvetica Now, Arial (when forced), Inter (heaviest weight for authority)

**Implementation notes:**

- Use Regular (400) + one emphasis weight (500/600 only)
- Avoid Light (300), ExtraBold (800+), Black in body/UI text
- Headlines may use Semibold or the heavier weight — never a different family
- System fallbacks must be included (system-ui, -apple-system, BlinkMacSystemFont, etc.)
- Never mix serif and sans-serif in the same product
- Letter-spacing: use default or very subtle tracking (+0–50 for headlines only)

---

## 2. Spacing & Layout Grid

**Rule:** Strict 4px increments. No exceptions.

Allowed values (in pixels or rem equivalents):  
4, 8, 12, 16, 20, 24, 28, 32, 40, 48, 56, 64, 80, 96, 128

**Usage pattern:**

- Component padding → 12–24 px most common
- Element gaps (flex/grid) → 8, 12, 16 px
- Section / card spacing → 24, 32, 48 px
- Page / screen margins → 16–32 px (responsive)
- Form field vertical rhythm → 20–24 px between label + input

Never use: 10px, 15px, 18px, 22px, 25px, 30px, 35px, arbitrary values

---

## 3. Color System – Semantic Tokens Only

**Rule:** No hex/rgb/hsl codes written directly in component files.  
All colors come from a central semantic token set.

**Required minimum semantic tokens:**

- background page / screen background
- surface cards, sheets, modals, elevated panels
- surface-subtle slightly different panels / zebra striping
- border all 1px borders & dividers
- text-primary body text, high-contrast
- text-secondary secondary labels, captions, icons
- text-tertiary very muted (placeholders, disabled)
- primary main CTA, links, selected states
- primary-hover hover/active state of primary
- primary-muted disabled primary, subtle accents
- destructive delete, error, warning actions
- success success states (if used)

**Implementation approaches (pick one):**

- CSS variables + Tailwind (most common for web)
- Design tokens JSON + style-dictionary
- Theme provider with native color scheme support
- Dark mode variants auto-generated from same tokens

Never hardcode brand colors per component.

---

## 4. Component & Interaction Rules

**Core consistency checklist – apply to every interactive element:**

1. **Border radius**  
   One value only: 6px, 8px, 10px or 12px  
   Applies to: buttons, cards, inputs, chips, modals, popovers, avatars  
   No mixing round + square corners in same screen

2. **Elevation / Shadow**
   - Cards / surface: single subtle shadow (small offset + low opacity)
   - Modals / drawers / floating panels: stronger shadow
   - Hover lift: optional very subtle scale(1.01–1.02) + shadow increase
   - Pressed state: subtle inset shadow or background darken

3. **Interactive states (every clickable element must have):**
   - hover → background / border / scale change
   - active / pressed → stronger feedback (darker/lighter + inset if possible)
   - focus → visible ring matching primary color (2–3px, 50% opacity)
   - disabled → 40–60% opacity + cursor-not-allowed

4. **Input / control sizing**  
   All buttons, inputs, selects, chips in the same context **must** share the same height  
   Most common comfortable sizes: 36–40px (dense), 44–48px (comfortable)

5. **Icon system**  
   One icon set only (Lucide, Heroicons, Feather, Phosphor, etc.)  
   Consistent size: 16px, 20px or 24px depending on context  
   Stroke width usually 1.8–2.2

---

## 5. Platform-agnostic Micro-decisions

- Loading states → always show skeleton / shimmer, never empty containers
- Errors → red text + icon below field (never inline red border only)
- Success feedback → green check / toast (transient)
- Links → always underlined on hover (web), or subtle color change (mobile)
- Avatars → consistent fallback color or initials
- Tables → zebra striping optional, but row hover mandatory
- Cards → consistent internal padding, never cramped
- Typography rhythm → line-height 1.4–1.6 for body text

---

## Final Acceptance Checklist (run before merge / publish)

- [ ] Single typeface family + max 2 weights used
- [ ] Spacing values belong to 4px scale only
- [ ] All colors come from semantic token set
- [ ] Uniform border-radius across components
- [ ] Every interactive element has hover + focus + active states
- [ ] Consistent control heights in the same context
- [ ] Single icon library & size convention
- [ ] Shadows used for hierarchy, not decoration
- [ ] No inline style overrides that break tokens

---
