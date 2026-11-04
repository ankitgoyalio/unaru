"""Opt-in signed, sandboxed helper replacement using isolated fake authorization."""
import http.server
import json
import os
from pathlib import Path
import plistlib
import secrets
import select
import shutil
import socket
import subprocess
import tempfile
import threading
import unittest
from urllib.error import HTTPError
from urllib.parse import parse_qs, urlparse
from urllib.request import Request, urlopen
import uuid

ROOT = Path(__file__).resolve().parents[2]
IDENTITY = os.environ.get("UNARU_SIGNING_IDENTITY")


class FakeKite(http.server.BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def do_POST(self):
        self.server.exchanges += 1
        self.reply(True)

    def do_DELETE(self):
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b'{"status":"success","data":true}')

    def do_GET(self):
        self.server.profiles += 1
        if self.server.profile_status != 200:
            self.send_response(self.server.profile_status)
            self.end_headers()
            self.wfile.write(b'{"status":"error","error_type":"NetworkException","message":"Isolated temporary failure"}')
            return
        self.reply(False)

    def reply(self, exchange):
        data = dict(user_id="FAKE20", user_name="Isolated Fake Account", user_shortname="Fake",
                    user_type="individual", email="fake@example.invalid", broker="ZERODHA",
                    exchanges=[], products=[], order_types=[], avatar_url=None,
                    meta=dict(demat_consent="physical"))
        if exchange:
            data.update(api_key=self.server.api_key, access_token=self.server.access_token,
                        public_token="fake-public", refresh_token="", login_time="2026-11-04 10:00:00")
        self.send_response(200)
        self.end_headers()
        self.wfile.write(json.dumps(dict(status="success", data=data)).encode())


@unittest.skipUnless(IDENTITY, "Set UNARU_SIGNING_IDENTITY for isolated real Keychain acceptance")
class SessionLifecycleTests(unittest.TestCase):
    def test_signed_sandboxed_replacement_quit_crash_and_logout(self):
        namespace = str(uuid.uuid4()).upper()
        api_key = "fake20-" + secrets.token_hex(12)
        provider = http.server.ThreadingHTTPServer(("127.0.0.1", 0), FakeKite)
        provider.api_key = api_key
        provider.access_token = "fake20-" + secrets.token_hex(24)
        provider.exchanges = provider.profiles = 0
        provider.profile_status = 200
        thread = threading.Thread(target=provider.serve_forever, daemon=True)
        thread.start()
        self.addCleanup(provider.server_close)
        self.addCleanup(provider.shutdown)
        with tempfile.TemporaryDirectory(prefix="unaru-session-20-") as temporary:
            directory = Path(temporary)
            app = directory / "SessionHost.app"
            macos = app / "Contents/MacOS"
            helpers = app / "Contents/Helpers"
            macos.mkdir(parents=True)
            helpers.mkdir()
            host_id = "io.ankitgoyal.unaru.session-test." + namespace
            (app / "Contents/Info.plist").write_bytes(plistlib.dumps(dict(
                CFBundleIdentifier=host_id, CFBundleExecutable="SessionHost", CFBundlePackageType="APPL")))
            source = directory / "Host.swift"
            source.write_text('''import Foundation
if CommandLine.arguments.count >= 3, CommandLine.arguments[1] == "--test-storage-failure" {
    let url = URL(fileURLWithPath: CommandLine.arguments[2])
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    if CommandLine.arguments.count == 4 {
        try Data(CommandLine.arguments[3].utf8).write(to: url, options: .atomic)
    } else if FileManager.default.fileExists(atPath: url.path) {
        try FileManager.default.removeItem(at: url)
    }
    exit(0)
}
let child = Process()
let executable = URL(fileURLWithPath: CommandLine.arguments[0])
child.executableURL = executable.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Helpers/Backend")
child.arguments = Array(CommandLine.arguments.dropFirst())
let lifetime = Pipe()
child.standardInput = lifetime
child.standardOutput = FileHandle.standardOutput
child.standardError = FileHandle.standardError
try child.run()
try lifetime.fileHandleForReading.close()
DispatchQueue.global().async {
    _ = FileHandle.standardInput.readDataToEndOfFile()
    try? lifetime.fileHandleForWriting.close()
}
child.waitUntilExit()
exit(child.terminationStatus)
''')
            host = macos / "SessionHost"
            subprocess.run(["swiftc", str(source), "-o", str(host)], check=True, capture_output=True)
            entitlements = directory / "Host.entitlements"
            entitlements.write_bytes(plistlib.dumps({"com.apple.security.app-sandbox": True,
                "com.apple.security.network.client": True, "com.apple.security.network.server": True}))
            binary_dir = subprocess.check_output(["swift", "build", "--package-path", str(ROOT / "backend"),
                                                  "--show-bin-path"], text=True).strip()
            original = (Path(binary_dir) / "Backend").read_bytes()
            helper = helpers / "Backend"
            helper.write_bytes(original)
            helper.chmod(0o755)
            self.sign(helper, ROOT / "backend/BundledBackend.entitlements", "io.ankitgoyal.unaru.backend")
            self.sign(app, entitlements, host_id)
            first_hash = self.code_hash(helper)
            with socket.socket() as listener:
                listener.bind(("127.0.0.1", 0))
                port = listener.getsockname()[1]
            self.address = f"http://127.0.0.1:{port}"
            self.process = None
            self.token = None
            environment = dict(PATH=os.environ["PATH"], UNARU_BUNDLED="1", KITE_API_KEY=api_key,
                KITE_API_SECRET="fake20-secret-" + secrets.token_hex(16), LOG_LEVEL="error",
                UNARU_TEST_STORAGE=namespace, UNARU_TEST_KITE_URL=f"http://127.0.0.1:{provider.server_port}")
            failure_file = Path.home() / "Library/Containers" / host_id / "Data/Library/Application Support/session-store-failure"
            environment["UNARU_TEST_SESSION_FAILURE_FILE"] = str(failure_file)
            self.set_failure(host, failure_file, "save")
            try:
                self.launch(host, port, directory, environment)
                self.assertEqual(self.request("session")["state"], "signedOut")
                attempt = self.request("login", "POST")
                redirect = parse_qs(urlparse(attempt["browserURL"]).query)["redirect_params"][0]
                state = parse_qs(redirect)["state"][0]
                with urlopen(self.address + "/kite/callback?status=success&request_token=fake20-request&state=" + state) as response:
                    self.assertEqual(response.status, 200)
                self.assertEqual(self.request("login/" + attempt["id"])["state"], "signedIn")
                self.assertEqual(self.request("session").get("persistence"), "saveFailed")
                self.assertEqual(self.request("profile")["userID"], "FAKE20")
                self.assertEqual(self.request("session/save", "POST").get("persistence"), "saveFailed")
                self.set_failure(host, failure_file)
                self.assertEqual(self.request("session/save", "POST").get("persistence"), "saved")
                self.assertEqual(provider.exchanges, 1)
                old_token = self.token
                # Normal app quit closes its private child lifetime pipe.
                self.stop()
                # Different executable bytes, same developer and explicit helper identifier.
                self.assertIn(b"It works!", original)
                helper.write_bytes(original.replace(b"It works!", b"It works?"))
                self.sign(helper, ROOT / "backend/BundledBackend.entitlements", "io.ankitgoyal.unaru.backend")
                self.sign(app, entitlements, host_id)
                self.assertNotEqual(first_hash, self.code_hash(helper))
                provider.profile_status = 502
                self.launch(host, port, directory, environment)
                with self.assertRaises(HTTPError) as denied:
                    self.request("session", token=old_token)
                self.assertEqual(denied.exception.code, 401)
                self.assertNotIn("kiteSignInRequired", denied.exception.read().decode())
                for path in ("session", "profile", "session"):
                    with self.assertRaises(HTTPError) as failed:
                        self.request(path)
                    self.assertEqual(failed.exception.code, 503)
                    self.assertEqual(json.load(failed.exception), {"code": "kiteSessionUnavailable"})
                # Stop the actual helper while validation is still failing. In-memory retention
                # cannot satisfy recovery after this second launch and Keychain read.
                self.stop()
                self.launch(host, port, directory, environment)
                with self.assertRaises(HTTPError) as failed_again:
                    self.request("session")
                self.assertEqual(failed_again.exception.code, 503)
                self.assertEqual(json.load(failed_again.exception), {"code": "kiteSessionUnavailable"})
                provider.profile_status = 200
                self.assertEqual(self.request("session")["state"], "signedIn")
                self.assertEqual(self.request("profile")["userID"], "FAKE20")
                self.assertGreaterEqual(provider.profiles, 3)
                self.assertEqual(provider.exchanges, 1)
                # Killing the sandboxed parent closes its private pipe, stopping the helper.
                self.process.kill()
                self.process.wait(timeout=5)
                self.process.stdin.close()
                self.process.stdout.close()
                self.process = None
                self.launch(host, port, directory, environment)
                self.assertEqual(self.request("session")["state"], "signedIn")
                self.assertEqual(provider.exchanges, 1)
                self.set_failure(host, failure_file, "delete")
                with self.assertRaises(HTTPError) as deletion:
                    self.request("logout", "POST")
                self.assertEqual(deletion.exception.code, 503)
                # No completed local logout claim while secure removal is failing.
                with self.assertRaises(HTTPError) as hidden:
                    self.request("session")
                self.assertEqual(hidden.exception.code, 503)
                self.stop()
                self.launch(host, port, directory, environment)
                # A client retaining logout intent retries removal before restoration.
                with self.assertRaises(HTTPError):
                    self.request("logout", "POST")
                self.set_failure(host, failure_file)
                self.assertEqual(self.request("logout", "POST")["revocation"], "unconfirmed")
                self.stop()
                self.launch(host, port, directory, environment)
                self.assertEqual(self.request("session")["state"], "signedOut")
                print("Signed sandbox helper: changed code hash, quit/crash restoration, fresh launch credential, transient validation/restart/retry, save failure/retry, delete failure/restart/retry passed")
            finally:
                if self.process is not None and self.process.poll() is None:
                    # Cleanup is scoped to this UUID and fake API key, even after assertion failure.
                    try:
                        self.request("logout", "POST")
                    except Exception:
                        pass
                self.stop()
                # Remove only this test's item if the helper failed before cleanup.
                import hashlib
                service = "io.ankitgoyal.unaru.kite-session.test." + namespace
                subprocess.run(["security", "delete-generic-password", "-s", service,
                    "-a", hashlib.sha256(api_key.encode()).hexdigest()], capture_output=True)
                shutil.rmtree(Path.home() / "Library/Containers" / host_id, ignore_errors=True)

    def set_failure(self, host, path, operation=None):
        arguments = [str(host), "--test-storage-failure", str(path)]
        if operation:
            arguments.append(operation)
        subprocess.run(arguments, check=True, capture_output=True, env={"PATH": os.environ["PATH"]})

    def sign(self, path, entitlements, identifier):
        subprocess.run(["codesign", "--force", "--sign", IDENTITY, "--identifier", identifier,
            "--options", "runtime", "--entitlements", str(entitlements), str(path)], check=True, capture_output=True)

    def code_hash(self, helper):
        result = subprocess.run(["codesign", "-d", "--verbose=4", str(helper)], capture_output=True, text=True, check=True)
        return next(line for line in (result.stderr + result.stdout).splitlines() if line.startswith("CDHash="))

    def launch(self, host, port, directory, environment):
        self.token = secrets.token_urlsafe(32)
        self.process = subprocess.Popen([str(host), "serve", "--hostname", "127.0.0.1", "--port", str(port)],
            cwd=directory, env=environment | {"UNARU_CONNECTION_TOKEN": self.token},
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        ready, _, _ = select.select([self.process.stdout], [], [], 20)
        self.assertTrue(ready, "Signed sandbox helper failed to become ready")
        self.assertEqual(self.process.stdout.readline(), b"UNARU_READY\n")

    def stop(self):
        if self.process is None:
            return
        if not self.process.stdin.closed:
            self.process.stdin.close()
        try:
            self.process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            self.process.kill()
            self.process.wait(timeout=5)
        self.process.stdout.close()
        self.process = None

    def request(self, path, method="GET", token=None):
        request = Request(self.address + "/" + path, method=method,
                          headers={"Authorization": "Bearer " + (token or self.token)})
        with urlopen(request, timeout=5) as response:
            data = response.read().decode()
            self.assertNotIn("fake20-secret", data)
            self.assertNotIn("access_token", data)
            return json.loads(data)
