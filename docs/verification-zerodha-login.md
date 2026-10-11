# Zerodha login verification

Verification date: 2026-10-11.

Implementation branch: `t3/implement-spec-3`.

## Automated results

The checks passed against fake Kite responses and an isolated real PostgreSQL database. No production Neon data or real broker credentials were used.

- `go test -race ./...` passed from `backend` with `TEST_DATABASE_URL` configured for the isolated database.
- `go vet ./...` passed from `backend`.
- `pnpm test:browser` passed from the repository root. This command builds the frontend and runs 12 Chromium scenarios.
- `git diff --check` passed.

The HTTP tests cover first login, callback binding and replay rejection, identity matching, absolute expiry, backend restart, stale database connection recovery, broker outages, reconnection, and logout. Concurrent login and reconnect callbacks cannot restore access after logout. Logout retains the linked identity and a saved-data fixture. Encrypted pending revocations survive backend restart and retry without delaying local logout.

The browser tests cover the login path, referral destination, keyboard controls, a 320-pixel layout, persisted browser cookies, session refresh and expiry, reconnection recovery, broker outages, and logout. Secret-marker assertions cover API responses, cookies, browser storage, generated frontend files, and captured logs. Real HTTP adapter tests cover cancellation, token-error classification, and SDK logging.

The exact AirOps reference was retrieved through Mobbin and inspected during implementation. The login screen uses its white and pale green composition with original investment artwork.

## Review results

The standards review raised three findings. The spec review raised three findings. All six were fixed in `a0e2bcf` and integrated in `de0c2ff`. Both reviewers rechecked the fixes and found no remaining material issues.

## Live acceptance

Live verification is pending. The installation owner agreed to prepare their Kite and Neon settings locally. No real Kite login or live Neon scenario has been observed, and the feature is not fully verified.

The following scenarios remain pending:

1. Real hosted login, registered callback, token exchange, expected-account match, and connected landing screen.
2. Dashboard access after browser and backend restarts.
3. Supported Kite token invalidation followed by same-account reconnection, preserving dashboard session identifiers and absolute expiry.
4. Logout ending dashboard access and invalidating the previous real broker token.
5. A fresh login after logout.

Follow [the live acceptance guide](live-acceptance.md). Record each observed outcome and failure without credentials, token values, or account identifiers. Keep issue #8 and parent spec #3 open until the required live scenarios pass.
