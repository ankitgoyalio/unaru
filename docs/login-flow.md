# Login flow

The first version runs locally and supports one Zerodha account per installation. Each installation's owner supplies their own Kite app credentials through the backend's `.env` file.

## Sign-in screen

Use the [AirOps screen on Mobbin](https://mobbin.com/screens/34e45a12-f486-4d5a-b6dd-1bed5394496c) as the visual reference: a white sign-in area on the left and a pale green illustrated area on the right.

The primary action is **Sign in with Zerodha**.

Below it, show **Don't have a Zerodha account yet? Sign up**. The **Sign up** link opens `https://zerodha.com/open-account?c=SH1331` for Zerodha account registration.

## Session behavior

Zerodha is the only login method. Neon Postgres stores persistent dashboard sessions and Kite access tokens. The dashboard session persists across browser and backend restarts for up to 30 days unless the user logs out. Expiry of Kite access leaves the dashboard session active for viewing saved data; fresh broker data requires reconnection.

Reconnection sends the user through Kite login again. The Go backend exchanges the returned request token for a new access token and verifies that the returned Zerodha user ID matches the dashboard session before restoring broker access.

Signing out ends the dashboard session, clears its browser cookie, and invalidates its Kite access token. Saved portfolio data remains available after the next successful login.

See [ADR-0001](adr/0001-separate-dashboard-session-from-kite-access.md).

See [ADR-0002](adr/0002-use-neon-postgres-for-login-persistence.md) for the database choice.
