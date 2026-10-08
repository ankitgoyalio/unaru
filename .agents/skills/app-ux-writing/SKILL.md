---
name: app-ux-writing
description: "UX writing for app screens and flows, control and feature naming, voice and tone, shared terminology, and source-string implementation. Use for drafting or reviewing interface language; Apple platforms first. Excludes marketing copy and standalone product or company naming."
---

# App UX Writing

## 1. Ground the copy

Inspect the requested element in context: nearby controls for a label; entry, decisions, states, and outcome for a flow. Establish the audience, intended action, and actual behavior from supplied requirements or implementation. Read applicable writing guidance and `WORD_LIST.md` in the project root or app documentation; otherwise use established UI terms.

Before drafting, account for facts that affect the choice or next action: deletion scope, retained access, timing, permissions, privacy, and recovery. Mark each unresolved fact and keep dependent wording provisional. A desired feeling of security cannot substantiate an encryption or privacy promise.

This step is complete when the requested elements, relevant states, established terms, and factual gaps are identified. A one-label task needs only its immediate context.

## 2. Take the relevant branches

Read each reference whose condition applies, then use its decisions in the requested copy:

- **Interface element or flow:** [Interface patterns](references/interface-patterns.md), the sections for the affected headings, choices, errors, alerts, empty states, notifications, or progress. Use **Flow and hierarchy (PACE)** when timing or information hierarchy is involved. Read **Accessibility and localization** for visible or spoken copy.
- **New or changed voice, or a tone mismatch:** [Voice and tone](references/voice-and-tone.md). Finish with observable writing choices and examples tested in the affected moments; routine copy reuses the documented voice.
- **New or changed feature, destination, setting, plan, or control name:** [Naming](references/naming.md). Finish with a recommendation tested in actual UI language and its material tradeoffs. An established action label needs only the contextual check.
- **Establishing or changing shared terminology:** [Terminology](references/terminology.md). Finish with the applicable word-list entry or a proposed entry, and reconcile related uses within scope.
- **Editing source strings or resources:** [Implementation](references/implementation.md), before editing. Finish with affected resource and accessibility uses accounted for, verification performed, and remaining runtime or language checks identified.

For source attribution or deeper research, use the [WWDC inventory](references/wwdc-sources.md).

## 3. Check and deliver

Read headings and actions alone, then the full copy and adjacent steps aloud. Verify that a person scanning can predict the action, that the sequence distinguishes pending from complete, and that each promise matches established behavior. Remove filler and duplicated meaning while retaining behavioral modifiers, informed-choice and recovery details, and terminology repetition that resolves ambiguity. Keep personality when it serves the moment.

Deliver ready-to-use copy located by screen, state, and element. For a review, pair each changed passage with the current wording and the effect on understanding, choice, or recovery. Include placement or timing changes when wording alone cannot solve the problem. Identify unresolved facts separately from copy fixes.

Finish when every requested element and relevant state has copy or an explicit factual blocker, related terminology agrees, and the applicable branch checks are met.
