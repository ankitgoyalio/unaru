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
the Kite access token in memory. Closing and reopening a window retains that session;
quitting the app discards it.

Startup, sign-in, and recovery use a dedicated screen without a sidebar. Sign in with
Kite opens the default browser. The app polls an authorized attempt with a five-minute
deadline and cancellation. Successful login opens the native split view with a
resizable sidebar and informational ``AccountFooter``. It shows the avatar or initials,
full name, and Kite user ID. The signed-in main area stays empty.

``BackendConnection`` rejects obsolete verification and cancelled login responses.
Temporary login-status or profile errors offer Retry Sign-In for the same attempt.
Session verification fetches a fresh profile before displaying identity. Periodic
verification detects Kite authentication rejection and session loss. Temporary network
failures offer Retry without repeating browser login. Credential rejection offers a
local service restart. The app caches no profile or Kite credential. Redirects are
refused before credentials can be forwarded.

iOS and visionOS retain their initial content and deployment targets.

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
