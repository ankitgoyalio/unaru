---
name: pull-request-message
description: Draft or revise PR and MR bodies with a visual summary, concrete evidence, and merge risk. Use when the user asks for a pull request or merge request message, description, summary, or template content.
---

# Pull Request Message

Use this structure for the PR or MR body:

```markdown
## Summary

<compact visual and a brief explanation of the change>

## Evidence

- **Before:** <observed behavior or available baseline>
  **After:** <verified result>

## Merge Danger

**Door:** <one-way or two-way>

<reason and practical rollback constraints, if needed>

**Blast Radius:** <short scope label>

<affected users or systems and concrete failure modes, if needed>
```

## Gather the change

Use the user's intent, issue context, and supplied diff as evidence. In a Git worktree, inspect the repository template and compare the complete branch against its intended base. Distinguish committed changes from uncommitted work that would not be included. Cover every material change without a file-by-file inventory.

Ask a focused question only when missing context would make the description misleading. Drafting a body does not authorize creating, updating, or merging a PR or MR.

## Summary

Choose a compact representation suited to the change:

- Pseudocode for algorithms; call trees for execution order.
- Component trees for UI ownership and state; shallow file trees for responsibility changes.
- Mermaid for interactions or data flow; a diff sketch for an existing structure's changes.
- A complete code block when the new shape needs surrounding context.

Pair the visual with a short explanation. Use repository terminology, including `GLOSSARY.md` when available.

## Evidence

Prefer before/after screenshots for visible changes and executed tests or output for behavior. Identify the check and its outcome.

Never invent screenshots, test execution, or results. Label illustrative pseudocode as illustrative. If a baseline or verification is unavailable, say so; do not present an expected result as observed evidence.

## Merge Danger

Classify reversibility: two-way means a practical rollback exists; one-way means effects cannot readily be undone. Note data loss or migration constraints where relevant.

Describe the affected scope and plausible consequences, such as consumer breakage or responsive layout regressions. Ground risk claims in the actual diff.

## Deliver

Return ready-to-paste Markdown without preamble. Honor repository-required template fields; otherwise use the structure above. Provide a title only when requested.

Adapted from [Matt Pocock's PR skill](https://github.com/mattpocock/skills/blob/main/skills/engineering/pr/SKILL.md), which credits [Dex Horthy's show-me skill](https://github.com/humanlayer/skills/blob/main/plugins/show-me/skills/show-me/SKILL.md).
