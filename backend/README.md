# Connect the Mac app to your backend

1. Install the tools listed in [Development](../docs/development.md).
2. Create your local configuration once:

   ```fish
   cp -n backend/.env.example backend/.env
   chmod 600 backend/.env
   ```

   Edit `backend/.env` and fill in `KITE_API_KEY` and `KITE_API_SECRET` from the
   [Kite developer console](https://developers.kite.trade/). The [example file](.env.example)
   describes every backend variable. Existing process variables take precedence over files.
3. Change into the backend directory, then start the native backend bound to loopback:

   ```fish
   cd backend
   swift run Backend serve --hostname 127.0.0.1 --port 8080
   ```

4. Open Unaru and choose **Configure Connection**, or open **Unaru > Settings** with Command-comma.
5. Enter `http://127.0.0.1:8080` as the backend address and choose **Connect**.
6. If macOS requests Keychain access, review and allow Unaru to read the backend's local pairing item. A native backend running as the same Mac user can then pair automatically. If Keychain sharing is unavailable, use the approval steps below.
7. After connection verification, return to the main window and choose **Sign in with Kite**.

There is no connection token to create or copy. Unaru generates a credential and stores
it in Keychain only after the backend approves it. The backend stores the approved
public verification key. Kite API secrets and access tokens stay on the backend.

## Load configuration automatically

Vapor loads `.env` from the backend process working directory. Start the backend from
this checkout's `backend` directory, as shown above. `swift run --package-path backend`
from the repository root does not make the running server use `backend` as its working
directory. An installed executable also reads dotenv files from its process working directory. In Xcode,
set the Backend scheme's custom working directory to this checkout's `backend` folder.

For deployment, `--env production` selects `.env.production` as an optional override.
Precedence is process environment, then `.env.<environment>`, then `.env`.
The default environment is `development`. Select it with `--env` or a process-level
`VAPOR_ENV`; setting `VAPOR_ENV` inside a dotenv file does not select the environment.
Restart the backend after edits. If old shell exports override your file, remove them
from that shell with `set -e KITE_API_KEY KITE_API_SECRET` before launch.

Real dotenv files are ignored by Git and excluded from Docker build contexts. The Mac
app does not read them. Keep the secret file on the backend host. Production services
can keep supplying variables through their service manager or secret store instead.
Vapor's [environment guide](https://docs.vapor.codes/basics/environment/) describes the file format.

For Docker Compose, supply the same file explicitly from the repository root:

```fish
docker compose --env-file backend/.env -f backend/docker-compose.yml up --build
```

Compose passes the Kite variables into the container and keeps pairing state in its
named volume. It uses `/app/.unaru` rather than a native `UNARU_DATA_DIRECTORY` override.
It does not automatically load your native `.env.production` override.

## Approve a remote or container connection

1. Expose the backend through HTTPS with a certificate trusted by your Mac. Forward `X-Unaru-Key`, `X-Unaru-Signature`, `X-Unaru-Timestamp`, and `X-Unaru-Nonce`. Forward `Authorization` for legacy clients. For a container on the same Mac, loopback HTTP also works.
2. Enter the final backend address in Unaru Settings and choose **Connect**.
3. Compare the eight-digit pairing code shown in Unaru. On the backend host, use the same user and data directory as the running backend. From the checkout's `backend` directory, run:

   ```fish
   swift run Backend pair 12345678
   ```

   Replace `12345678` with the code shown on your Mac. With an installed executable, run `Backend pair 12345678`. For Docker Compose:

   ```fish
   docker compose -f backend/docker-compose.yml exec app ./Backend pair 12345678
   ```

4. Approve only the code from the Mac you intend to connect. The code expires after five minutes. Unaru finishes connection automatically; subsequent launches do not require approval again.

The code is a comparison value, not a password. Knowing a code or reaching the server
does not authorize a client. Approval requires filesystem access under the backend
owner's identity. **Cancel Connection** invalidates the pending request. A cancelled or
expired request requires **Connect** again.

The native same-Mac path requires a loopback-bound backend, the same login Keychain, and
an address without a proxy path prefix. A different user, a container, a remote server,
or denied Keychain access uses code approval. Unaru never treats a loopback address
alone as authorization.

## Preserve backend pairing state

Pairing state lives in `~/.unaru` under the backend process user's home. Set
`UNARU_DATA_DIRECTORY` to use another persistent directory. The directory is owner-only
and contains approved public verification keys, local bootstrap authority, and short-
lived approval metadata. Keep it private and use a separate directory for each backend
installation. Run only one backend process per directory.

Docker Compose stores it in a named volume at `/app/.unaru`. Preserve that volume across
container recreation. Signed requests include a timestamp and unique nonce; keep the Mac
and backend clocks synchronized to within one minute. Approved Mac connections survive
backend restarts; the in-memory Kite session does not. Deleting installation state
revokes paired credentials and requires pairing again. Up to 64 credentials and 32
concurrent pending requests are supported.

Existing `UNARU_CONNECTION_TOKEN` configuration remains supported for already connected
apps during migration. New users do not configure it. Reconnecting to the same saved
address reuses the app’s private key. A different address creates a new key and requires
pairing.

HTTP is accepted only for loopback addresses or `localhost`; remote connections require
HTTPS. The app refuses redirects, embedded URL credentials, query parameters, and
fragments. Use the final backend URL. A reverse proxy path prefix is supported when
routes such as `<prefix>/pairing` reach `/pairing`. Keep credential headers, pairing
request bodies, and callback query strings out of proxy logs.

## Configure Kite browser login

1. Create a Kite Connect app in the [Kite developer console](https://developers.kite.trade/).
2. Register the backend callback as the app's redirect URL. For a backend on this
   Mac, use `http://127.0.0.1:8080/kite/callback`. For a remote backend, use
   `https://your-server.example/kite/callback`. Include the public path prefix
   if your reverse proxy uses one, and forward that path to `/kite/callback`.
3. Fill in `KITE_API_KEY` and `KITE_API_SECRET` in `backend/.env`, as described above.
   Docker Compose forwards both Kite variables. Connection credentials are created by pairing.
4. Restart the backend. Allow outbound HTTPS to `api.kite.trade` and ensure the
   browser can reach `kite.zerodha.com` and the registered callback address.
5. Connect Unaru to the backend as described above, then choose **Sign in with Kite**. The browser
   uses the public API key. The API secret and access token stay on the backend.
6. Finish login within five minutes and return to Unaru. The callback page tells
   you to return. Unaru observes completion through authorized HTTP polling.

Kite's [login documentation](https://kite.trade/docs/connect/v3/user/#login-flow)
specifies `redirect_params` as a URL-encoded query string returned to the registered
redirect. Unaru uses `state=<random-value>` within that parameter, rather than assuming
Kite echoes an OAuth `state` parameter directly. The [desktop
guidance](https://kite.trade/docs/connect/v3/apps/) permits a personal loopback
redirect. The browser must run on the backend's Mac for a loopback callback; use your
public HTTPS backend address otherwise.

Each installation serves one Kite account and keeps its access token only in memory.
Restarting the backend requires another login. A new login supersedes any earlier
attempt. Cancellation and the five-minute deadline reject old callbacks, including
exchanges or profile responses already in flight. Callback authority is consumed before
exchange, so a failed exchange needs a new login. A temporary profile failure permits
**Retry Sign-In** without replaying exchange. Closing a browser tab does not notify
Unaru. Choose **Cancel Sign-In**, or let the attempt expire, then try again.

Configure proxy access logs to omit query strings, request bodies, and Authorization
headers, particularly on `/kite/callback`. Kite supplies its short-lived request token
in that callback query. Unaru returns plain text with no external resources, `Cache-
Control: no-store`, and `Referrer-Policy: no-referrer`. Never put the connection
credential, API secret, or access token in a browser URL. The app opens the default
browser in production. Debug UI tests with isolated storage replace only that browser
handoff with a controlled HTTP receipt; they never open a real Kite session or use
browser cookies.

## Restore a Kite session

Reopen Unaru with the backend running. Unaru restores the saved address and Keychain
connection credential, shows **Verifying Connection…**, and asks the backend for the
current profile before displaying the account footer. The backend uses its in-memory
Kite access token for a fresh provider request. The app stores no Kite token, cached
authenticated identity, or separate app session reference. An unfinished browser attempt
is not restored after the app quits.

Kite access tokens normally expire at 6 AM the following day and can be revoked earlier.
Unaru handles Kite's authentication response rather than a local expiry timer. If Kite
rejects the token, choose **Sign in with Kite** and complete browser login again. A
backend restart also requires login because it discards the in-memory Kite session.
Saved app connection settings remain available.

## Recover a connection

- If the backend rejects this Mac’s connection credential, open Settings and choose **Connect** to pair again.
- If your network, backend, or Kite is temporarily unavailable, restore
  connectivity and choose **Retry** in the main window. Unaru retains your
  connection configuration and validates the existing session again. A temporary
  failure hides authenticated identity until validation succeeds; it does not
  discard the backend's Kite session or open another browser login.
- If login completion encounters a temporary profile failure, choose
  **Retry Sign-In**. This retries the same attempt without repeating token exchange
  or opening the browser again. A cancelled, denied, or expired attempt needs
  **Sign in with Kite** instead.
- If the backend cannot read or write its pairing directory, correct its filesystem permissions and restart it. This failure does not mean Kite login expired.
- If Keychain is locked or unavailable, unlock it and reopen Settings.

Connecting to a different backend or pairing again clears the current identity and
cancels earlier verification or login. Delayed responses cannot restore the previous
connection's identity. The main window keeps setup and retry accessible when the sidebar
is hidden.

See the [backend contract](Sources/Backend/Backend.docc/Backend.md) for HTTP details and
[Development](../docs/development.md) for checks.