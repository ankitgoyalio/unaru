# ``Backend``

The Vapor backend for Unaru.

## Overview

The backend currently exposes a root health response and a `/hello` greeting.
It depends on Shared and KiteConnect. Authentication endpoints and trading
features have not been implemented.

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
- ``routes(_:)``
