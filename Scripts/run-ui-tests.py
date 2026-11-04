#!/usr/bin/env python3
"""Run one complete, disjoint partition of the macOS UI suite."""

import argparse
from collections import Counter
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def load_shards(root=ROOT):
    """Reject stale partitions rather than silently omit a new acceptance test."""
    discovered = []
    for source in (root / "apps/unaru/unaruUITests").glob("*.swift"):
        text = source.read_text()
        methods = re.findall(r"\bfunc\s+(test\w+)\s*\(", text)
        if methods and not re.search(r"\b(?:class|extension)\s+unaruUITests\b", text):
            raise ValueError(f"Unrecognized UI test class in {source.name}")
        if re.search(r"\bclass\s+(?!unaruUITests\b)\w+\s*:\s*XCTestCase\b", text):
            raise ValueError(f"Add class-aware sharding for {source.name}")
        discovered.extend(methods)
    shards = json.loads((root / ".github/ui-test-shards.json").read_text())
    assigned = [name for shard in shards for name in shard["tests"]]
    if (not discovered or Counter(assigned) != Counter(discovered)
            or any(count != 1 for count in Counter(assigned).values())
            or [shard["shard"] for shard in shards] != [1, 2, 3]
            or any(not shard["tests"] for shard in shards)):
        raise ValueError("UI shards must contain every discovered test exactly once across three nonempty shards")
    return shards


def verify_summary(summary, expected):
    """Require actual successful execution, including no skipped UI cases."""
    if (summary["result"] != "Passed" or summary["totalTestCount"] != expected
            or summary["passedTests"] != expected
            or any(summary[key] for key in ("failedTests", "skippedTests", "expectedFailures"))):
        raise ValueError(f"Expected {expected} passing UI tests without skips: {summary}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("shard", type=int, choices=(1, 2, 3))
    args = parser.parse_args()
    shards = load_shards()
    selected = shards[args.shard - 1]["tests"]
    output = ROOT / ".test-results"
    output.mkdir(exist_ok=True)
    (output / "ui-shards.json").write_text(json.dumps(shards, indent=2) + "\n")
    result = output / "macos-ui.xcresult"
    subprocess.run([
        "xcodebuild", "test", "-project", "apps/unaru/unaru.xcodeproj", "-scheme", "unaru",
        "-destination", "platform=macOS", "-derivedDataPath", ".build/macos",
        "-parallel-testing-enabled", "NO", "CODE_SIGN_IDENTITY=-",
        "-resultBundlePath", str(result), "-test-timeouts-enabled", "YES",
        "-default-test-execution-time-allowance", "120",
        "-maximum-test-execution-time-allowance", "180", "-showBuildTimingSummary",
        *(f"-only-testing:unaruUITests/unaruUITests/{name}" for name in selected),
    ], cwd=ROOT, check=True)
    summary = json.loads(subprocess.check_output([
        "xcrun", "xcresulttool", "get", "test-results", "summary", "--path", str(result),
    ], text=True))
    (output / "ui-summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    verify_summary(summary, len(selected))
    subprocess.run([
        "xcrun", "xcresulttool", "export", "attachments", "--path", str(result),
        "--output-path", str(output / "screenshots"), "--filter", "*.png",
    ], check=True)


if __name__ == "__main__":
    main()
