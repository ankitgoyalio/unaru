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
python3 -m unittest discover -s Tests/CI -p 'test_*.py'
python3 Scripts/check-documentation.py
python3 Scripts/check-documentation-examples.py
swift test --package-path packages/Shared
swift test --package-path backend
python3 -m unittest discover -s Tests/BackendConfiguration -p 'test_*.py'
xcodebuild build-for-testing -project apps/unaru/unaru.xcodeproj -scheme unaru -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO
xcodebuild build-for-testing -project apps/unaru/unaru.xcodeproj -scheme unaru -destination 'generic/platform=visionOS Simulator' CODE_SIGNING_ALLOWED=NO
xcodebuild test -project apps/unaru/unaru.xcodeproj -scheme unaru -destination 'platform=macOS' CODE_SIGN_IDENTITY=- -only-testing:unaruUITests
python3 Scripts/build-documentation.py
```

The backend loads Vapor dotenv files from its working directory. Copy
[`backend/.env.example`](../backend/.env.example) to `backend/.env` for local Kite
configuration, as described in [backend setup](../backend/README.md). Real dotenv
files stay out of Git and Docker build contexts. The subprocess configuration tests
use temporary dotenv files and fake credentials to check startup, precedence, logging,
and authorized login initiation. They make no live Kite requests. The opt-in signed
lifecycle test separately uses real Keychain with a unique fake API key and UUID namespace;
it deletes only its own items during cleanup.

Linux CI runs the Shared and Backend suites with Swift 6.4.2. Apple CI also
compiles the app and its tests for iOS and visionOS simulators, runs macOS UI tests,
builds the macOS app for DocC, and validates the static documentation. Workflow timeouts bound builds and tests.
Logs and result artifacts belong in ignored `.test-results/`.

Apple package checks and simulator builds run alongside the macOS UI build and
an Intel helper build. The UI build produces signed test products for four shards
on independent Mac desktops. Only products from the current run are used. These
Mac jobs use at most five runners concurrently. The short fourth shard waits for
app DocC to release its runner. Package documentation reuses
the package test builds. A Linux job combines all three DocC modules and verifies
the complete site. The required `apple` check requires every Apple job and site
assembly to succeed. Linux package tests run independently. Every pull request
runs the full set of checks.
Artifact downloads use the pinned `actions/download-artifact` action with its
current-run runtime token and fail on a digest mismatch. Downloads do not accept
a run ID, repository, or GitHub token override.

`.github/ui-test-shards.json` assigns each UI method to one runner. The runner
script rejects missing or duplicated methods and requires every selected test to
pass without skips. When adding or renaming a UI method, update its shard entry.
Run `python3 -m unittest discover -s Tests/CI -p 'test_*.py'` to check the partition.
Keep slow methods on separate shards. UI workers use independent desktops to avoid
interference with keyboard focus and windows.

CI caches SwiftPM dependencies and build products for each job, operating system,
architecture, runner image, toolchain, and dependency manifest. Caches contain
weekly build seeds. SwiftPM checks the current source and incrementally rebuilds
after every restore. Main and dispatched runs refresh a seed once per week. PRs
save only when no compatible seed exists. UI shards consume the current run's
build artifact and do not restore or save SwiftPM caches. This avoids saving
large caches for every source commit.
Main-branch caches remain available to new PRs within GitHub's cache retention
limits. Restoring a cache never skips a build, test, or documentation check.
Xcode DerivedData, result bundles, and generated documentation sites are not cached.

The Mac app build runs `Scripts/bundle-backend.sh` to compile Backend for each requested
architecture, combine the slices, and sign the helper with sandbox inheritance. The app
allows incoming and outgoing networking so its child can bind loopback and call Kite.
The helper has the explicit signing identifier `io.ankitgoyal.unaru.backend` and owns
its saved Kite authorization in Keychain. The helper lives in `Contents/Helpers`; iOS and visionOS builds skip this phase. SwiftPM
builds use `.build/bundled-backend` and run outside Xcode's script sandbox. App Sandbox
remains enabled. Distribution archives require the usual signing identity for both
executables. No standalone backend needs to be launched for the Mac app.
Helper builds disable the compiler index store. Neither the app nor the UI test
runner reads the helper's development index.
CI builds each helper architecture once for the app builds: the UI build supplies
the native slice, and a separate job supplies the Intel slice. DocC builds both app
architectures with those current-run artifacts. The bundle script checks each
slice's architecture and accepts prebuilt helpers only in Debug CI builds.

Mac UI tests use controlled loopback HTTP servers for browser completion and session
recovery. Debug builds accept `UNARU_TEST_STORAGE` with a UUID to isolate configuration,
`UNARU_TEST_BACKEND_ADDRESS` to select the controlled loopback server, and
`UNARU_TEST_BROWSER=1` to replace the browser handoff. Tests that launch the actual helper
use `UNARU_TEST_BACKEND_PORT` to avoid occupying the owner's callback port.
The app forwards the isolated UUID to the helper so it cannot select production session
storage. `UNARU_TEST_KITE_URL` accepts only an HTTP loopback origin with an explicit
port, only in a Debug helper with that UUID. Release builds ignore both overrides.
`UNARU_TEST_APPEARANCE=Light` or `Dark` fixes appearance, and
`UNARU_TEST_REVALIDATION_SECONDS` accelerates session checks. Every override requires the
isolated UUID and is ignored by Release builds. No test uses real Kite credentials or
browser cookies. The subprocess suite checks bundled authorization, missing Kite
configuration, disabled pairing, and helper exit after its parent pipe closes.

To verify signed helper replacement locally, select a compatible Apple signing identity:

```fish
env UNARU_SIGNING_IDENTITY='<identity hash from security find-identity -v -p codesigning>' python3 -m unittest discover -s Tests/BackendConfiguration -p test_session_lifecycle.py
```

Build the Debug backend first with `swift build --package-path backend`. The opt-in test
compiles a sandboxed parent, signs two helper variants with different code hashes under
the stable helper identifier, and exercises normal quit, parent crash, restoration,
launch-credential rotation, and logout/restart against fake loopback Kite responses.
It uses unique fake credentials and a UUID Keychain service with cleanup. Without the
identity variable, this test is explicitly skipped. CI's ad hoc signatures cannot replace
this signing-aware evidence. Tests never access the owner's Kite session.

Run UI tests in an unlocked Mac login session with Xcode UI automation authorization.
CI prepares a display of at least 1280 × 1024 points before UI tests so the
1024 × 846 minimum app window and system chrome remain visible.
An initialization or system-authentication failure means the tests did not run.
For manual accessibility verification, use VoiceOver and keyboard navigation through
startup, sign-in, cancellation, configuration recovery, and Retry. Confirm there is no
backend address or pairing step. Check the minimum window size and both appearances.
After login, hide and restore the sidebar and verify readable name and ID wrapping.
UI queries cover labels and control availability but do not verify spoken VoiceOver
output.

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
The allowlist includes `actions/download-artifact@*` for current-run transfers.
The cache allowlist includes `actions/cache@*` and `actions/cache/*@*` for separate
restore and save actions. All workflow references still use full commit SHAs.

CI runs actionlint with a checksum-verified binary. The Security workflow scans
Actions and Python with CodeQL. Swift scanning awaits support for the Swift 6.4
compiler, as described in [Security](../SECURITY.md).

## Measure CI changes

Before changing CI, run the existing workflow on the proposed branch and record
the commit, run URL, runner labels, queue time, job durations, and step durations.
Keep the application source and required check coverage fixed during the comparison.
After changing CI, record a run with empty optimization caches and a second run
that restores those caches. Report elapsed workflow time separately from the sum
of runner time, because parallel jobs can reduce latency while consuming more compute.
Keep raw API responses, logs, and timing reports in ignored `.test-results/` or CI
artifacts. A failed or cancelled run is not a successful performance measurement.
The CI dispatch input `cache_namespace` defaults to `swift-build-v3`. Use a unique
value to measure empty optimization caches, then dispatch the same revision with
the same value to measure restored caches. Each independent run starts fresh
runners and executes all checks. Record each run separately.

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
