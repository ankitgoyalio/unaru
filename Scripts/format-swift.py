#!/usr/bin/env python3
"""Format authored Swift files and add missing headers, or validate with --lint."""

import argparse
import os
from pathlib import Path
import subprocess
import sys

from swift_headers import MISSING_HEADER, SWIFTFORMAT_VERSION, format_header, header_error

ROOT = Path(__file__).resolve().parents[1]


def authored_files(paths):
    requested = []
    for path in paths:
        supplied = Path(path).absolute()
        # Normalize macOS /var symlinks without following a source-file symlink.
        absolute = supplied.parent.resolve() / supplied.name
        if not absolute.exists():
            raise ValueError(f"path does not exist: {path!r}")
        requested.append(str(absolute.relative_to(ROOT)))
    records = subprocess.run(
        ["git", "--literal-pathspecs", "ls-files", "--cached", "--others",
         "--exclude-standard", "-z", "--", *requested],
        cwd=ROOT, capture_output=True, check=True,
    ).stdout.split(b"\0")
    files = sorted({path for path in records if path.endswith(b".swift")
                    and (ROOT / os.fsdecode(path)).is_file()
                    and not (ROOT / os.fsdecode(path)).is_symlink()})
    if not files:
        return []
    attributes = subprocess.run(
        ["git", "check-attr", "-z", "--stdin", "linguist-generated", "linguist-vendored"],
        input=b"".join(path + b"\0" for path in files), cwd=ROOT,
        capture_output=True, check=True,
    ).stdout.split(b"\0")
    exempt = {attributes[index] for index in range(0, len(attributes) - 1, 3)
              if attributes[index + 2] in (b"set", b"true")}
    return [ROOT / os.fsdecode(path) for path in files if path not in exempt]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lint", action="store_true", help="Check without changing files")
    parser.add_argument("paths", nargs="*", help="Files or directories; default: the repository")
    args = parser.parse_args()
    files = authored_files(args.paths)
    if not files:
        print("No authored Swift files selected.")
        return 0
    try:
        version = subprocess.run(["swiftformat", "--version"], capture_output=True, check=True).stdout.decode().strip()
    except (OSError, subprocess.CalledProcessError):
        version = "unavailable"
    if version != SWIFTFORMAT_VERSION:
        raise ValueError(f"SwiftFormat {SWIFTFORMAT_VERSION} is required (found {version})")
    author = None
    updates = []
    failed = False
    for path in files:
        content = path.read_bytes()
        try:
            if args.lint:
                error = header_error(path, content)
                if error:
                    raise ValueError(error)
            else:
                if author is None and header_error(path, content) == MISSING_HEADER:
                    author = subprocess.run(
                        ["git", "config", "user.name"], cwd=ROOT, capture_output=True,
                    ).stdout.decode().strip()
                formatted = format_header(path, content, author=author)
                if formatted != content:
                    updates.append((path, formatted))
        except (ValueError, UnicodeError) as error:
            print(f"{str(path.relative_to(ROOT))!r}: {error}", file=sys.stderr)
            failed = True
    if failed:
        print("Run python3 Scripts/format-swift.py <file>, review, and stage the intended hunks. "
              "Correct malformed author/date fields manually.", file=sys.stderr)
        return 1
    for path, content in updates:
        path.write_bytes(content)
    # Explicit files include hidden sources; bounded argv supports large repos.
    batches = [[]]
    size = 0
    for path in files:
        if batches[-1] and size + len(os.fsencode(path)) + 1 > 48_000:
            batches.append([])
            size = 0
        batches[-1].append(str(path))
        size += len(os.fsencode(path)) + 1
    for batch in batches:
        result = subprocess.run(
            ["swiftformat", *batch, *(["--lint"] if args.lint else []),
             "--config", str(ROOT / ".swiftformat"), "--cache", "ignore"], cwd=ROOT,
        )
        failed |= result.returncode != 0
    return int(failed)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print(f"Swift formatting failed: {error}", file=sys.stderr)
        sys.exit(1)
