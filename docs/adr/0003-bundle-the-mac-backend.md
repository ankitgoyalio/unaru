# Bundle the Mac backend and let the app manage it

Ship the Mac app and backend as one bundle. The app starts its embedded helper on
loopback, authorizes requests with a random credential held only for that app launch,
and stops the helper when it exits. This retains the existing Kite integration while
removing backend addresses and connection pairing from the user flow.

This supersedes the independently configured Mac backend in
[ADR 0001](0001-keep-kite-integration-in-self-hosted-backend.md) and the Mac pairing flow in
[ADR 0002](0002-pair-backend-connections.md). Remote servers are outside the current
product scope. Standalone backend commands remain available for development.

Kite credentials live in an owner-only configuration folder outside the bundle. The
fixed loopback port preserves the registered browser callback. An occupied port fails
startup instead of attaching to an existing service. A private stdout signal confirms
that the child has bound its listener before the app sends any credential. Restarting the app loses the
in-memory Kite session and requires browser sign-in again.
