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

Live acceptance passed on 2026-10-11. The backend and frontend ran on Linux with the owner's locally configured Kite app and Neon database. The owner authenticated personally from their Mac through an SSH tunnel. Broker credentials and authentication challenges stayed on Zerodha's hosted page.

1. The owner confirmed successful first login, return to the connected dashboard, and the expected account. This exercised the registered callback and backend token exchange.
2. The backend restarted with the same configuration and database. The owner confirmed the dashboard session restored after quitting and reopening the same browser profile without another login.
3. `go run ./cmd/verify-live reconnect` reported `capture: PASS` and `verification: PASS`. The command invalidated real Kite access, then verified restored access after user-driven reconnection with unchanged dashboard session identifiers and absolute expiry.
4. The owner confirmed logout returned to sign-in. `go run ./cmd/verify-live logout` reported `verification: PASS`, confirming revocation of the captured dashboard session and Kite's documented token-invalid response for the previous access token.
5. The owner confirmed a fresh login succeeded after logout.
6. An isolated Chromium browser opened the exact referral destination through keyboard activation. Tab and Shift+Tab reached the sign-in and sign-up controls with visible three-pixel focus outlines. Enter on sign-in opened Kite's hosted login; no broker authentication was automated.
7. The finished sign-in screen was inspected at desktop width and at 320 CSS pixels. At 320 pixels, the document width matched the viewport, all controls fit, text remained readable, and the page had no horizontal overflow. The desktop composition retained the inspected AirOps reference's white and pale green split.

No failures remained in these acceptance scenarios. The manual UI check used Chromium on Linux; it does not establish compatibility with every Mac browser or full accessibility conformance. Automated expiry, replay, outage, and identity-mismatch tests supplement the live checks.

The [live acceptance guide](live-acceptance.md) describes how to repeat these checks. No credentials, token values, or account identifiers are recorded here.

## Final interface revision

The owner subsequently replaced the AirOps direction with a supplied Folk sign-in reference. The final interface uses a white canvas, a top-left wordmark, and centered account panels across sign-in, dashboard, and recovery states. It uses Tailwind CSS v4, self-hosted Inter, and the existing Zerodha asset. Fixed layout spacing follows an 8-pixel scale, with 8-pixel corner radii, 8-pixel heading-to-subtitle spacing, and a 16-pixel margin before the signup row.

The final production build and 11 targeted Chromium checks passed. These checks cover keyboard sign-in, the referral destination, session recovery and expiry, broker outages, enlarged and spaced text at 320 CSS pixels, forced colors, and pending authentication actions with retry. Dashboard and recovery screens were also inspected with mock account data. This revision changes presentation and copy; the live authentication results above were recorded before this visual revision.
