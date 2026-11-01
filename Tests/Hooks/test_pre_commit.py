"""Exercise the hook against real Git indexes in disposable repositories."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class StagedCommitChecksTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.repo = Path(self.temp.name)
        self.env = os.environ.copy()
        for name in tuple(self.env):
            if name.startswith("GIT_"):
                del self.env[name]
        self.git("init", "--quiet")
        self.git("config", "user.name", "Hook Test")
        self.git("config", "user.email", "hook@example.invalid")
        (self.repo / "Scripts").mkdir()
        shutil.copy2(ROOT / "Scripts/check-documentation.py", self.repo / "Scripts/check-documentation.py")
        hooks = self.repo / ".githooks"
        hooks.mkdir()
        shutil.copy2(ROOT / ".githooks/pre-commit", hooks / "pre-commit")
        shutil.copy2(ROOT / ".githooks/check_swift_format.py", hooks / "check_swift_format.py")
        shutil.copy2(ROOT / ".gitattributes", self.repo / ".gitattributes")
        shutil.copy2(ROOT / ".swiftformat", self.repo / ".swiftformat")
        # Keep size-check tests independent of a developer's installed formatter.
        self.bin = self.repo / "bin"
        self.bin.mkdir()
        formatter = self.bin / "swiftformat"
        formatter.write_text(
            "#!/usr/bin/env python3\n"
            "import json, os, pathlib, sys\n"
            "if '--version' in sys.argv:\n"
            "    print('0.64.5')\n"
            "else:\n"
            "    root = pathlib.Path(sys.argv[sys.argv.index('--config') + 1]).parent\n"
            "    paths = [pathlib.Path(p) for p in sys.argv[1:sys.argv.index('--lint')]]\n"
            "    files = {str(p.relative_to(root)): p.read_bytes().decode() for p in paths}\n"
            "    data = b''.join(p.read_bytes() for p in paths)\n"
            "    pathlib.Path('formatter-files').write_text(json.dumps(files))\n"
            "    with pathlib.Path('formatter-calls').open('a') as log: log.write('lint\\n')\n"
            "    pathlib.Path('formatter-input').write_bytes(data)\n"
            "    pathlib.Path('formatter-environment').write_text(json.dumps({k: os.environ.get(k) for k in ('GIT_DIR', 'GIT_WORK_TREE', 'GIT_COMMON_DIR')}))\n"
            "    config = pathlib.Path(sys.argv[sys.argv.index('--config') + 1]).read_bytes()\n"
            "    pathlib.Path('formatter-config').write_bytes(config)\n"
            "    pathlib.Path('formatter-args').write_text(json.dumps(sys.argv))\n"
            "    sys.exit(1 if b'UNFORMATTED' in data else 0)\n"
        )
        formatter.chmod(0o755)
        self.env["PATH"] = str(self.bin) + os.pathsep + self.env["PATH"]
        self.git("config", "core.hooksPath", ".githooks")
        self.git("add", ".gitattributes", ".swiftformat")

    def git(self, *args):
        return subprocess.run(
            ["git", *args], cwd=self.repo, env=self.env,
            capture_output=True, check=True,
        )

    def stage(self, name, content):
        path = self.repo / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(content)
        self.git("add", "--", name)

    def check_hook(self, succeeds):
        result = subprocess.run(
            [str(self.repo / ".githooks/pre-commit")],
            cwd=self.repo, env=self.env, capture_output=True,
        )
        self.assertEqual(result.returncode, 0 if succeeds else 1, result.stderr)
        return result.stderr.decode()

    def test_documentation_artifacts_are_blocked_even_when_forced_or_exempt(self):
        for name in ("Documentation/Evidence/run.txt", "Documentation/Ticket-9.md",
                     "Documentation/Review.md", "Documentation/Partial-0x.md",
                     "Documentation/session.json", "Documentation/run.log",
                     "Documentation/Run-2026-10-28.md"):
            with self.subTest(name=name):
                self.stage(name, b"execution output")
                self.assertIn("execution/history artifact", self.check_hook(False))
                self.git("rm", "--cached", "--", name)
        self.stage(".gitattributes", b"Documentation/** linguist-generated=true\n")
        self.stage("Documentation/result.json", b"{}")
        self.check_hook(False)

    def test_documentation_links_read_staged_content_and_deletions(self):
        self.stage("Documentation/README.md", b"[DocC](DocC.md)\n")
        self.stage("Documentation/DocC.md", b"Durable behavior")
        self.check_hook(True)
        (self.repo / "Documentation/README.md").write_text("[broken](missing.md)")
        self.check_hook(True)
        self.git("rm", "--cached", "Documentation/DocC.md")
        self.assertIn("broken local link", self.check_hook(False))

    def test_unregistered_project_docs_are_blocked_even_when_exempt(self):
        self.stage(".gitattributes", b"*.md linguist-generated=true\n")
        for name in ("docs/sdk-design.md", "docs/sdk-ticket-plan.md",
                     "docs/Run-2026-10-29.md", "docs/Evidence/run.txt",
                     "docs/new-guide.md", "Plan.md", "Documentation/Usage.md",
                     "Documentation/Contracts.md"):
            with self.subTest(name=name):
                self.stage(name, b"redundant documentation")
                self.assertIn("unregistered", self.check_hook(False))
                self.git("rm", "--cached", "--", name)

    def test_project_docs_and_numbered_adrs_are_allowed_and_links_checked(self):
        self.stage("AGENTS.md", b"[Development](docs/development.md)\n")
        self.stage("docs/development.md", b"[Decision](adr/0014-durable-docs.md)\n")
        self.stage("docs/adr/0014-durable-docs.md", b"A durable design decision")
        self.check_hook(True)
        (self.repo / "docs/development.md").write_text("[broken](missing.md)")
        self.check_hook(True)
        working = subprocess.run(
            ["python3", "Scripts/check-documentation.py"],
            cwd=self.repo, env=self.env, capture_output=True,
        )
        self.assertNotEqual(working.returncode, 0)
        self.assertIn(b"broken local link", working.stderr)
        self.git("add", "docs/development.md")
        self.assertIn("broken local link", self.check_hook(False))
        self.stage("docs/development.md", b"[Decision](adr/0014-durable-docs.md)\n")
        self.git("rm", "--cached", "docs/adr/0014-durable-docs.md")
        self.assertIn("broken local link", self.check_hook(False))
        self.stage("docs/adr/0014-durable-docs.md", b"A durable design decision")
        self.stage("AGENTS.md", b"[broken](missing.md)\n")
        self.assertIn("broken local link", self.check_hook(False))

    def test_ci_base_checks_committed_changes_even_with_clean_index(self):
        self.git("commit", "--quiet", "-m", "Baseline")
        base = self.git("rev-parse", "HEAD").stdout.decode().strip()
        self.stage("source.swift", b"UNFORMATTED committed source")
        self.git("-c", "core.hooksPath=/dev/null", "commit", "--quiet", "-m", "Bypass local hook")
        result = subprocess.run(["python3", ".githooks/pre-commit", "--base", base],
                                cwd=self.repo, env=self.env, capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(b"SwiftFormat failed", result.stderr)
        self.git("rm", "source.swift")
        self.git("commit", "--quiet", "-m", "Remove source")
        result = subprocess.run(["python3", ".githooks/pre-commit", "--base", base],
                                cwd=self.repo, env=self.env, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_rule_change_checks_unchanged_swift(self):
        self.stage("source.swift", b"UNFORMATTED baseline")
        self.git("-c", "core.hooksPath=/dev/null", "commit", "--quiet", "-m", "Baseline")
        self.stage(".swiftformat", (self.repo / ".swiftformat").read_bytes() + b"\n")
        self.assertIn("SwiftFormat failed", self.check_hook(False))

    def test_rule_change_does_not_expand_size_guard_to_unchanged_files(self):
        self.stage("source.swift", b"x" * 20_001)
        self.git("-c", "core.hooksPath=/dev/null", "commit", "--quiet", "-m", "Baseline")
        self.stage(".swiftformat", (self.repo / ".swiftformat").read_bytes() + b"\n")
        self.check_hook(True)

    def test_exact_limit_passes_but_one_more_byte_blocks(self):
        self.stage("source.swift", b"x" * 20_000)
        self.check_hook(True)
        self.stage("source.swift", b"x" * 20_001)
        error = self.check_hook(False)
        self.assertIn("5,000.25 tokens", error)
        self.assertIn("Group code by responsibility", error)
        self.assertIn("Stage the revised original", error)

    def test_counts_bytes_instead_of_unicode_characters(self):
        self.stage("README.md", ("é" * 10_001).encode())
        self.assertIn("20,002 bytes", self.check_hook(False))

    def test_large_unstaged_content_does_not_block_small_staged_blob(self):
        self.stage("source.swift", b"small")
        (self.repo / "source.swift").write_bytes(b"x" * 25_000)
        (self.repo / "untracked.md").write_bytes(b"x" * 25_000)
        self.check_hook(True)

    def test_small_working_copy_cannot_hide_large_staged_blob(self):
        self.stage("source.swift", b"x" * 25_000)
        (self.repo / "source.swift").write_bytes(b"small")
        self.check_hook(False)

    def test_lockfiles_codegen_and_vendor_are_exempt(self):
        for name in (
            "Package.resolved", "nested/Package.resolved", "skills-lock.json",
            "yarn.lock",
            "Sources/Generated/API.swift", "generated/API.swift",
            "API.generated.swift", "API.g.swift", "Vendor/SDK.swift",
        ):
            self.stage(name, b"x" * 25_000)
        self.check_hook(True)

    def test_exemptions_use_staged_attributes(self):
        attributes = self.repo / ".gitattributes"
        self.stage("API.swift", b"x" * 25_000)
        attributes.write_text("API.swift linguist-generated=true\n")
        self.check_hook(False)
        self.git("add", ".gitattributes")
        attributes.write_text("")
        self.check_hook(True)

    def test_multiple_violations_and_unusual_filenames(self):
        names = ["space name.swift", "line\nbreak.swift", "déjà.swift"]
        for name in names:
            self.stage(name, b"x" * 20_001)
        error = self.check_hook(False)
        for name in names:
            self.assertIn(repr(name), error)

    def test_rename_to_authored_path_checks_the_blob(self):
        self.stage("API.generated.swift", b"x" * 25_000)
        self.git("commit", "--quiet", "-m", "Generated baseline")
        self.git("mv", "API.generated.swift", "API.swift")
        self.check_hook(False)

    def test_unchanged_large_files_and_deletions_are_ignored(self):
        self.stage("README.md", b"x" * 25_000)
        self.git("-c", "core.hooksPath=/dev/null", "commit", "--quiet", "-m", "Baseline")
        self.stage("GLOSSARY.md", b"small")
        self.check_hook(True)
        self.git("rm", "README.md")
        self.check_hook(True)

    def test_symlinks_are_ignored(self):
        (self.repo / "link").symlink_to("missing-target")
        self.git("add", "link")
        self.check_hook(True)

    def test_actual_commit_is_blocked_without_changing_the_index(self):
        self.stage("source.swift", b"x" * 20_001)
        before = self.git("write-tree").stdout
        result = subprocess.run(
            ["git", "commit", "-m", "Should fail"],
            cwd=self.repo, env=self.env, capture_output=True,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(b"Commit blocked", result.stderr)
        self.assertEqual(self.git("write-tree").stdout, before)

    def test_formatting_reads_staged_content_and_config(self):
        name = "space ' quote\nfile.swift"
        self.stage(name, b"let value = 1\n")
        (self.repo / name).write_bytes(b"UNFORMATTED working copy")
        config = (self.repo / ".swiftformat").read_bytes()
        (self.repo / ".swiftformat").write_text("unstaged invalid config")
        before = self.git("write-tree").stdout
        self.check_hook(True)
        self.assertEqual((self.repo / "formatter-input").read_bytes(), b"let value = 1\n")
        self.assertEqual((self.repo / "formatter-config").read_bytes(), config)
        args = json.loads((self.repo / "formatter-args").read_text())
        self.assertEqual(json.loads((self.repo / "formatter-files").read_text()), {name: "let value = 1\n"})
        self.assertIn("--lint", args)
        self.assertEqual(self.git("write-tree").stdout, before)
        self.assertEqual((self.repo / name).read_bytes(), b"UNFORMATTED working copy")

    def test_formatter_batches_staged_blobs_in_one_invocation(self):
        names = ["one.swift", "folder/雪.swift", ".hidden.swift", ".folder/two.swift",
                 "space ' quote\nfile.swift"]
        for name in names:
            self.stage(name, b"let value = 1\n")
            (self.repo / name).write_bytes(b"UNFORMATTED working copy")
        before = self.git("write-tree").stdout
        self.check_hook(True)
        self.assertEqual((self.repo / "formatter-calls").read_text(), "lint\n")
        self.assertEqual(json.loads((self.repo / "formatter-files").read_text()),
                         {name: "let value = 1\n" for name in names})
        self.assertEqual(self.git("write-tree").stdout, before)
        # A failure anywhere in the batch still blocks the hook.
        self.stage(".hidden.swift", b"UNFORMATTED staged blob")
        self.assertIn("SwiftFormat failed", self.check_hook(False))

    def test_unformatted_staged_swift_blocks_actual_commit(self):
        self.stage("source.swift", b"UNFORMATTED staged blob")
        (self.repo / "source.swift").write_bytes(b"formatted working copy")
        before = self.git("write-tree").stdout
        result = subprocess.run(
            ["git", "commit", "-m", "Should fail formatting"],
            cwd=self.repo, env=self.env, capture_output=True,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(b"SwiftFormat failed for staged", result.stderr)
        self.assertEqual(self.git("write-tree").stdout, before)
        self.assertEqual((self.repo / "source.swift").read_bytes(), b"formatted working copy")

    def test_missing_formatter_only_blocks_authored_swift(self):
        (self.bin / "swiftformat").unlink()
        # Simulate an unavailable tool without falling through to a system install.
        (self.bin / "swiftformat").write_text("#!/bin/sh\nexit 127\n")
        (self.bin / "swiftformat").chmod(0o755)
        self.stage("README.md", b"notes")
        self.stage("API.generated.swift", b"UNFORMATTED")
        self.check_hook(True)
        self.stage("source.swift", b"let value = 1\n")
        self.assertIn("SwiftFormat 0.64.5 is required", self.check_hook(False))

    def test_formatter_discovers_header_metadata_without_hook_git_locators(self):
        self.env["GIT_DIR"] = str(self.repo / ".git")
        self.env["GIT_WORK_TREE"] = str(self.repo)
        self.env["GIT_COMMON_DIR"] = str(self.repo / ".git")
        self.stage("source.swift", b"let value = 1\n")
        self.check_hook(True)
        observed = json.loads((self.repo / "formatter-environment").read_text())
        self.assertEqual(observed, {"GIT_DIR": None, "GIT_WORK_TREE": None, "GIT_COMMON_DIR": None})
        # The parent Git calls still need their original repository environment.
        self.assertEqual(self.env["GIT_DIR"], str(self.repo / ".git"))

    def test_wrong_formatter_version_blocks(self):
        formatter = self.bin / "swiftformat"
        formatter.write_text("#!/bin/sh\necho 0.63.1\n")
        self.stage("source.swift", b"let value = 1\n")
        self.assertIn("found 0.63.1", self.check_hook(False))

    def test_missing_staged_configuration_blocks(self):
        self.git("rm", "--cached", ".swiftformat")
        self.stage("source.swift", b"let value = 1\n")
        self.assertIn("stage the root .swiftformat", self.check_hook(False))

    def test_deleted_swift_does_not_require_formatter(self):
        self.stage("source.swift", b"let value = 1\n")
        self.git("commit", "--quiet", "-m", "Baseline")
        self.git("rm", "source.swift")
        (self.bin / "swiftformat").write_text("#!/bin/sh\nexit 1\n")
        self.check_hook(True)


if __name__ == "__main__":
    unittest.main()
