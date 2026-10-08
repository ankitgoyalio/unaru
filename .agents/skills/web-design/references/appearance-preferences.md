# Appearance and preferences

## Contrast and themes

Verify actual foreground/background pairs, including hover, focus, selected, and error states. WCAG 1.4.3 requires 4.5:1 for normal text and 3:1 for large text (at least 18pt, or 14pt bold), subject to its exceptions. WCAG 1.4.11 requires 3:1 for visual information needed to identify controls/states and understand graphics against adjacent colors, subject to its exceptions; decorative borders are not universally required to reach 3:1. Pair status colors with text, shape, or another perceivable cue.

Use the project's theme tokens. When dark appearance is supported, check each supported theme and honor the product's override/system-preference behavior. Declare only the schemes actually rendered with `color-scheme` so native controls match. A universal theme toggle is not an accessibility requirement.

Test [forced colors](https://developer.mozilla.org/en-US/docs/Web/CSS/Reference/At-rules/@media/forced-colors) with `@media (forced-colors: active)`: box shadows and background images may disappear, so controls and focus may need borders/outlines and system colors. `prefers-contrast: forced` is not a valid media value; `prefers-contrast: more` addresses a different preference. Retain browser color adjustment except where preserving a specific meaning requires a narrow override. Preference definitions are in [Media Queries Level 5](https://www.w3.org/TR/mediaqueries-5/).

## Motion and changing content

For motion, provide a [reduced-motion](https://developer.mozilla.org/en-US/docs/Web/CSS/Reference/At-rules/@media/prefers-reduced-motion) path that removes nonessential movement while preserving final state and usable controls. Implement it at the animated component rather than blindly shortening all animation durations, which can break completion events or state sequencing.

Automatically moving content lasting over five seconds alongside other content needs the applicable pause/stop/hide mechanism (WCAG 2.2.2). Apply the flash threshold in 2.3.1; avoid flashing as the simplest safe design. Disabling nonessential interaction-triggered animation is **AAA 2.3.3**, distinguishable from the AA baseline. A reduced-motion query alone does not satisfy every moving-content criterion.

Check state recognition and readable content in each supported theme and relevant preference mode. For animation rendering cost, consult [performance](performance.md#rendering-and-interaction).
