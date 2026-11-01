# Pair backend connections instead of entering tokens

The Mac app generates and stores its connection credential in Keychain. A native backend bound to loopback publishes a bootstrap secret in the same user's login Keychain; access to that item allows automatic pairing, subject to macOS access control. Loopback network access alone grants no authority. Other connections require the backend owner to approve the app's short-lived comparison code through a server-side command using an owner-only data directory.

This replaces manual token setup while retaining the backend boundary in [ADR 0001](0001-keep-kite-integration-in-self-hosted-backend.md). Approved credential hashes persist across backend restarts, while Kite sessions remain in memory. Existing explicitly configured connection tokens remain accepted for migration. Container deployments use code approval because they do not share the host's login Keychain.
