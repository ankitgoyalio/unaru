# ``Shared``

Types and behavior shared by the Unaru app and backend.

## Overview

This package defines the credential-free ``SessionStatus`` and ``ConnectionProblem``
payloads shared by the app and backend. Session status is returned only after the
backend authorizes the app’s connection credential. The bundled Mac app uses a private,
launch-scoped credential. Standalone development clients can use connection pairing.
``PairingRequest`` offers a client-
generated public verification key for approval; ``PairingStatus`` reports its short-
lived comparison code and approval state. The request contains only the public
verification key. The private signing key is never transmitted. On macOS,
``LocalPairingKeychain`` supplies same-user bootstrap access under Keychain controls.
``LoginAttempt``, ``LoginStatus``, and ``AccountProfile`` describe the browser handoff
and its resulting public identity. Dates use Foundation Codable's default seconds since
2001. These payloads contain no broker tokens or API secret. `ConnectionProblem`
distinguishes `backendNotConfigured` from `kiteSignInRequired`. The latter accompanies
an authorized profile request when no valid Kite session remains. A generic HTTP 401
without that code indicates rejected app connection credentials. HTTP 503 with
`kiteSessionUnavailable` permits retrying validation of saved authorization.
`sessionStorageUnavailable` permits retrying secure-storage access without claiming that
the token is absent or invalid. Both preserve saved authorization. Session status reports
a backend-held session; a fresh profile request validates it before the app displays
identity. Optional `SessionStatus.persistence` reports `saved`, `saveFailed`, or
`memoryOnly` for usable sessions without disclosing credentials. Older payloads without
this field remain decodable. `LoginStatus.persistence` provides the same status at
browser completion so a save failure can appear immediately. Neither payload exposes
the access token. The scaffold greeting remains available for the existing examples.

The following example compiles as a Swift Testing test body:

```swift
hello()
```

``SecuritiesHoldings`` represents a successful securities-source read, including an
empty result. It preserves retrieval time separately from the optional price valuation
date. ``SecurityHolding`` retains each source row and its limitations, including unknown
classification, unusable prices, and potential overlap. ``HoldingMTF`` keeps financing
fields separate from ordinary inventory. These contracts expose no broker credentials
or combined investment total. HTTP 503 with `portfolioUnavailable` permits retrying the
source without another sign-in.

``NetPositions`` contains only current net collection rows, including returned closed
positions, with retrieval time separate from the unavailable market-price date.
``TradingPosition`` preserves signed quantities, multipliers, broker prices and trading
P&L, and supporting buy/sell fields. Its `state` groups nonzero quantities as current
and zero quantities as closed. These values do not contribute to holdings returns.

## Topics

### Scaffold

- ``hello()``

### Backend connection contract

- ``SessionStatus``
- ``ConnectionProblem``

- ``LoginAttempt``
- ``LoginStatus``
- ``AccountProfile``

### Securities holdings

- ``SecuritiesHoldings``
- ``SecurityHolding``
- ``HoldingMTF``

### Trading positions

- ``NetPositions``
- ``TradingPosition``

### Connection pairing

- ``PairingRequest``
- ``PairingStatus``
- ``LocalPairingKeychain``
