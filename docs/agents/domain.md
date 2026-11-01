# Domain docs

This repo uses a single-context domain layout:

- `GLOSSARY.md` at the repo root defines domain terms.
- `docs/adr/` holds architectural decision records.

## Before exploring the codebase

Read `GLOSSARY.md` and the ADRs relevant to the area you will work in.

If these files do not exist, proceed silently.
The `domain-modeling` skill creates them when terms or decisions get resolved.

## Use the glossary's vocabulary

Use the glossary's terms when naming domain concepts in issues,
proposals, code, and tests.

If a term is missing, check whether the concept belongs in the project.
Record a real vocabulary gap for `domain-modeling`.

## Identify ADR conflicts

If a proposal contradicts an ADR, name the ADR and explain why
the decision needs reconsideration.
