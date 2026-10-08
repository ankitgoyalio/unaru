# Semantics and interaction

## Structure and names

Use native links for navigation and buttons for actions, preserving browser opening, copying, and keyboard behavior. Give non-submit buttons inside forms `type="button"`. Structure the content with meaningful headings, landmarks, lists, and tables; choose heading levels by nesting rather than font size. Provide a way to bypass repeated navigation, such as a working skip link. Name multiple navigation landmarks distinctly and mark the active page with `aria-current="page"`.

An interactive element's accessible name includes its visible label (WCAG 2.5.3). For an icon-only control, supply an action name and hide decorative icon content. Informative images need a contextual alternative, decorative images an empty alternative, and complex graphics an equivalent detailed explanation. Media needs the applicable caption and audio-description alternatives (WCAG 1.2).

## Widgets and focus

Choose a native element or an established project component before creating an ARIA widget. For a custom tablist, combobox, menu, grid, or tree, read the corresponding [APG pattern](https://www.w3.org/WAI/ARIA/apg/patterns/) for its keyboard and focus model. Composite widgets often have one Tab stop and arrow-key navigation; making every child tabbable changes that model. Ordinary site navigation remains links rather than an application menu.

For a modal, use the platform's modal behavior (`dialog.showModal()` where supported), give it a name, place initial focus to suit its content, keep background interaction unavailable, and restore focus to the opener or a logical successor. Verify Escape, a visible close action, and focus through changing content or unavailable controls. See [HTML dialog](https://html.spec.whatwg.org/multipage/interactive-elements.html#the-dialog-element) and [APG modal guidance](https://www.w3.org/WAI/ARIA/apg/patterns/dialog-modal/).

Keep focus order aligned with reading order. Keyboard focus must be visible and not entirely hidden by author-created sticky content (WCAG 2.4.7, 2.4.11). The two-CSS-pixel perimeter area and 3:1 change-of-contrast requirement belongs to **AAA 2.4.13**, not the AA baseline.

## Navigation and updates

For client-side routing, test direct URLs, refresh, Back/Forward, document title, focus placement, and scroll restoration; retain the router/browser defaults unless demonstrated behavior needs correction. Put shareable navigation state in URLs while keeping sensitive or transient editing state elsewhere.

Announce relevant status messages without moving focus (WCAG 4.1.3), typically with `role="status"`. Reserve assertive alerts for urgent information; announcing every DOM update overwhelms the task.
