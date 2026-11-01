# Security

Unaru is in development. Security fixes target the current `main` branch.
There is no production security qualification or support commitment for older revisions.

## Report a vulnerability

Use [GitHub's private vulnerability reporting form](https://github.com/ankitgoyalio/unaru/security/advisories/new).
Include the affected revision, reproduction steps, expected impact, and sanitized
logs or examples. Keep suspected vulnerabilities out of public issues until the
maintainer has assessed them and coordinated a fix.

Never include API secrets, access tokens, credentials, or identifiable account data
in a report. If a credential was exposed, revoke or rotate it through its issuer.

## Automated checks

Secret scanning, push protection, dependency alerts, and Dependabot security
updates are enabled. CodeQL scans GitHub Actions and Python on pull requests,
pushes to `main`, and a weekly schedule. CI also runs actionlint.

Swift CodeQL scanning is deferred because the published compiler support matrix
ends at Swift 6.3 and this project requires Swift 6.4. Revisit that limit when
updating CodeQL. Passing automated checks does not establish production safety.
