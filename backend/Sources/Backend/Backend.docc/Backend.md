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

### Trading funds contract

`GET /portfolio/funds` requires app authorization and a validated Kite session.
The pinned SDK reads `GET /user/margins`. ``TradingFundsSource`` maps the documented
equity and commodity segments into Shared `TradingFunds`. Each segment preserves
its enabled state, net availability, total utilisation (`debits`), and component balances
as Decimal values. Negative and zero balances remain valid reported amounts.
No components are added together and no funds enter holdings performance or wealth.

Disabled segments remain explicit successful results. The pinned SDK requires both
segments and their documented fields. Missing segment data is a malformed response,
reported as a retryable HTTP 503 with `portfolioUnavailable`, never a disabled segment
or an invented zero balance. Provider diagnostics and extra fields are excluded.
Retrieval time uses Foundation Codable seconds since 2001. Responses use `no-store`.

Funds requests have independent supersession checks. Old responses after logout,
confirmed expiry, a new login, or a newer funds read cannot disclose old balances or
remove newer authority. Temporary failures preserve the valid session. Confirmed token
rejection uses the existing authority-removal and `kiteSignInRequired` contract.

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

### Current-holdings performance contract

`POST /portfolio/performance` accepts Shared `PortfolioPerformanceRequest` with the
`readID` of each successful holdings source. It requires app authorization and validated
Kite authority. ``PerformanceSources`` accepts only the latest successful reads.
A source read clears its cached result before requesting Kite, so an in-flight or
failed refresh cannot supply an aggregate. Missing or superseded read IDs return
HTTP 503 with `portfolioUnavailable`. Authority removal clears both cached sources.
All snapshots remain in memory and responses use `Cache-Control: no-store`.

``HoldingValuation`` uses Decimal throughout. Ordinary securities quantity is settled
quantity plus T1, excluding the separate MTF quantity. Used quantity and net CNC
positions are never deducted again. This follows the provider's
[quantity clarification](https://kite.trade/forum/discussion/comment/50543/) and
[same-day sale example](https://kite.trade/forum/discussion/comment/52974/).
An ordinary component of a mixed MTF record remains eligible when its relationship is
supported. Financed sales, short delivery, pledge relationships, discrepancies, and
possible overlapping records withhold the affected contribution.

Cost is eligible quantity times positive acquisition price. Value is eligible quantity
times positive market price or NAV. Each measure can be available independently.
Gain requires both. Combined return is summed matched gain divided by summed matched
cost, times 100, with no percentage for a nonpositive denominator. The response gives
cost, value, and return coverage separately, plus matched cost and value. No available
contribution from nonempty inventory is unavailable, while successful empty inventory
is zero. Unknown classification and missing valuation dates do not invent metadata or
prevent otherwise supported arithmetic.

Source normalization indexes duplicate identities in linear time. Combined analysis
checks shared depository identities across sources and returns source-qualified rows
with final eligibility. Cross-source overlaps retain both records with unavailable
contributions. These row values are the authoritative inputs for allocation,
largest-holding ordering, and value-based inspection. Positions and trading balances
never enter this projection.

### Current-value allocation contract

The performance response also includes Shared `PortfolioAllocation`.
``HoldingAllocation`` uses the final ordinary row valuations after cross-source overlap
checks. Acquisition cost is not an allocation input. Holdings with usable value and
unavailable cost remain eligible. Ranking is descending by current value, with
source-qualified row identity as the deterministic tie-breaker. Source names and symbols
stay available without external metadata lookups.

Each ordinary row belongs to one supported type group. Securities remain unknown because
the source supplies no investment classification. The dedicated fund source establishes
mutual fund membership without underlying exposure. Group coverage includes unvalued
records. Missing prices and ambiguous inventory make valuation coverage incomplete.
No unavailable holding receives an invented weight. Group and row percentages divide
only by a positive available valued total. Successful empty inventory has zero value,
empty ranking and groups, and no percentages.

MTF quantities stay outside the denominator and ranking. The result counts records with
omitted MTF components, including mixed records whose ordinary component remains eligible.
Positions, funds, collateral balances, and provider P&L never enter allocation.
Allocation follows the same exact-read, authority, memory-only, and refresh lifetime as
the performance response.

### Net positions contract

`GET /portfolio/positions` requires app authorization and a validated Kite session.
The pinned SDK reads Kite's positions, and ``NetPositionSource`` exposes only the
`net` collection as Shared `NetPositions`. The overlapping `day` collection is not
added or returned. Nonzero signed quantities are current positions. Returned zero
quantities are closed positions. Every net row keeps its own retrieval-scoped identity.

Signed quantities, contract multipliers, prices, realised and unrealised trading P&L,
mark-to-market values, and buy/sell activity remain broker reported. No trading value
or P&L contributes to holdings quantities or investment returns. Delivery purchases
stay in Positions until the holdings source reports them. No market-price timestamp
is supplied, so `valuationDate` remains absent. Retrieval time uses Foundation Codable
seconds since 2001.

An empty net collection is a successful source. Temporary failures return HTTP 503
with `portfolioUnavailable` and preserve valid Kite authority. Confirmed token rejection
returns HTTP 401 with `kiteSignInRequired`. The operation rejects obsolete responses
after authority changes or a newer positions read. Holdings and positions reads do not
supersede one another. Responses contain no broker credentials and use
`Cache-Control: no-store`.

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
The source contract excludes provider P&L. Combined performance uses the separate operation below.

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
