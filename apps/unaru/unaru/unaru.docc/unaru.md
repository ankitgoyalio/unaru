# ``unaru``

The SwiftUI application for Unaru.

## Overview

On macOS, ``BundledBackend`` launches the helper embedded in the app bundle and waits
for an authorized response on loopback. The app generates a fresh internal credential
for each launch. It does not ask for an address, connection token, or pairing approval.
The helper exits when the app quits, crashes, or is force-quit. A port conflict produces
a startup error with Retry. Retry restarts a failed helper and reloads Kite configuration.

Kite credentials live in `.env` in the app's Application Support directory. The app
creates a private template on first launch. Missing credentials during sign-in show
Set Up Kite with Open Configuration Folder and Retry. Register
`http://127.0.0.1:8080/kite/callback` with Kite. The helper owns token exchange and keeps
validated Kite authorization in its own Keychain item. After quit, crash, or a compatible
signed rebuild, the helper restores and validates the saved account before exposing
identity. Expired or invalid authorization requires browser sign-in again. The app never
reads the token or shares its Keychain access.

Startup, sign-in, and recovery use a fixed-size, window-modal sheet over the native
split view. The sheet closes after the account is verified. Sign in with Kite opens
the default browser. The app polls an authorized attempt with a five-minute deadline
and cancellation. Cancelling sign-in shows progress until durable removal is confirmed.
Failure shows Couldn’t Finish Cancelling Sign-In with Retry Cancellation and blocks
another sign-in. Success returns to the sign-in action within the sheet.
The resizable sidebar shows an informational ``AccountFooter`` only while signed in.
It shows the avatar or initials, full name, and Kite user ID. A nonmodal Sign-In Not
Saved notice in the main area leaves the account usable and offers Retry Saving.
Saving uses the current helper-held session without another browser handoff. Successful
saving clears the notice. Older helper responses can omit persistence status.

``BackendConnection`` rejects obsolete verification and cancelled login responses.
Temporary login-status or profile errors offer Retry Sign-In for the same attempt.
Session verification fetches a fresh profile before displaying identity. Periodic
verification detects Kite authentication rejection and session loss. Temporary network
failures offer Retry without repeating browser login. Saved-session validation failures
show Can’t Verify Kite Session. Keychain read failures show Saved Session Unavailable.
Both keep identity hidden and retry existing authorization. Failed retries retain the
same recovery action, and successful validation closes the sheet. Credential rejection
offers a local service restart without discarding the saved Kite token. The app caches no profile or Kite credential. Redirects are
refused before credentials can be forwarded. Logout clears visible identity immediately,
but failed durable removal shows Couldn’t Finish Logging Out with Retry Log Out.
Sign-in stays blocked until the helper acknowledges deletion. A credential-free marker
in the app's configuration directory retains unfinished logout or cancellation across
app relaunches. Cancellation retains the attempt ID and never broadens into logout.
Startup retries deletion before any session-status or profile request. The marker is
removed only after durable deletion succeeds. A separate notice reports unconfirmed
provider revocation after successful local removal.

iOS and visionOS retain their initial content and deployment targets.

The initial signed-in destination is Portfolio. Its Holdings child lists securities and mutual funds
reported by Kite in separate native tables. Return opens inspection for the selected row.
Inspection separates ordinary inventory, prices, financing, and source limitations.
The account control remains in the sidebar footer. The view covers the connected Kite account's returned holdings without claiming complete
demat inventory or external-account coverage. Trading positions and combined investment
calculations are outside these source inspection views.

``PortfolioStore`` shares fetched holdings across windows in memory. Opening Portfolio
and Refresh Portfolio fetch both sources independently. The toolbar and menu offer Refresh Portfolio
with Command-R. Initial loading, an empty source, retrieval time, missing price date,
and read failures have separate visible states. Retry preserves the valid Kite session and requests only the failed source.
Each source has its own loading, failure, empty, and retrieval state. A failed refresh
retains that source's previous rows with a stale notice while successful sources remain visible. Authority removal clears
holdings across every window. Obsolete success and failure cannot restore old rows or
invalidate a newer session. App relaunch fetches holdings again without restoring a
portfolio snapshot.

Mutual fund inspection retains fractional units, acquisition prices, latest available
NAVs, folios, and pledged units. NAV dates appear per holding, including different dates
within a source. Unavailable dates stay unavailable. Retrieval time never establishes
a current-day NAV. Missing cost, NAV, pledge relationships, and potential overlaps have
text explanations. Exact source prices remain available in inspection without treating
provider P&L as a verified return.

## Topics

### Application and content

- ``unaruApp``
- ``ContentView``
- ``AccountFooter``

### Mac startup and sign-in

- ``BundledBackend``
- ``BackendConnection``
- ``BackendTransport``
- ``ConnectionStatusView``
