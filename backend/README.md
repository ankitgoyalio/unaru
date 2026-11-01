# Connect the Mac app to your backend

1. Install the tools listed in [Development](../docs/development.md).
2. Generate a separate random connection token in your password manager.
3. Set `UNARU_CONNECTION_TOKEN` in the backend process environment through your
   service manager or secret store. Use a nonempty token with printable ASCII
   characters and no spaces. Keep this token separate from Kite credentials.
4. From the repository root, start the backend bound to loopback:

   ```fish
   swift run --package-path backend Backend serve --hostname 127.0.0.1 --port 8080
   ```

5. Open Unaru on your Mac and choose **Configure Connection**. You can also open
   **Unaru > Settings** with Command-comma.
6. Enter `http://127.0.0.1:8080` as the backend address and enter the same connection
   token in the separate secure field.
7. Choose **Save Connection**. A successful check displays **Kite Sign-In Required**.

The backend address survives app restarts in preferences. The connection token
is stored in Keychain. Unaru verifies the saved connection again at launch.
Choose **Sign in with Kite** in the main window to open your default browser.
Complete Kite authentication, then return to Unaru. The account name and Kite
user ID appear at the bottom of the sidebar after the backend retrieves the
profile. No token copying is needed. Hiding the sidebar keeps sign-in available.

## Connect to a remote server

1. Configure your server or reverse proxy to expose the backend through HTTPS
   with a certificate trusted by your Mac. Forward the `Authorization` header.
2. Set `UNARU_CONNECTION_TOKEN` in the backend environment. For Docker Compose,
   supply it through the host environment or an untracked environment file.
3. Enter the final HTTPS backend address in Unaru Settings. A path prefix is
   supported when the proxy routes `<prefix>/session` to the backend's `/session`.
4. Enter the connection token and choose **Save Connection**.

HTTP is accepted only for literal loopback addresses or `localhost`. The app
refuses redirects, embedded address credentials, query parameters, and fragments.
Use the final HTTPS address rather than an address that redirects. Keep request
headers out of proxy logs. Never put credentials in URLs or commit them to Git.

## Configure Kite browser login

1. Create a Kite Connect app in the [Kite developer console](https://developers.kite.trade/).
2. Register the backend callback as the app's redirect URL. For a backend on this
   Mac, use `http://127.0.0.1:8080/kite/callback`. For a remote backend, use
   `https://your-server.example/kite/callback`. Include the public path prefix
   if your reverse proxy uses one, and forward that path to `/kite/callback`.
3. Set `KITE_API_KEY` and `KITE_API_SECRET` in the backend process environment
   through your service manager or secret store. Keep the separate
   `UNARU_CONNECTION_TOKEN` configured. Docker Compose forwards all three.
4. Restart the backend. Allow outbound HTTPS to `api.kite.trade` and ensure the
   browser can reach `kite.zerodha.com` and the registered callback address.
5. Save your connection in Unaru, then choose **Sign in with Kite**. The browser
   uses the public API key. The API secret and access token stay on the backend.
6. Finish login within five minutes and return to Unaru. The callback page tells
   you to return. Unaru observes completion through authorized HTTP polling.

Kite's [login documentation](https://kite.trade/docs/connect/v3/user/#login-flow)
specifies `redirect_params` as a URL-encoded query string returned to the
registered redirect. Unaru uses `state=<random-value>` within that parameter,
rather than assuming Kite echoes an OAuth `state` parameter directly.
The [desktop guidance](https://kite.trade/docs/connect/v3/apps/) permits a
personal loopback redirect. The browser must run on the backend's Mac for a
loopback callback; use your public HTTPS backend address otherwise.

Each installation serves one Kite account and keeps its access token only in
memory. Restarting the backend requires another login. A new login supersedes
any earlier attempt. Cancellation and the five-minute deadline reject old
callbacks, including exchanges or profile responses already in flight. Callback
authority is consumed before exchange, so a failed exchange needs a new login.
A temporary profile failure permits **Retry Sign-In** without replaying exchange.
Closing a browser tab does not notify Unaru. Choose **Cancel Sign-In**, or let
the attempt expire, then try again.

Configure proxy access logs to omit query strings, request bodies, and
Authorization headers, particularly on `/kite/callback`. Kite supplies its
short-lived request token in that callback query. Unaru returns plain text with
no external resources, `Cache-Control: no-store`, and `Referrer-Policy: no-referrer`.
Never put the connection token, API secret, or access token in a browser URL.
The app opens the default browser in production. Debug UI tests with isolated
storage replace only that browser handoff with a controlled HTTP receipt;
they never open a real Kite session or use browser cookies.

## Recover a connection

- If the backend rejects the connection token, open Settings and correct it.
- If the backend is unavailable, restore connectivity and choose **Retry** in
  the main window. You do not need to repeat setup.
- If the server has no valid connection token, set `UNARU_CONNECTION_TOKEN` on
  the server, restart it, and retry. This failure does not mean Kite login expired.
- If Keychain is locked or unavailable, unlock it and reopen Settings.

Changing saved settings cancels earlier verification and discards its result.
The main window keeps setup and retry accessible when the sidebar is hidden.

See the [backend contract](Sources/Backend/Backend.docc/Backend.md) for HTTP details
and [Development](../docs/development.md) for checks.
