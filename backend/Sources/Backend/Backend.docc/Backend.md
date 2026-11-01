# ``Backend``

The Vapor backend for Unaru.

## Overview

The backend exposes health and greeting routes plus an authorized `GET /session`
operation. The connection token comes from `UNARU_CONNECTION_TOKEN` in the server
process environment. ``ConnectionAuthorization`` protects app operations with
`Authorization: Bearer <connection-token>`. No credential belongs in a URL.

`GET /session` returns HTTP 200 with `{"state":"signedOut"}` when app authorization
succeeds and no Kite session exists. The response has `Cache-Control: no-store`.
Missing or incorrect authorization returns HTTP 401 without session information.
A missing or invalid server token returns HTTP 503 with
`{"code":"backendNotConfigured"}` to a request carrying bearer authorization.
This configuration failure is separate from Kite authentication and temporary
server failures. Empty tokens and tokens containing spaces or non-ASCII
characters are invalid. Health and greeting routes remain public and disclose
no session information.

New protected routes must use ``ConnectionAuthorization``. Shared payloads contain
no broker credentials. Browser login and Kite session validation follow in the
next slice. See the [connection setup guide](../../../README.md).

Keep Kite's API secret and token exchange on the backend. The application owns
credential storage, login state, authorization, and recovery after missed events.
KiteConnect supplies the broker protocol implementation.

The following example compiles as a Swift Testing test body without a network request:

```swift
let configuration = try KiteConfiguration()
let client = try KiteClient(apiKey: "documentation-api-key", configuration: configuration)
_ = client
```

## Topics

### Application lifecycle

- ``Entrypoint``
- ``configure(_:)``
- ``routes(_:connectionToken:)``
