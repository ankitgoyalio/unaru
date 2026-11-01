# Contribute to Unaru

Read the [development guide](docs/development.md) for the toolchain, commit hook,
and validation commands. Follow the [documentation policy](Documentation/README.md)
when adding or moving documentation.

Create a branch and open a pull request against `main`. Keep each pull request
focused on one change. Explain the resulting behavior and record the checks you
ran. Include screenshots for visible interface changes.

Before committing, run SwiftFormat and the checks relevant to your changes.
Keep generated DocC examples synchronized with their catalogs. Use Conventional
Commits for commit messages and pull request titles.

Merges use squash commits. Required checks must pass against the current base,
and review conversations must be resolved. Human approval is optional while the
repository has one maintainer. The `main` ruleset applies to administrators too.

Report bugs and propose features through
[GitHub Issues](https://github.com/ankitgoyalio/unaru/issues).
Use the [security reporting process](SECURITY.md) for suspected vulnerabilities.
