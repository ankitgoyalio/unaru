# ``unaru``

The SwiftUI application for Unaru.

## Overview

On macOS, the app opens a native split view with an empty, resizable sidebar.
Configure Connection opens native Settings, also available with Command-comma.
The backend address is saved in preferences and the separate connection token
is saved in Keychain. A verified connection reports that Kite sign-in is required.
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
Settings, while a missing server token identifies a backend configuration problem.
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
