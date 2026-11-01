# Documentation

- [Development](../docs/development.md) covers toolchain setup and local checks.
- [DocC](DocC.md) covers catalogs, coverage, compiled examples, and static builds.
- [Pages](Pages.md) covers publication and live verification.

Keep consumer guidance and reproducible instructions in Git. Record decisions in
`docs/adr/` and implementation discussion in the relevant GitHub issue or PR.
Keep logs, result bundles, generated sites, and execution reports in ignored
`.test-results/` or CI artifacts.

DocC catalogs are the source of module documentation. Update them with the code.
Every authored declaration in the selected documentation scope needs a comment.
Shared documents public declarations. Backend and the app also document internal
declarations. Dependency symbols and tests are outside that scope.

Tooling was adapted from `ankitgoyalio/swiftkiteconnect` at
`b210694a48fb065ff7d96d418b9e05e5beaa5c84`, under the repository's MIT license.
