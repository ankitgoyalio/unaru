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
This slice verifies backend access only. Browser login and account identity are
implemented in the following slice, so no sign-in action is available yet.

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
