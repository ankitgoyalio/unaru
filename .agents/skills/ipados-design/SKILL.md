---
name: ipados-design
description: Design or review iPad interfaces for resizable windows, adaptive navigation, menu commands, keyboard and pointer input, Pencil, accessibility, or content transfer.
license: MIT
---

# iPadOS design

1. Bound the review or design to the requested interaction and supported OS range. For code changes, inspect the framework, SDK, and deployment target; check API availability separately from visual guidance.
2. Load only the references triggered by that interaction:

- Resizing, multitasking, navigation, presentations, or external displays: [layout and windows](references/layout-windows-navigation.md).
- Menus, keyboard, pointer, or selection: [commands and input](references/commands-input.md).
- Drawing, handwriting, or Pencil gestures: [Pencil](references/pencil.md).
- Drag/drop or cross-app content transfer: [content transfer](references/content-transfer.md).
- Materials, colors, symbols, or animation: [appearance](references/appearance.md).
- Text, controls, navigation, focus, or accessible media: [accessibility](references/accessibility.md).

3. For behavior newer than the [source refresh](references/sources.md), or an implementation symbol not covered here, fetch its Apple page with `sosumi fetch <Apple URL>` and verify the supported OS and API availability.
4. Check the failure conditions for the affected interaction: narrow/wide windows and rotation for layout, independent state for multiple windows, touch and keyboard paths for commands, pointer behavior for custom controls, enlarged text and assistive activation for controls, and disconnect recovery for external displays. For an artifact review, cite the code or visible behavior supporting each finding; for a design, specify the expected outcome in each applicable condition. For a running implementation, exercise those conditions and record results; label unavailable runtime checks untested. Finish when every affected interaction has a supported decision or a finding with its trigger, user impact, and correction.
