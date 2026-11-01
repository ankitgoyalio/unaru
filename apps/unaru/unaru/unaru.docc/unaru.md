# ``unaru``

The SwiftUI application for Unaru.

## Overview

On macOS, the app opens a native split view with an empty, resizable sidebar.
Configure Connection opens native Settings, also available with Command-comma.
The backend address is saved in preferences and the separate connection token
is saved in Keychain. A verified connection reports that Kite sign-in is required.
Browser login is added in the following slice.

``BackendConnection`` owns verification and rejects results from a previous
configuration. Temporary failures offer Retry. Invalid app credentials lead to
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
