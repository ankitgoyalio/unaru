# Run Unaru with its bundled backend

Build and open the Mac app. Its build phase embeds the native backend in
`unaru.app/Contents/Helpers/Backend`. The app starts that helper automatically; there is
no backend address, Connect button, or pairing step.

1. Register `http://127.0.0.1:8080/kite/callback` as your Kite Connect app's redirect URL.
2. Open Unaru and choose **Sign in with Kite**.
3. If **Set Up Kite** appears, choose **Open Configuration Folder**. Edit the `.env`
   template and fill in `KITE_API_KEY` and `KITE_API_SECRET` from your Kite developer app.
4. Choose **Retry**, then **Sign in with Kite** to complete login in your browser.

The configuration folder is `Unaru` inside the app's Application Support directory.
For the sandboxed Mac app, this is normally
`~/Library/Containers/io.ankitgoyal.unaru/Data/Library/Application Support/Unaru`.
The app creates the folder with mode 700 and the template with mode 600. Credentials
stay outside the signed bundle. Existing checkout dotenv files and saved remote
connection settings are not imported. Copy your Kite values into this template once.

The app generates an internal authorization credential for each launch and passes it
directly to its child process. It does not save a connection credential in Keychain or
publish pairing authority. The helper listens only on `127.0.0.1:8080`; an occupied port
shows a startup error with **Retry**. Close the conflicting service and retry. The app
never attaches to another running backend. It stops its helper on quit, including an
abrupt exit. Kite sessions stay in memory, so quitting requires another browser login.
Closing a window alone keeps the session available.

## Run a standalone backend for development

The following commands are for backend development. The Mac app always uses its own
embedded helper.

Install the tools in [Development](../docs/development.md). Copy `.env.example` to
`backend/.env` and set its Kite credentials. From the backend directory, run:

```fish
swift run Backend serve --hostname 127.0.0.1 --port 8080
```

Stop the standalone process before opening the Mac app because they share the callback
port. Standalone pairing and container support remain available for backend testing.

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

## Preserve standalone pairing state

Standalone backends retain the pairing API and `Backend pair <code>` approval command
for development clients. They store approval state in `~/.unaru` or
`UNARU_DATA_DIRECTORY`. Keep this directory private and persistent. Container builds
use the Compose named volume. The bundled app does not read or write this registry.

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
5. In a development client, initiate the authorized browser login. The browser
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

## Recover the bundled app

- For a local startup error, close other copies or services using port 8080 and choose
  **Retry**. If the embedded helper is missing, rebuild or reinstall the app.
- For **Set Up Kite**, edit the app-owned `.env` and choose **Retry** to reload it.
- For a temporary network or Kite failure, restore connectivity and choose **Retry**.
  The app validates an existing Kite session before displaying identity.
- For **Retry Sign-In**, retry the pending read without another token exchange or
  browser handoff. Cancelled, denied, or expired attempts need a new sign-in.

See the [backend contract](Sources/Backend/Backend.docc/Backend.md) for HTTP details and
[Development](../docs/development.md) for checks.
