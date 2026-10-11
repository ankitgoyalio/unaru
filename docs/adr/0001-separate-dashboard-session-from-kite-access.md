# Keep the dashboard session independent of Kite access

The local dashboard uses Zerodha as its only login method. After a successful Kite login, it creates its own session so the user can continue viewing saved data after Kite access expires. Expiry or invalidation of Kite access requires reconnection for fresh broker data and does not, by itself, end the dashboard session.

This separates access to saved dashboard data from the lifetime of broker authorization. The dashboard session persists across browser and backend restarts for up to 30 days unless the user logs out. A persistent browser cookie identifies a server-side session record.

Each local installation supports one Zerodha account. Its owner supplies their own Kite app API key and secret through the backend's `.env` file; the application does not hardcode the developer's Zerodha account ID.

Signing out ends the dashboard session and invalidates its Kite access token. It retains saved portfolio data for the next successful login.
