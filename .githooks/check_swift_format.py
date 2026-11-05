"""Lint staged Swift blobs with the staged repository configuration."""

import io
import os
from pathlib import Path
import subprocess
import sys
import tempfile

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "Scripts"))
from swift_headers import SWIFTFORMAT_VERSION, header_error


def check_swift_format(files):
    swift_files = [(path, oid) for path, oid in files if path.endswith(b".swift")]
    if not swift_files:
        return 0

    try:
        version = subprocess.run(
            ["swiftformat", "--version"], capture_output=True, check=True,
        ).stdout.decode().strip()
    except (OSError, subprocess.CalledProcessError):
        version = "unavailable"
    if version != SWIFTFORMAT_VERSION:
        print(
            f"Commit blocked: SwiftFormat {SWIFTFORMAT_VERSION} is required "
            f"(found {version}). See docs/development.md for installation.",
            file=sys.stderr,
        )
        return 1

    config = subprocess.run(
        ["git", "show", ":.swiftformat"], capture_output=True,
    )
    if config.returncode:
        print("Commit blocked: stage the root .swiftformat configuration first.", file=sys.stderr)
        return 1

    # Formatter subprocesses must not inherit the original hook's Git locators.
    formatter_env = os.environ.copy()
    for name in ("GIT_DIR", "GIT_WORK_TREE", "GIT_COMMON_DIR"):
        formatter_env.pop(name, None)
    with tempfile.TemporaryDirectory(prefix="unaru-format-") as directory:
        config_path = os.path.join(directory, ".swiftformat")
        with open(config_path, "wb") as output:
            output.write(config.stdout)
        # Materialize only the staged blobs, preserving arbitrary filenames.
        objects = subprocess.run(
            ["git", "cat-file", "--batch"],
            input=b"".join(oid + b"\n" for _, oid in swift_files),
            capture_output=True, check=True,
        )
        blobs = io.BytesIO(objects.stdout)
        failed = False
        for path, _ in swift_files:
            _, kind, size = blobs.readline().rstrip(b"\n").split()
            if kind != b"blob":
                raise ValueError("Expected a staged blob")
            content = blobs.read(int(size))
            if len(content) != int(size) or blobs.read(1) != b"\n":
                raise ValueError("Incomplete staged blob")
            error = header_error(path, content)
            if error:
                failed = True
                print(f"{os.fsdecode(path)!r}: {error}", file=sys.stderr)
            target = Path(directory) / os.fsdecode(path)
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(content)

        # Explicit paths include hidden Swift files, unlike directory traversal.
        # Bound each argv well below platform limits; newline-delimited filelists
        # cannot represent every valid Git filename.
        batches = [[]]
        batch_bytes = 0
        for path, _ in swift_files:
            target = os.path.join(directory, os.fsdecode(path))
            size = len(os.fsencode(target)) + 1
            if batch_bytes + size > 48_000 and batches[-1]:
                batches.append([])
                batch_bytes = 0
            batches[-1].append(target)
            batch_bytes += size
        for batch in batches:
            result = subprocess.run(
                ["swiftformat", *batch, "--lint", "--config", config_path,
                 "--cache", "ignore"],
                capture_output=True, env=formatter_env,
            )
            if result.returncode:
                failed = True
                print("SwiftFormat failed for staged Swift files:", file=sys.stderr)
                # Report repository-relative paths instead of disposable locations.
                sys.stderr.buffer.write(
                    result.stderr.replace(os.fsencode(directory) + b"/", b"")
                )
    if failed:
        print(
            "Commit blocked: run python3 Scripts/format-swift.py <file>, review "
            "the changes, then stage the intended hunks and retry. "
            "The hook leaves the index and working tree unchanged.",
            file=sys.stderr,
        )
    return int(failed)
