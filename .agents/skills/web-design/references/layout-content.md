# Layout and content

## Reflow and readable text

Build breakpoints around content failure, or use container queries when a reusable component depends on its allocated space. Keep source order meaningful as columns change. See [web.dev media queries](https://web.dev/learn/design/media-queries).

Allow browser zoom through the viewport configuration. Verify text resizing to 200% (WCAG 1.4.4) and reflow at 320 CSS pixels for vertically scrolling content, equivalent to a 1280-pixel viewport at 400% zoom (1.4.10). Isolate genuinely two-dimensional content such as data tables or maps rather than hiding overflow or truncating the page to pass. Relative font units help respect user settings; CSS pixels themselves do not disable browser zoom. Test fluid typography's zoom behavior instead of relying on viewport units alone.

WCAG 1.4.12 requires content to survive user overrides of line height 1.5 times the font size, paragraph spacing 2 times, letter spacing 0.12 times, and word spacing 0.16 times. These are **override test values**, not mandatory default typography. Select line length and font scale from the project's content and design system. Check clipping in buttons, headings, and error text as well as paragraphs.

## Pointer and hover

WCAG 2.5.8 AA requires targets at least 24 by 24 CSS pixels **or an applicable exception**. For its spacing exception, centered 24-pixel-diameter circles around undersized targets must intersect neither another target nor another such circle. Inline links, equivalent controls, unmodified browser controls, and essential presentation have defined exceptions. Larger targets can improve usability; 44 by 44 is the enhanced AAA criterion, not a universal AA minimum or a blanket rule for inline links.

Provide a single-pointer alternative to dragging (2.5.7) and alternatives to multipoint/path gestures (2.5.1) where required. Keep scrolling and pinch zoom available; constrain `touch-action` only for the gesture the component actually handles. Supplemental hover/focus content must be dismissible, hoverable, and persistent subject to 1.4.13 exceptions. Essential actions also need an explicit touch/keyboard route.

## Language and direction

Set the page language and mark language changes. Use known `dir` values for localized interfaces and `dir="auto"` for unknown-direction user content. Use [CSS logical properties](https://www.w3.org/TR/css-logical-1/) for layout relationships that follow writing direction. Mirror directional navigation where its meaning changes; preserve media, logos, and unrelated symbols. Test long translations, RTL mixed with LTR identifiers, and localized errors.

Format dates, numbers, and lists through the project's localization layer or `Intl`, supplying the applicable locale, currency, and time zone. Keep interface text available as text rather than embedding it in imagery.
