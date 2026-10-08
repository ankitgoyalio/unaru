# Implementing interface copy

Treat historical UI examples as illustrations. Consult current official Apple documentation when a task depends on present-day component behavior, APIs, or platform requirements.

Follow the project's existing string storage, localization, capitalization, and accessibility conventions. On Apple platforms, inspect the relevant String Catalog, strings resources, or source call sites used by the project. Preserve interpolation arguments, plural behavior, and string identity unless the task requires changing them. Account for affected translations through the existing workflow; an English edit does not establish translation quality.

Update related visible and accessibility copy within the requested scope. Surface a required interaction change explicitly.

Verify affected layouts and accessibility behavior when a running app or preview is available: larger text, long translations, reading order, and meaningful labels. Run relevant existing checks when the edits affect resources or behavior. If only source or screenshots are available, report the checks performed and the remaining runtime or language review, without claiming those checks passed.
