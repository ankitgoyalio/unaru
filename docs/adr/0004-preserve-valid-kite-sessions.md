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

Credential-free save status is included in session status and successful login
completion. The app keeps the account usable while displaying Sign-In Not Saved.
Retry Saving uses the validated helper-held session and clears the notice on success.

Failed logout shows a distinct recovery state and blocks another sign-in until secure
deletion succeeds. A credential-free file in the app's configuration directory records
unfinished logout before the helper request. After helper or app restart, the app
retries deletion before requesting any restorable session. It removes the marker only
after the helper acknowledges durable removal. Provider revocation uncertainty remains
separate from local deletion failure.

Synchronous store operations remain serialized with coordinator authority, including
blocked saves and deletions. No old store completion can resume after a newer actor
generation. Delayed provider responses still require generation and client checks.
