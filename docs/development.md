# Development

Use Swift 6.4 and Xcode 27.2 for Apple builds. `.swift-version` selects Swift 6.4.2
for standalone tools and Linux CI. Newer 6.4 patches are accepted. The Xcode
project uses Swift 6 language mode. Shared and Backend require macOS 15 or later.
The app supports iOS 18, macOS 15, and visionOS 2 or later.

## Set up tools

Install Nick Lockwood's SwiftFormat 0.64.5, the latest release when this setup was
added. The toolchain's `swift format` is a different formatter. All contributors
and CI use the exact pinned version.

Run these commands from the repository root:

```fish
swiftformat --version
python3 Scripts/check-development.py
git config core.hooksPath .githooks
```

If full Xcode is not selected, set `DEVELOPER_DIR` to the Xcode 27.2 installation
before running checks. The preflight reports the selected tools and rejects an
incompatible compiler, Xcode version, or formatter.

## Run checks

```fish
swiftformat . --lint --config .swiftformat
python3 -m unittest discover -s Tests/Hooks -p 'test_*.py'
python3 -m unittest discover -s Tests/Documentation -p 'test_*.py'
python3 Scripts/check-documentation.py
python3 Scripts/check-documentation-examples.py
swift test --package-path packages/Shared
swift test --package-path backend
xcodebuild build-for-testing -project apps/unaru/unaru.xcodeproj -scheme unaru -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO
xcodebuild build-for-testing -project apps/unaru/unaru.xcodeproj -scheme unaru -destination 'generic/platform=visionOS Simulator' CODE_SIGNING_ALLOWED=NO
xcodebuild test -project apps/unaru/unaru.xcodeproj -scheme unaru -destination 'platform=macOS' CODE_SIGN_IDENTITY=- -only-testing:unaruUITests
python3 Scripts/build-documentation.py
```

Linux CI runs the Shared and Backend suites with Swift 6.4.2. Apple CI also
compiles the app and its tests for iOS and visionOS simulators, runs macOS UI tests,
builds the macOS app for DocC, and validates the static documentation. Workflow timeouts bound builds and tests.
Logs and result artifacts belong in ignored `.test-results/`.

Mac UI tests run a controlled loopback HTTP server inside the XCTest runner.
They use only test tokens and a unique defaults suite and Keychain service per
case. The macOS UI-test runner has the incoming-network entitlement needed to
bind its loopback server; the shipping app has only outgoing-network access.
The controlled server rejects failed listener startup rather than using port 0.
Restoration cases hold profile responses to verify validation progress, simulate
provider rejection and backend session loss, and retry socket and HTTP failures
without another browser handoff. Debug builds accept `UNARU_TEST_STORAGE` with a UUID to select that storage;
`UNARU_TEST_RESET=1` clears only the selected test storage. Release builds ignore
these variables. Test cleanup clears those credentials by relaunching the app.
Debug builds with isolated storage also accept `UNARU_TEST_BROWSER=1` to send
the handoff to the controlled backend instead of opening a browser. Release
builds ignore this setting. No test needs Kite credentials or browser cookies.
Run UI tests in an unlocked Mac login session with Xcode's UI automation authorization enabled. A runner
initialization or system-authentication failure means the UI tests did not run.

For manual accessibility verification, use VoiceOver and keyboard navigation to
open Settings, edit both fields, save, start and cancel login, retry a failed
connection or login, and hide and restore the sidebar. After login, resize the
sidebar and check that the informational account name and ID wrap and remain
readable. Verify avatar initials when an image cannot load. Check the minimum
window size and both appearances. UI queries cover accessible labels and control availability but do not verify spoken
VoiceOver output.

## Resolve commit check failures

The hook checks staged documentation links, authored file sizes, and Swift
formatting. Files larger than 20,000 bytes fail. Generated files, lockfiles, and
vendored sources use staged `.gitattributes` exemptions.

Formatting reads staged Swift blobs and the staged `.swiftformat`. The hook
leaves the index and working files unchanged, so partial staging is preserved.
To fix a rejection, format the affected file, review the diff, and stage the
intended hunks again. Changing formatter policy checks all authored Swift files.

```fish
swiftformat path/to/file.swift --config .swiftformat
python3 .githooks/pre-commit --base origin/main
```

CI applies the same commit checks against the pull request base or previous push.
Change the formatter pin, configuration, tests, CI installer, and this guide together.

GitHub Actions references use full commit SHAs. Repository policy requires these
pins and allows only the action repositories used by the workflows. Keep the
allowlist synchronized when introducing an action. Every checkout disables
persisted Git credentials. Workflow runs from outside contributors require approval.

CI runs actionlint with a checksum-verified binary. The Security workflow scans
Actions and Python with CodeQL. Swift scanning awaits support for the Swift 6.4
compiler, as described in [Security](../SECURITY.md).

## Update dependencies

Dependabot checks both Swift packages and GitHub Actions every Monday at 08:00
Asia/Kolkata. Networking patch and minor updates are grouped. KiteConnect and
major upgrades remain separate. Review release notes and require passing CI
before merging updates. Keep resolved package files in Git. Dependabot security alerts and security
updates are also enabled.

The backend uses KiteConnect 0.1.0 as an exact package dependency. Keep the Kite
API secret and token exchange on the backend. Browser login uses its request-token
exchange and profile API through the backend's outbound HTTP boundary. See [backend setup](../backend/README.md) for
Kite credentials and redirect registration. No trading routes are implemented.

## Build the container

The Docker context is the repository root because Backend depends on Shared:

```fish
docker build -f backend/Dockerfile -t unaru-backend .
docker compose -f backend/docker-compose.yml build
```

The builder uses Swift 6.4.2 on Ubuntu 24.04. The runtime includes libcurl for
KiteConnect's FoundationNetworking transport. See [DocC](../Documentation/DocC.md)
for documentation builds and [Pages](../Documentation/Pages.md) for publication.
