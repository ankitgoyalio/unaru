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
`Cache-Control: no-store`. Approved public verification keys survive restart. Standalone Kite
sessions remain in memory; bundled Mac helpers use private Keychain storage. Protected endpoints reject unapproved credentials with HTTP
401. A missing legacy-only configuration can still return HTTP 503 with
`backendNotConfigured`.

New protected routes must use ``ConnectionAuthorization``. Request bodies and credential
headers must be excluded from proxy logs. The app-facing identity payloads contain no
Kite access token or API secret.

Keep Kite's API secret and token exchange on the backend. The backend owns broker
credential storage, login correlation, and app authorization. KiteConnect supplies the
broker protocol implementation.

### Securities holdings contract

`GET /portfolio/holdings` requires app authorization and a validated Kite session.
The real pinned SDK reads Kite's securities holdings. ``SecuritiesHoldingSource`` maps
only supported inspection fields into Shared `SecuritiesHoldings`; arbitrary provider
metadata and credentials never enter the response. Foundation Codable dates use
seconds since 2001. Retrieval time records when the helper obtained the response.
The source provides no security name, investment classification, or price valuation date.

Every source row remains visible, including potentially overlapping records and
nonpositive prices. Ordinary, T1, used, collateral, and MTF fields remain separate.
Used quantity is not subtracted again. Pledge and MTF relationships are not inferred,
and this operation calculates no combined investment total.

A successful empty source returns HTTP 200 with an empty `holdings` array. Temporary
provider failures return HTTP 503 with `portfolioUnavailable` and preserve the session.
Missing Kite authority or confirmed `TokenException` returns HTTP 401 with
`kiteSignInRequired`. Missing app authorization is rejected before the operation runs.
An obsolete response after authority removal or a newer holdings read returns no old
data and cannot invalidate newer authority. Authorized responses use `Cache-Control: no-store`.

### Mutual fund holdings contract

`GET /portfolio/mutual-funds` applies the same app and Kite authorization requirements
as securities holdings. The pinned SDK reads `GET /mf/holdings`.
``MutualFundHoldingSource`` returns Shared `MutualFundHoldings` with its own retrieval
time. Source ordering and all rows remain intact. Fractional units, acquisition prices,
NAVs, and pledged units retain Decimal precision. Available NAV dates stay calendar
dates. Missing, null, and empty dates remain unavailable, with no retrieval-time fallback.

Symbols and folios are inspection fields, not unique row keys. Repeated fund symbols
carry an overlap limitation even when folios differ. Pledged units are neither added to
nor deducted from primary units. Nonpositive prices and units remain inspectable with
limitations. Malformed required SDK fields fail the source rather than fabricating rows.
The contract excludes provider P&L and calculates no combined investment total.

Empty success, temporary failures, and confirmed invalidation follow the securities
HTTP contract. Mutual fund refresh ordering is independent of securities ordering.
Delayed responses must still match the current Kite authority and latest source request.

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
- `GET /profile` retrieves the backend-held session's current public identity.
  A missing session or Kite `TokenException` returns HTTP 401 with
  `{"code":"kiteSignInRequired"}`. A token rejection invalidates the session.
  Missing or incorrect connection credentials return HTTP 401 before this route
  runs, without that code. Other upstream failures, including transport errors,
  rate limits, malformed responses, and permission errors, return HTTP 503
  without discarding the Kite session.
- `GET /session` restores saved bundled-helper authorization and validates its account
  before returning `signedIn`. Missing or confirmed invalid authorization returns
  `signedOut`. Temporary provider failures return HTTP 503 with
  `{"code":"kiteSessionUnavailable"}`. Secure-storage read failures return HTTP 503 with
  `{"code":"sessionStorageUnavailable"}`. Both preserve the item and permit retrying the
  same request without browser login or token exchange, including after helper restart.
  Neither response contains account identity. `GET /profile` uses the same codes when
  restoration fails before a validated session exists.
  The optional `persistence` field is `saved`, `saveFailed`, or `memoryOnly` for signed-in
  sessions. The app follows `signedIn` with a fresh `GET /profile` before showing identity.
- `POST /session/save` retries saving the current validated session and returns
  `SessionStatus`. A failed save returns `saveFailed` while retaining usable identity.
  It performs no browser handoff or exchange. Connection authorization is required.
- Signed-in `LoginStatus` responses also include optional credential-free `persistence`
  status so clients can present save failures immediately after browser completion.
- `DELETE /login/:id` detaches the matching browser attempt and validated authority
  before secure deletion. HTTP 503 leaves removal pending and requires retry. A successful
  response acknowledges durable removal of that attempt's saved authorization.
  The saved value retains a credential-free attempt ID so cancellation can be replayed
  before restoration after helper restart. An old cancellation cannot delete a newer
  saved session. Clients retain the cancellation intent until acknowledgement.
- `POST /logout` detaches old authority and removes saved authorization before returning
  `LogoutResult`. Failed secure deletion returns HTTP 503 and permits another logout
  request. Remote revocation remains bounded and may be `unconfirmed` after local success.
- Public `GET /kite/callback` accepts Kite's `state`, `status`, and
  `request_token` query fields. A matching unconsumed attempt must exist and
  remain within its five-minute deadline. Callback authority is consumed before
  exchange. Malformed, denied, expired, replayed, or superseded callbacks return
  HTTP 400 with a fixed message and no credential data.

A cancelled browser tab sends no callback. The app provides cancellation and a bounded
wait. The backend keeps one browser attempt and one authenticated session in memory.
A restart discards browser authority. Only a bundled Mac helper selects the narrow
``KiteSessionStore`` boundary's Keychain implementation, ``KeychainKiteSessionStore``.
The store scopes authorization to the API key and validated account. Synchronous storage
operations cannot complete after newer actor authority; restored provider requests must
still pass generation and request-order checks. An older restore response cannot clear
or replace a newer validated session. Standalone and test coordinators default to no storage.

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
