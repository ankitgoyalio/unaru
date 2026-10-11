# Verify live Zerodha login

Run the automated Go and browser checks in [README](../README.md) before using your live configuration. Keep the backend and frontend running with your own Kite app and Neon settings in `backend/.env`. Register `http://localhost:5173/api/auth/callback` in your Kite app and open `http://localhost:5173`.

Complete every Zerodha login and authentication challenge yourself in the browser. Keep credentials, authentication codes, callback URLs, and account identifiers out of chat and test records.

1. Choose **Sign in with Zerodha**. Confirm that you return to `/dashboard`, the expected account is linked, and the dashboard says **Connected to Zerodha**. Record account matching as pass or fail without the identifier.
2. Restart the backend with the same configuration and encryption key. Close and reopen the same browser profile. Confirm that the dashboard remains signed in and connected.
3. In a separate terminal, run this command from `backend`:

   ```sh
   go run ./cmd/verify-live reconnect
   ```

   Wait for `capture: PASS`. The command invalidates the stored Kite token through Kite's supported API while preserving dashboard sessions. Reload the dashboard and confirm that you remain signed in and see **Reconnect with Zerodha**. Choose that action and complete Zerodha login with the same account. Confirm that connected access returns. The command prints `verification: PASS` only after confirming new broker access and unchanged dashboard session identifiers and absolute expiry.
4. While connected, run this command from `backend`:

   ```sh
   go run ./cmd/verify-live logout
   ```

   Wait for `capture: PASS`, then choose **Log out** in the dashboard. Confirm that the sign-in screen returns. The command prints `verification: PASS` only after observing revocation of a captured dashboard session and Kite's documented token-invalid response for the previous broker token.
5. Choose **Sign in with Zerodha** again and confirm that a fresh login succeeds.
6. Confirm the registration link opens `https://zerodha.com/open-account?c=SH1331`. Check keyboard operation and the login layout at a narrow browser width.

Both verification commands stop after five minutes. A `verification: FAIL` means the scenario remains unverified. Check local configuration and broker availability, then repeat from a connected dashboard. Do not start another login or logout in another browser while a verification command runs. These commands retain tokens and session comparisons only in process memory and print no credentials or identifiers.

For manual token invalidation without the session comparison, run `go run ./cmd/invalidate-broker` from `backend`. Reload the dashboard afterward and reconnect through the supported login action.

Record the date, each scenario, pass or fail, and any failure in plain language. Keep live acceptance pending until every required scenario passes. Automated fake-broker tests do not replace these checks.
