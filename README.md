# Unaru

A local investment dashboard with Zerodha sign-in. Each installation links to one Zerodha account. The owner supplies their own Kite application and Neon database.

## Run locally

Install Go 1.25 or newer, Node.js 22 or newer, and pnpm 10.

1. Create your own Kite Connect application and a Neon database. Register `http://localhost:5173/api/auth/callback` as the Kite redirect URL.
2. Copy `backend/.env.example` to `backend/.env`. Set your Kite API key, secret, and Neon connection string in that local file.
3. Generate encryption key material with `openssl rand -base64 32`. Set `TOKEN_ENCRYPTION_KEY` in the local file. Retain this key across backend restarts so stored broker tokens remain readable.
4. Run `pnpm install` at the repository root.
5. Run `go run ./cmd/server` from `backend`. The backend runs the same embedded Postgres migrations for Neon and test databases.
6. Run `pnpm dev` from the repository root. Open `http://localhost:5173` and choose **Sign in with Zerodha**.
7. Complete broker login and any authentication challenges yourself on Zerodha. Never put passwords, authentication codes, or configuration secrets in chat.

Keep the browser origin and registered callback origin identical. Vite proxies `/api` to the loopback backend, so API calls and browser cookies use one origin. HTTP is accepted only on loopback. An HTTPS `APP_ORIGIN` makes authentication cookies Secure. Do not place backend secrets in `VITE_` variables.

Configuration errors identify the missing setting without printing its value. If sign-in fails, check backend availability and the registered callback, then use the sign-in action again.

## Run automated checks

Use an isolated test database. The Go and browser tests create isolated schemas in that database.

```sh
docker run -d --name unaru-test-postgres -e POSTGRES_PASSWORD=test -e POSTGRES_DB=unaru_test -p 127.0.0.1:55432:5432 postgres:17
cd backend
TEST_DATABASE_URL='postgres://postgres:test@127.0.0.1:55432/unaru_test?sslmode=disable' go test ./...
```

From the repository root, run `pnpm build`, `pnpm --filter @unaru/frontend exec playwright install chromium`, and `TEST_DATABASE_URL='postgres://postgres:test@127.0.0.1:55432/unaru_test?sslmode=disable' pnpm test:browser`. Browser checks use fake provider responses and do not require Kite credentials.

## Authentication design

`backend/auth` owns configuration, database migrations, HTTP authentication, and the official Go SDK adapter. `Broker` is the external provider boundary. `NewServer` accepts a clock for absolute-expiry tests. The server stores hashes of opaque browser identifiers and AES-GCM ciphertext for broker tokens. Identity linking, dashboard session creation, and broker authorization replacement share one transaction.

Login uses Kite's documented `redirect_params` to return the attempt identifier, with a separate HttpOnly browser binding. Attempts expire after five minutes and are consumed before exchange. A callback cannot be replayed after a failed exchange. The dashboard cookie expires 30 days after login; requests do not extend it.

See the [Kite login contract](https://kite.trade/docs/connect/v3/user/), [official Go SDK](https://github.com/zerodha/gokiteconnect), and [Neon Go guide](https://neon.com/docs/guides/go).

Sign-in and recovery states follow the supplied Folk reference, with a white canvas, a top-left wordmark, and a compact centered account panel. Signed-in pages use a desktop sidebar or a mobile navigation drawer. Profile contains account details, the broker connection, and logout. Inter is self-hosted under the SIL Open Font License. Zerodha remains the authentication provider.

Real Kite acceptance passed with the installation owner on 2026-10-11. See the [verification record](docs/verification-zerodha-login.md) for results and the [live acceptance guide](docs/live-acceptance.md) to repeat the scenarios with your own local configuration.
