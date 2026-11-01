# Keep Kite integration in the self-hosted backend

Unaru is self-hosted for personal use. Keep SwiftKiteConnect in the backend for the Kite token exchange and profile requests. The macOS app displays the resulting profile.

A standalone Mac app could own the Kite integration for personal use. Keeping the existing backend boundary avoids moving credentials and Kite integration into the app, at the cost of requiring a running backend.

The app opens the default browser for Kite login. The backend handles the redirect and token exchange before the app resumes. The backend address is configurable so the backend can run on the same Mac or on a self-hosted server.

Each backend installation serves one Kite account. The backend owns the Kite API key, API secret, and access token. A separate connection token authorizes app requests; the app stores that token in Keychain.
