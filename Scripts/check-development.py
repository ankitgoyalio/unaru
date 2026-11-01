#!/usr/bin/env python3
"""Report required local tools before building or testing the package."""
import platform
from pathlib import Path
import re
import runpy
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]


def main():
    checks = [("Swift", ["swift", "--version"], r"Swift version 6\.4(?:[. ]|$)")]
    if platform.system() == "Darwin":
        checks = [
            ("Xcode", ["xcodebuild", "-version"], r"Xcode " + re.escape((ROOT / ".xcode-version").read_text().strip()) + r"(?:\n|$)"),
            ("Selected Swift", ["xcrun", "--find", "swift"], r"/Xcode[^/]*\.app/"),
            ("Swift", ["xcrun", "swift", "--version"], r"Swift version 6\.4(?:[. ]|$)"),
        ]
    version = runpy.run_path(str(ROOT / ".githooks/check_swift_format.py"))["SWIFTFORMAT_VERSION"]
    checks.append(("SwiftFormat", ["swiftformat", "--version"], re.escape(version) + r"$"))
    failed = False
    for label, command, expected in checks:
        try:
            result = subprocess.run(command, capture_output=True, text=True, timeout=15)
            output = (result.stdout + result.stderr).strip()
            passed = result.returncode == 0 and re.search(expected, output) is not None
        except (OSError, subprocess.TimeoutExpired) as error:
            output, passed = str(error), False
        print(f"{label}: {output}")
        if not passed:
            failed = True
            print(f"Required {label} unavailable or incompatible. See docs/development.md.", file=sys.stderr)
    return int(failed)


if __name__ == "__main__":
    sys.exit(main())
