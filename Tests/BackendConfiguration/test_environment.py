"""Verify dotenv configuration through a real backend process and HTTP routes."""
import contextlib
import json
import os
from pathlib import Path
import socket
import subprocess
import tempfile
import time
import unittest
from urllib.parse import parse_qs, urlparse
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parents[2]
BASE = """KITE_API_KEY=dotenv-base-key
KITE_API_SECRET=dotenv-fixture-secret
UNARU_CONNECTION_TOKEN=dotenv-fixture-token
LOG_LEVEL=error
"""


class BackendEnvironmentTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        result = subprocess.run(
            ["swift", "build", "--package-path", str(ROOT / "backend"), "--show-bin-path"],
            check=True, capture_output=True, text=True,
        )
        cls.executable = Path(result.stdout.strip()) / "Backend"
        if not cls.executable.is_file():
            raise RuntimeError("Build Backend with swift test --package-path backend first.")

    @contextlib.contextmanager
    def backend(self, specific=None, process_values=None, arguments=()):
        # No developer credentials or login Keychain access enter these fixtures.
        environment = {key: value for key, value in os.environ.items() if not (
            key.startswith("KITE_") or key.startswith("UNARU_")
            or key in {"LOG_LEVEL", "VAPOR_ENV"}
        )}
        environment.update(process_values or {})
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            (directory / ".env").write_text(BASE)
            (directory / ".env.production").write_text("KITE_API_KEY=wrong-environment\n")
            if specific is not None:
                (directory / ".env.testing").write_text(specific)
            with socket.socket() as listener:
                listener.bind(("127.0.0.1", 0))
                port = listener.getsockname()[1]
            with (directory / "server.log").open("w+") as log:
                # Testing mode avoids native bootstrap publication and live Kite requests.
                process = subprocess.Popen(
                    [str(self.executable), "serve", "--env", "testing", "--hostname",
                     "127.0.0.1", "--port", str(port), *arguments],
                    cwd=directory, env=environment, stdout=log, stderr=subprocess.STDOUT,
                )
                address = f"http://127.0.0.1:{port}"
                try:
                    deadline = time.monotonic() + 15
                    while True:
                        if process.poll() is not None:
                            log.seek(0)
                            self.fail(f"Backend exited during startup:\n{log.read()}")
                        try:
                            with urlopen(address, timeout=0.25) as response:
                                self.assertEqual(response.status, 200)
                            break
                        except OSError:
                            if time.monotonic() >= deadline:
                                self.fail("Backend did not become ready within 15 seconds.")
                            time.sleep(0.05)
                    yield address, log
                finally:
                    process.terminate()
                    try:
                        process.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        process.kill()
                        process.wait(timeout=5)

    def login_key(self, address, token="dotenv-fixture-token"):
        headers = {"Authorization": f"Bearer {token}"}
        with urlopen(Request(address + "/session", headers=headers), timeout=2) as response:
            self.assertEqual(json.load(response)["state"], "signedOut")
        with urlopen(Request(address + "/login", data=b"", headers=headers), timeout=2) as response:
            attempt = json.load(response)
        self.assertIsInstance(attempt["expiresAt"], (int, float))
        return parse_qs(urlparse(attempt["browserURL"]).query)["api_key"][0]

    def test_base_file_configures_authentication_and_kite_login(self):
        with self.backend() as (address, log):
            self.assertEqual(self.login_key(address), "dotenv-base-key")
            log.seek(0)
            self.assertNotIn("GET /session", log.read())

    def test_selected_environment_file_overrides_base(self):
        with self.backend("KITE_API_KEY=dotenv-testing-key\n") as (address, _):
            self.assertEqual(self.login_key(address), "dotenv-testing-key")

    def test_process_environment_overrides_both_files(self):
        with self.backend("KITE_API_KEY=dotenv-testing-key\n", {
            "KITE_API_KEY": "process-key", "UNARU_CONNECTION_TOKEN": "process-token",
        }) as (address, _):
            self.assertEqual(self.login_key(address, "process-token"), "process-key")

    def test_log_option_overrides_dotenv_log_level(self):
        with self.backend(arguments=("--log", "info")) as (address, log):
            self.assertEqual(self.login_key(address), "dotenv-base-key")
            log.seek(0)
            self.assertIn("GET /session", log.read())


if __name__ == "__main__":
    unittest.main()
