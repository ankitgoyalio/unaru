---
name: macos-design
description: Design or review Mac interfaces for menu commands, windows, toolbars, keyboard and pointer input, accessibility, appearance, or system integration.
license: MIT
---

# macOS design

1. Bound the review or design to the requested interaction and supported OS range. For code changes, inspect the framework, SDK, and deployment target; check API availability separately from visual guidance.
2. Load only the references triggered by that interaction:

- Menus, toolbars, sidebars, keyboard, or pointer: [commands and navigation](references/commands-navigation.md).
- Window lifecycle, documents, panels, or presentations: [windows and presentation](references/windows-presentation.md).
- Materials, colors, symbols, or animation: [appearance](references/appearance.md).
- Text, controls, navigation, focus, or accessible media: [accessibility](references/accessibility.md).
- Finder, Dock, search, sharing, notifications, or automation: [system integration](references/system-integration.md).

3. For behavior newer than the [source refresh](references/sources.md), or an implementation symbol not covered here, fetch its Apple page with `sosumi fetch <Apple URL>` and verify the supported OS and API availability.
4. Check the failure conditions for the affected interaction: minimum window size for layout, active/inactive appearance for custom chrome, keyboard and VoiceOver paths for commands/presentations, enlarged text for content, and independent/restored state for document or window changes. For an artifact review, cite the code or visible behavior supporting each finding; for a design, specify the expected outcome in each applicable condition. For a running implementation, exercise those conditions and record results; label unavailable runtime checks untested. Finish when every affected interaction has a supported decision or a finding with its trigger, user impact, and correction.
