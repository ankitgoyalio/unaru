"""Exercise header generation, staged checks, and squash merges with SwiftFormat."""

from datetime import datetime, timezone
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
HEADER = b"//\n//  old.swift\n//  unaru\n//\n//  Created by Original Author on 02/01/2020.\n\n"


class SwiftFormatWorkflowTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        binary = os.environ.get("SWIFTFORMAT_TEST_BINARY") or shutil.which("swiftformat")
        if not binary:
            raise unittest.SkipTest("SwiftFormat is unavailable")
        version = subprocess.run([binary, "--version"], capture_output=True, check=True)
        if version.stdout.strip() != b"0.64.5":
            raise unittest.SkipTest("SwiftFormat 0.64.5 is required")
        cls.binary = Path(binary).resolve()

    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.directory = Path(temporary.name)
        self.repo = self.directory / "repo"
        self.repo.mkdir()
        self.env = {key: value for key, value in os.environ.items() if not key.startswith("GIT_")}
        self.env["PATH"] = str(self.binary.parent) + os.pathsep + self.env["PATH"]
        self.git("init", "--quiet", "-b", "main")
        self.git("config", "user.name", "Original Author")
        self.git("config", "user.email", "original@example.invalid")
        self.git("config", "core.hooksPath", "/dev/null")
        for name in (".swiftformat", ".gitattributes", ".githooks/pre-commit",
                     ".githooks/check_swift_format.py", "Scripts/swift_headers.py",
                     "Scripts/format-swift.py", "Scripts/check-documentation.py"):
            target = self.repo / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(ROOT / name, target)
        self.git("add", ".")
        self.git("commit", "--quiet", "-m", "Tools baseline")
        self.git("config", "core.hooksPath", ".githooks")

    def git(self, *args):
        return subprocess.run(["git", *args], cwd=self.repo, env=self.env,
                              capture_output=True, check=True).stdout

    def format(self, *args, succeeds=True):
        result = subprocess.run([sys.executable, "Scripts/format-swift.py", *args],
                                cwd=self.repo, env=self.env, capture_output=True)
        self.assertEqual(result.returncode, 0 if succeeds else 1, result.stderr)
        return result

    def test_generates_headers_and_formats_untracked_hidden_sources(self):
        for name in ("new.swift", ".hidden.swift", "folder/雪 ' quote\nnew.swift"):
            path = self.repo / name
            path.parent.mkdir(exist_ok=True)
            path.write_bytes(b"/// A documented value.\nlet value=1\n")
        generated = self.repo / "API.generated.swift"
        generated.write_bytes(b"this is not Swift")
        dates = {datetime.now(timezone.utc).strftime("%d/%m/%Y")}
        self.format()
        dates.add(datetime.now(timezone.utc).strftime("%d/%m/%Y"))
        content = (self.repo / "new.swift").read_text()
        self.assertTrue(any(f"Created by Original Author on {day}." in content for day in dates))
        self.assertIn("/// A documented value.\nlet value = 1\n", content)
        self.assertIn("Created by Original Author", (self.repo / ".hidden.swift").read_text())
        self.assertEqual(generated.read_bytes(), b"this is not Swift")
        before = (self.repo / "new.swift").read_bytes()
        self.git("config", "user.name", "Different Author")
        self.format()
        self.assertEqual((self.repo / "new.swift").read_bytes(), before)
        self.format("--lint")

    def test_rename_keeps_author_and_date(self):
        path = self.repo / "renamed.swift"
        path.write_bytes(HEADER + b"let value=1\n")
        self.format("--lint", "renamed.swift", succeeds=False)
        self.format("renamed.swift")
        self.assertEqual(path.read_bytes(), HEADER.replace(b"old.swift", b"renamed.swift") + b"let value = 1\n")

    def test_missing_staged_header_cannot_be_hidden_by_formatted_working_copy(self):
        path = self.repo / "new.swift"
        path.write_bytes(b"let value = 1\n")
        self.format("--lint", succeeds=False)
        self.git("add", "new.swift")
        before = self.git("write-tree")
        self.format("new.swift")
        working = path.read_bytes()
        result = subprocess.run(["git", "commit", "-m", "Missing staged header"],
                                cwd=self.repo, env=self.env, capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(b"missing source header", result.stderr)
        self.assertEqual(self.git("write-tree"), before)
        self.assertEqual(path.read_bytes(), working)
        self.git("add", "new.swift")
        self.git("commit", "--quiet", "-m", "Header staged")

    def test_malformed_metadata_does_not_rewrite_any_selected_file(self):
        malformed = HEADER.replace(b"02/01/2020", b"31/02/2020")
        (self.repo / "old.swift").write_bytes(malformed)
        (self.repo / "new.swift").write_bytes(b"let value=1\n")
        self.format(succeeds=False)
        self.assertEqual((self.repo / "old.swift").read_bytes(), malformed)
        self.assertEqual((self.repo / "new.swift").read_bytes(), b"let value=1\n")

    def test_vendored_and_symlinked_sources_are_not_modified(self):
        (self.repo / "Vendor").mkdir()
        (self.repo / "Vendor/SDK.swift").write_bytes(b"not Swift")
        (self.repo / "alias.swift").symlink_to("Vendor/SDK.swift")
        self.format()
        self.assertEqual((self.repo / "Vendor/SDK.swift").read_bytes(), b"not Swift")
        self.assertTrue((self.repo / "alias.swift").is_symlink())

    def test_wrong_formatter_version_does_not_add_header(self):
        binary = self.directory / "bin"
        binary.mkdir()
        executable = binary / "swiftformat"
        executable.write_text("#!/bin/sh\necho 0.63.1\n")
        executable.chmod(0o755)
        self.env["PATH"] = str(binary) + os.pathsep + self.env["PATH"]
        (self.repo / "new.swift").write_bytes(b"let value=1\n")
        self.format(succeeds=False)
        self.assertEqual((self.repo / "new.swift").read_bytes(), b"let value=1\n")

    def test_missing_identity_blocks_generation_but_not_existing_headers(self):
        self.git("config", "user.name", "")
        source = HEADER + b"let value = 1\n"
        (self.repo / "old.swift").write_bytes(source)
        self.format("--lint")
        self.format()
        (self.repo / "new.swift").write_bytes(b"let value = 1\n")
        self.format(succeeds=False)
        self.assertEqual((self.repo / "new.swift").read_bytes(), b"let value = 1\n")
        self.assertEqual((self.repo / "old.swift").read_bytes(), source)

    def test_selection_uses_literal_paths_and_excludes_other_sources(self):
        folder = self.repo / "folder[1]"
        folder.mkdir()
        (folder / "new.swift").write_bytes(b"let value=1\n")
        (self.repo / "other.swift").write_bytes(b"let value=2\n")
        self.format("folder[1]")
        self.assertIn(b"Created by Original Author", (folder / "new.swift").read_bytes())
        self.assertEqual((self.repo / "other.swift").read_bytes(), b"let value=2\n")

    def test_squash_on_another_date_preserves_headers_and_passes_ci_checks(self):
        self.git("checkout", "--quiet", "-b", "feature")
        (self.repo / "old.swift").write_bytes(HEADER + b"let value=1\n")
        self.format("old.swift")
        content = (self.repo / "old.swift").read_bytes()
        self.git("add", "old.swift")
        self.git("commit", "--quiet", "--date=2020-01-02T12:00:00Z", "-m", "Original source")
        self.git("checkout", "--quiet", "main")
        self.git("merge", "--squash", "feature")
        self.git("config", "user.name", "Squash Author")
        self.git("commit", "--quiet", "--date=2021-03-04T12:00:00Z", "-m", "Squashed source")
        self.assertEqual(self.git("log", "-1", "--format=%as", "--", "old.swift").strip(), b"2021-03-04")
        self.format("--lint")
        subprocess.run([sys.executable, ".githooks/pre-commit", "--base", "HEAD^"],
                       cwd=self.repo, env=self.env, capture_output=True, check=True)
        self.assertEqual((self.repo / "old.swift").read_bytes(), content)
        self.assertIn(b"Original Author on 02/01/2020", content)


if __name__ == "__main__":
    unittest.main()
