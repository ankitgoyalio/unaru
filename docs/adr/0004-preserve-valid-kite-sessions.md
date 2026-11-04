# Preserve valid Kite sessions across app restarts

A valid Kite session must survive app rebuilds, normal quits, and crashes. Require
browser sign-in again when Kite expires or invalidates the session. This revises
the session lifetime in [ADR 0003](0003-bundle-the-mac-backend.md), while retaining
the app-managed bundled helper. Losing a valid session whenever the helper stops
causes unnecessary browser sign-ins during development and normal use.

The bundled Mac backend helper owns the saved Kite access token in macOS
Keychain. Scope the saved session to the configured API key and validated Kite
account. Restore the token on launch and validate it with Kite before displaying
the account. The app receives persistence status and can request another save
attempt, but does not receive the token. Keep the app-to-helper authorization
credential temporary for each app launch.

Keep the saved session when a network or temporary Kite failure prevents
validation. Offer Retry and require sign-in only after Kite confirms that the
session is invalid. Delete saved sessions after confirmed invalidation and on
explicit sign-out. Do not report local sign-out as complete if deletion fails.

If secure storage fails after sign-in, keep the current session usable. Explain
that the login will not survive quitting and offer to retry saving it.

Give the helper a stable signing identity so replacement builds can retain
Keychain access. Verify restoration across actual helper termination and
replacement with isolated test credentials. A test backend that survives an app
relaunch does not establish persistence across helper replacement.

The persistence slice is implemented by `KiteLogin` and its narrow `KiteSessionStore`
boundary. Only bundled Mac helpers select `KeychainKiteSessionStore`; standalone
backends remain memory-only. Local store operations run synchronously within the
login actor, and restored profile requests check generation before publishing authority.

Signed local acceptance uses a sandboxed parent, isolated fake credentials, and
an isolated Keychain namespace. It verifies replacement with a different helper code
hash under the same Apple Development identity, normal quit, parent crash, and
sign-out followed by restart. Ad hoc CI signing alone does not prove this continuity.

Credential-free recovery codes distinguish temporary provider validation failure from
Keychain read failure. Both preserve saved authorization and keep identity hidden until
Retry succeeds. Generation and request-order checks reject stale restore responses,
including a rejection that arrives after a newer successful validation.

Credential-free save status and a save retry endpoint provide the foundation for save
recovery in issue #22. Failed logout stays in the existing retry flow until durable
deletion succeeds. Signed lifecycle acceptance also stops the helper during a provider
outage, then verifies recovery from Keychain without another exchange.
