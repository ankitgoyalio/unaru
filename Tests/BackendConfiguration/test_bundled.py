"""Exercise the actual helper with app-style authorization and parent lifetime."""
import json
import os
from pathlib import Path
import secrets
import select
import socket
import subprocess
import tempfile
import time
import unittest
from urllib.error import HTTPError
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parents[2]


class BundledBackendTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        result = subprocess.run(
            ["swift", "build", "--package-path", str(ROOT / "backend"), "--show-bin-path"],
            check=True, capture_output=True, text=True,
        )
        cls.executable = Path(result.stdout.strip()) / "Backend"

    def test_private_authorization_configuration_and_parent_exit(self):
        with socket.socket() as listener:
            listener.bind(("127.0.0.1", 0))
            port = listener.getsockname()[1]
        address = f"http://127.0.0.1:{port}"
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            (directory / ".env").write_text("KITE_API_KEY=\nKITE_API_SECRET=\nLOG_LEVEL=error\n")
            token = secrets.token_urlsafe(32)
            process = subprocess.Popen(
                [str(self.executable), "serve", "--hostname", "127.0.0.1", "--port", str(port)],
                cwd=directory,
                env={"PATH": os.environ["PATH"], "UNARU_BUNDLED": "1", "UNARU_CONNECTION_TOKEN": token},
                stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
            )
            try:
                readable, _, _ = select.select([process.stdout], [], [], 15)
                self.assertTrue(readable, "The child did not confirm listener ownership.")
                self.assertEqual(process.stdout.readline(), b"UNARU_READY\n")
                request = Request(address + "/session", headers={"Authorization": f"Bearer {token}"})
                deadline = time.monotonic() + 15
                while True:
                    self.assertIsNone(process.poll(), "Bundled helper exited before readiness.")
                    try:
                        with urlopen(request, timeout=0.25) as response:
                            self.assertEqual(json.load(response)["state"], "signedOut")
                        break
                    except OSError:
                        if time.monotonic() >= deadline:
                            self.fail("Bundled helper did not become ready.")
                        time.sleep(0.05)
                for path in ("/session", "/pairing"):
                    with self.assertRaises(HTTPError) as error:
                        urlopen(address + path, timeout=2)
                    self.assertEqual(error.exception.code, 401 if path == "/session" else 404)
                login = Request(address + "/login", data=b"", headers={"Authorization": f"Bearer {token}"})
                with self.assertRaises(HTTPError) as error:
                    urlopen(login, timeout=2)
                self.assertEqual(error.exception.code, 503)
                self.assertEqual(json.load(error.exception), {"code": "backendNotConfigured"})
                self.assertFalse((directory / ".unaru").exists())
                # Simulate an app crash: the OS closes its pipe without an HTTP shutdown call.
                process.stdin.close()
                self.assertEqual(process.wait(timeout=5), 0)
                with socket.socket() as listener:
                    self.assertNotEqual(listener.connect_ex(("127.0.0.1", port)), 0)
            finally:
                if process.stdin and not process.stdin.closed:
                    process.stdin.close()
                if process.poll() is None:
                    process.kill()
                    process.wait(timeout=5)
                process.stdout.close()
