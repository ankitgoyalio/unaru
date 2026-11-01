# ``unaru``

The SwiftUI application for Unaru.

## Overview

On macOS, the app opens a native split view with an empty, resizable sidebar.
Configure Connection opens native Settings, also available with Command-comma.
Settings accepts only a backend address and a Connect action. The app generates its credential and saves it in Keychain after pairing approval. Same-user native loopback backends use a Keychain bootstrap; other connections display a code for approval with `Backend pair <code>` on the server. The address is saved in preferences. A verified connection reports that Kite sign-in is required.
Sign in with Kite starts an authorized attempt and opens the default browser.
The app polls for completion while showing progress and a cancellation action.
A completed login displays an informational ``AccountFooter`` at the bottom of
the sidebar. It shows the avatar or initials, full name, and Kite user ID. The
signed-in main area stays empty.

``BackendConnection`` owns verification and rejects results from a previous
configuration or cancelled login. A revision guard applies after every network
response, including token-exchange completion and profile retrieval. Temporary
login-status or profile failures offer Retry Sign-In for the same attempt.
On launch, saved connection settings are restored and the backend-held session
is validated through a fresh profile request before identity appears. No profile
or Kite credential is cached in the app. Kite authentication rejection and a
missing backend session return to sign-in. Temporary validation failures retain
configuration and offer Retry without another login. Backend connection-token
rejection directs the user to Settings separately from Kite authentication.
Denied or expired attempts permit a new browser login. Connection failures offer Retry. Invalid app credentials lead to
Settings to pair this Mac again. Pairing cancellation and expiry require a new Connect attempt.
Remote addresses require HTTPS. HTTP is allowed only for loopback connections,
and redirects are refused before credentials can be forwarded.

KiteConnect remains a backend dependency. The app does not contain a Kite API
secret or perform token exchange. iOS and visionOS retain their initial content
and deployment targets.

## Topics

### Application and content

- ``unaruApp``
- ``ContentView``

### Mac connection

- ``BackendConnection``
- ``ConnectionStorage``
- ``ConnectionSettings``
- ``ConnectionStatusView``

- ``AccountFooter``

### Connection pairing

- ``BackendPairing``
- ``BackendTransport``
- ``PairingInstructions``
