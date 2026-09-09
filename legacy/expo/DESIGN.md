# Drillbit Design Context

## Register

Product UI. Design serves repeated task flow, not brand expression.

## Scene

An engineer opens Drillbit during a focused practice block at a desk or from the phone after a widget tap. The interface should reduce friction, keep the current challenge centered, and avoid anything that feels like a marketing surface.

## Typography

- One family: system sans via the platform default stack.
- Use regular and semibold only in normal UI.
- Keep headings useful, not heroic.
- Body copy should stay readable at 65-75 characters where prose is long.

## Color Strategy

Restrained. Tinted neutral surfaces carry most of the interface, with a single blue accent for current selection, primary action, links, and focus rings.

Semantic tokens live in `global.css` and should be used through Uniwind/HeroUI token classes. Component files should not hardcode hex, RGB, HSL, or OKLCH values unless they are defining tokens.

## Shape And Layout

- Use the shared radius token for controls, fields, panels, chips, and sheets.
- Spacing follows the project 4px scale.
- Cards are allowed for repeated memory rows and focused panels, but avoid nested card stacks.
- Answer mode keeps one large writing surface as the visual anchor.
- Params should behave like a compact settings tool, not a landing page.
- Memory should summarize patterns before showing raw history.

## Components

- Main app screens use HeroUI Native with Uniwind classes.
- Widgets use `@expo/ui` primitives only.
- Use Lucide for custom icons when an icon is needed outside native tab symbols.
- Interactive elements need visible pressed/focus/disabled states.
- Loading states should reserve layout and show skeleton-like surfaces where practical, not just empty areas.

## Motion

Motion should communicate state: sheet entry, header collapse, list refresh, field feedback. Keep transitions around 150-250ms and avoid decorative choreography.

## Copy Rules

- Use sentence case for labels and short commands.
- Be specific about what a setting changes.
- Avoid restating a heading in its description.
- No em dashes.
