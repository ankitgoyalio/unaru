---
name: web-design
description: "Design or review web interfaces: semantic structure, keyboard interaction, forms, responsive layout, navigation, visual accessibility, or loading performance."
license: MIT
---

# Web design

1. Bound the task: name the journey, deliverable (design, implementation, or review), supported browsers, and evidence available. Preserve the project's component and visual contracts; use WCAG 2.2 Level AA unless another accessibility target is specified.
2. Load references for behavior being designed, changed, or inspected. Read only the matching sections; when a decision introduces another branch, load that branch before proceeding:

- Page structure, navigation, custom widgets, dialogs, focus, or announcements: [semantics and interaction](references/semantics-interaction.md).
- Data entry, validation, authentication, or multistep services: [forms and recovery](references/forms-recovery.md).
- Reflow, zoom, typography, touch targets, or localized layouts: [layout and content](references/layout-content.md).
- Contrast, themes, motion, or forced colors: [appearance and preferences](references/appearance-preferences.md).
- Loading speed, input latency, layout shifts, images, fonts, or rendering cost: [performance](references/performance.md).
- New platform features, JavaScript-dependent journeys, or requested installation/offline behavior: [enhancement and installation](references/enhancement-installation.md).

3. Resolve disputed claims with the [source hierarchy](references/sources.md). Report standards violations against the applicable criterion or specification; label design-system choices and informative guidance accordingly.
4. Account for each applicable rule within that task boundary: an implementation needs a verification result or untested limitation; a design needs an expected interaction and acceptance check; a static review needs artifact evidence and any remaining runtime check. For findings, connect the trigger, user impact, and correction to that evidence. Declared styles or attributes alone cannot establish computed target sizes, actual autofill, or measured performance. A scoped review or automated scan alone cannot establish WCAG conformance.
