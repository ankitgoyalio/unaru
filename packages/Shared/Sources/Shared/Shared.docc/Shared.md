# ``Shared``

Types and behavior shared by the Unaru app and backend.

## Overview

This package defines the credential-free ``SessionStatus`` and
``ConnectionProblem`` payloads shared by the app and backend. Session status is
returned only after the backend authorizes the app's separate connection token.
``LoginAttempt``, ``LoginStatus``, and ``AccountProfile`` describe the browser
handoff and its resulting public identity. Dates use Foundation Codable's default
seconds since 2001. These payloads contain no broker tokens or API secret.
`ConnectionProblem` distinguishes `backendNotConfigured` from
`kiteSignInRequired`. The latter accompanies an authorized profile request when
no valid Kite session remains. A generic HTTP 401 without that code indicates
rejected app connection credentials. Session status reports a backend-held
session; a fresh profile request validates it before the app displays identity.
The scaffold greeting remains available for the existing examples.

The following example compiles as a Swift Testing test body:

```swift
hello()
```

## Topics

### Scaffold

- ``hello()``

### Backend connection contract

- ``SessionStatus``
- ``ConnectionProblem``

- ``LoginAttempt``
- ``LoginStatus``
- ``AccountProfile``
