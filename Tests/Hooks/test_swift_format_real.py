"""Optional integration coverage with the pinned SwiftFormat executable."""

import importlib.util
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]


class RealSwiftFormatTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        binary = os.environ.get("SWIFTFORMAT_TEST_BINARY") or shutil.which("swiftformat")
        if not binary:
            raise unittest.SkipTest("SwiftFormat is unavailable")
        version = subprocess.run([binary, "--version"], capture_output=True, check=True)
        if version.stdout.strip() != b"0.64.5":
            raise unittest.SkipTest("SwiftFormat 0.64.5 is required")
        cls.binary = Path(binary).resolve()
        spec = importlib.util.spec_from_file_location(
            "format_helper", ROOT / ".githooks/check_swift_format.py",
        )
        cls.helper = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(cls.helper)

    def test_snapshot_keeps_history_and_new_file_identity_in_a_worktree(self):
        with tempfile.TemporaryDirectory() as directory:
            repo = Path(directory) / "repo"
            worktree = Path(directory) / "worktree"
            repo.mkdir()
            env = {key: value for key, value in os.environ.items()
                   if not key.startswith("GIT_")}
            env["PATH"] = str(self.binary.parent) + os.pathsep + env["PATH"]

            def git(*args, cwd=repo):
                return subprocess.run(["git", *args], cwd=cwd, env=env,
                                      capture_output=True, check=True).stdout

            git("init", "--quiet")
            git("config", "user.name", "Original Author")
            git("config", "user.email", "original@example.invalid")
            git("config", "core.hooksPath", "/dev/null")
            shutil.copy2(ROOT / ".swiftformat", repo / ".swiftformat")
            old = repo / "old.swift"
            old.write_text("let value = 1\n")
            git("add", ".")
            with patch.dict(env, {"GIT_AUTHOR_DATE": "2020-01-02T12:00:00Z",
                                  "GIT_COMMITTER_DATE": "2020-01-02T12:00:00Z"}):
                git("commit", "--quiet", "-m", "Historical source")
            git("worktree", "add", "--quiet", "-b", "snapshot-test", str(worktree))
            git("config", "user.name", "Current Author")
            names = ["old.swift", ".hidden.swift", ".folder/雪 ' quote\nnew.swift"]
            for name in names:
                path = worktree / name
                path.parent.mkdir(exist_ok=True)
                if name != "old.swift":
                    path.write_text("let value = 1\n")
                subprocess.run([str(self.binary), str(path), "--config",
                                str(worktree / ".swiftformat"), "--cache", "ignore"],
                               cwd=worktree, env=env, capture_output=True, check=True)
            self.assertIn("Created by Original Author on 02/01/2020.",
                          (worktree / "old.swift").read_text())
            self.assertIn("Created by Current Author on",
                          (worktree / ".hidden.swift").read_text())
            git("add", ".", cwd=worktree)
            before = git("write-tree", cwd=worktree)
            blobs = []
            for name in names:
                oid = git("rev-parse", ":" + name, cwd=worktree).strip()
                blobs.append((os.fsencode(name), oid))
                (worktree / name).write_text("let unformatted=0\n")
            env["GIT_DIR"] = git("rev-parse", "--absolute-git-dir", cwd=worktree).decode().strip()
            env["GIT_WORK_TREE"] = str(worktree)
            env["GIT_COMMON_DIR"] = str(repo / ".git")
            previous = Path.cwd()
            try:
                os.chdir(worktree)
                with patch.dict(os.environ, env, clear=True):
                    self.assertEqual(self.helper.check_swift_format(blobs), 0)
            finally:
                os.chdir(previous)
            self.assertEqual(git("write-tree", cwd=worktree), before)
            for name in names:
                self.assertEqual((worktree / name).read_text(), "let unformatted=0\n")
