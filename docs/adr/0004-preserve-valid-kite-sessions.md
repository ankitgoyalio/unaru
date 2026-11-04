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

This decision is accepted but not yet implemented. The current implementation
keeps the session only in memory.
