# ``Backend``

The Vapor backend for Unaru.

## Overview

The Mac app embeds this executable, starts it on loopback with `UNARU_BUNDLED=1`,
and passes a launch-scoped `UNARU_CONNECTION_TOKEN`. This mode disables the pairing
registry and Keychain bootstrap. The app owns the stdin pipe; EOF terminates the helper
even after an abrupt parent exit. Kite configuration comes from the app's private
Application Support folder. The app does not connect to standalone servers.

For standalone development, the backend exposes health and greeting routes plus an authorized `GET /session`
operation. ``PairingStore`` approves app-generated credentials and persists their public keys
in an owner-only data directory. ``ConnectionAuthorization`` protects app operations
with fresh, signed requests using the app’s private key. Existing
`UNARU_CONNECTION_TOKEN` values remain accepted during migration. No credential belongs
in a URL.

`POST /pairing` accepts a `PairingRequest` and returns a `PairingStatus` containing an
attempt ID, comparison code, expiry, and approval state. A same-user Mac Keychain
bootstrap proof can approve immediately through an HMAC bound to the candidate public
key. The bootstrap secret itself is never transmitted. Otherwise the owner runs `Backend
pair <code>` on the server; the command writes a private approval marker for the running
backend to consume. A network caller cannot approve a code. The app polls `GET
/pairing/:id` with a signed request and can cancel with `DELETE /pairing/:id`.

Attempts expire after five minutes. Polling and cancellation require a signature from
the candidate private key, not the public ID or comparison code. Pairing responses use
`Cache-Control: no-store`. Approved public verification keys survive restart; Kite
sessions remain in memory. Protected endpoints reject unapproved credentials with HTTP
401. A missing legacy-only configuration can still return HTTP 503 with
`backendNotConfigured`.

New protected routes must use ``ConnectionAuthorization``. Request bodies and credential
headers must be excluded from proxy logs. The app-facing identity payloads contain no
Kite access token or API secret.

Keep Kite's API secret and token exchange on the backend. The backend owns broker
credential storage, login correlation, and app authorization. KiteConnect supplies the
broker protocol implementation.

### Environment configuration

``Entrypoint`` uses Vapor's automatic dotenv loading before configuring logging and
routes. Files resolve against the backend process working directory. Process variables
override `.env.<environment>`, which overrides `.env`. The default environment is
`development`; `--env` or process-level `VAPOR_ENV` selects another environment before
file loading. File changes take effect on restart.

| Variable | Purpose | Default |
| --- | --- | --- |
| `KITE_API_KEY` | Public API key for browser login | Required for login |
| `KITE_API_SECRET` | Backend-only request-token exchange secret | Required for login |
| `LOG_LEVEL` | Logging threshold, overridden by `--log` | `info` in development, `notice` in production |
| `UNARU_DATA_DIRECTORY` | Native persistent pairing state directory | Backend user's `~/.unaru` |
| `UNARU_CONNECTION_TOKEN` | App-generated authorization in bundled mode; optional standalone token | Unset |
| `UNARU_BUNDLED` | App-managed helper with stdin lifetime and no pairing | Unset |

Missing Kite credentials leave pairing and session status available, but login
initiation returns HTTP 503 with `{"code":"backendNotConfigured"}`. Startup logs a warning without credential values. The
hostname and port remain `serve` command options. The example configuration and local,
Xcode, and Compose launch procedures are in the repository's backend setup guide.

### Browser login contract

Account and login routes require an approved connection credential. Payloads never
contain the Kite API secret or access token. ``KiteLogin`` uses the pinned SDK and
replaces only its external HTTP transport during tests.

- `POST /login` returns a Shared `LoginAttempt` with `id`, `browserURL`, and
  `expiresAt`. Dates use Foundation Codable's seconds since 2001. The browser URL
  contains the public API key and a separate random callback value in
  Kite's documented `redirect_params`. Only the latest attempt remains valid.
- `GET /login/:id` returns `LoginStatus`: `pending`, `signedIn` with a public
  `AccountProfile`, `failed`, or `expired`. After exchange, this operation fetches
  the profile. HTTP 503 permits retrying that read without repeating exchange.
- `DELETE /login/:id` invalidates that attempt, including in-flight responses.
- `GET /profile` retrieves the backend-held session's current public identity.
  A missing session or Kite `TokenException` returns HTTP 401 with
  `{"code":"kiteSignInRequired"}`. A token rejection invalidates the session.
  Missing or incorrect connection credentials return HTTP 401 before this route
  runs, without that code. Other upstream failures, including transport errors,
  rate limits, malformed responses, and permission errors, return HTTP 503
  without discarding the Kite session.
- `GET /session` reports whether an in-memory session exists after exchange and
  profile retrieval. This status alone does not validate a saved Kite token.
  On launch and retry, the app follows `signedIn` with `GET /profile` and presents
  identity only after that fresh provider request succeeds. A backend restart
  returns `signedOut`, and the app requests browser login again.
- Public `GET /kite/callback` accepts Kite's `state`, `status`, and
  `request_token` query fields. A matching unconsumed attempt must exist and
  remain within its five-minute deadline. Callback authority is consumed before
  exchange. Malformed, denied, expired, replayed, or superseded callbacks return
  HTTP 400 with a fixed message and no credential data.

A cancelled browser tab sends no callback. The app provides cancellation and a bounded
wait. The backend keeps only one attempt and one authenticated session in memory. A
restart discards both.

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
- ``routes(_:connectionToken:login:pairing:)``
