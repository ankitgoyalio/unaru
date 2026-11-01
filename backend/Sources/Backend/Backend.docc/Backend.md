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
no broker credentials. Browser login uses the backend-held Kite credentials. See the [connection setup guide](../../../README.md).

Keep Kite's API secret and token exchange on the backend. The backend owns
broker credential storage, login correlation, and app authorization.
KiteConnect supplies the broker protocol implementation.

## Browser login contract

All app routes require the connection bearer token. Payloads never contain the
Kite API secret or access token. ``KiteLogin`` uses the pinned SDK and replaces
only its external HTTP transport during tests.

- `POST /login` returns a Shared `LoginAttempt` with `id`, `browserURL`, and
  `expiresAt`. Dates use Foundation Codable's seconds since 2001. The browser URL
  contains the public API key and a separate random callback value in
  Kite's documented `redirect_params`. Only the latest attempt remains valid.
- `GET /login/:id` returns `LoginStatus`: `pending`, `signedIn` with a public
  `AccountProfile`, `failed`, or `expired`. After exchange, this operation fetches
  the profile. HTTP 503 permits retrying that read without repeating exchange.
- `DELETE /login/:id` invalidates that attempt, including in-flight responses.
- `GET /profile` retrieves the backend-held session's current public identity.
  A Kite `TokenException` returns HTTP 401 and invalidates the session. Other
  upstream failures return HTTP 503 without discarding it.
- `GET /session` reports `signedIn` only after exchange and profile retrieval.
  Session restoration and full recovery policy are completed by issue #5.
- Public `GET /kite/callback` accepts Kite's `state`, `status`, and
  `request_token` query fields. A matching unconsumed attempt must exist and
  remain within its five-minute deadline. Callback authority is consumed before
  exchange. Malformed, denied, expired, replayed, or superseded callbacks return
  HTTP 400 with a fixed message and no credential data.

A cancelled browser tab sends no callback. The app provides cancellation and a
bounded wait. The backend keeps only one attempt and one authenticated session
in memory. A restart discards both.

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
- ``routes(_:connectionToken:login:)``
