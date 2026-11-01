#!/usr/bin/env python3
"""Keep DocC Swift examples synchronized with compiled Swift Testing sources."""

import argparse
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
EXAMPLES = {
    "packages/Shared/Sources/Shared/Shared.docc":
        ("packages/Shared/Tests/SharedTests/DocumentationExamples.swift", "import Shared"),
    "backend/Sources/Backend/Backend.docc":
        ("backend/Tests/BackendTests/DocumentationExamples.swift", "import KiteConnect"),
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--write", action="store_true")
    args = parser.parse_args()
    failed = False
    for catalog, (destination, imports) in EXAMPLES.items():
        bodies = []
        for page in sorted((ROOT / catalog).rglob("*.md")):
            for code in re.findall(r"^```swift\n(.*?)^```", page.read_text(), re.M | re.S):
                bodies.append(code.rstrip())
        if not bodies:
            sys.exit(f"No compiled examples found in {catalog}")
        source = "// Generated from DocC examples. Run Scripts/check-documentation-examples.py --write.\n"
        source += f"import Testing\n{imports}\n\n"
        for index, body in enumerate(bodies):
            source += f"@Test func documentationExample{index}() async throws {{\n"
            source += "\n".join("    " + line for line in body.splitlines()) + "\n}\n\n"
        source = source.rstrip() + "\n"
        target = ROOT / destination
        if args.write:
            target.write_text(source)
        elif not target.is_file() or target.read_text() != source:
            print(f"Stale compiled examples: {destination}. Run with --write.", file=sys.stderr)
            failed = True
    return int(failed)


if __name__ == "__main__":
    sys.exit(main())
