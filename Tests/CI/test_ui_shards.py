"""Protect acceptance coverage when the UI suite is partitioned across runners."""

import importlib.util
import json
from pathlib import Path
import shutil
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("ui_runner", ROOT / "Scripts/run-ui-tests.py")
runner = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(runner)


class UIShardsTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        shutil.copytree(ROOT / "apps/unaru/unaruUITests", self.root / "apps/unaru/unaruUITests")
        (self.root / ".github").mkdir()
        shutil.copy2(ROOT / ".github/ui-test-shards.json", self.root / ".github/ui-test-shards.json")

    def test_repository_partition_is_complete(self):
        self.assertEqual(len(runner.load_shards(self.root)), 3)

    def test_new_test_requires_partition_update(self):
        (self.root / "apps/unaru/unaruUITests/New.swift").write_text(
            "extension unaruUITests { func testNewCase() {} }")
        with self.assertRaisesRegex(ValueError, "exactly once"):
            runner.load_shards(self.root)

    def test_duplicate_cannot_replace_an_omitted_case(self):
        path = self.root / ".github/ui-test-shards.json"
        shards = json.loads(path.read_text())
        shards[0]["tests"][0] = shards[1]["tests"][0]
        path.write_text(json.dumps(shards))
        with self.assertRaisesRegex(ValueError, "exactly once"):
            runner.load_shards(self.root)

    def test_new_class_requires_class_aware_partition(self):
        (self.root / "apps/unaru/unaruUITests/New.swift").write_text(
            "class AnotherSuite: XCTestCase { func testNewCase() {} }")
        with self.assertRaises(ValueError):
            runner.load_shards(self.root)

    def test_zero_or_skipped_results_are_not_success(self):
        summary = dict(result="Passed", totalTestCount=9, passedTests=9,
                       failedTests=0, skippedTests=0, expectedFailures=0)
        runner.verify_summary(summary, 9)
        for changes in (dict(totalTestCount=0, passedTests=0),
                        dict(skippedTests=1, passedTests=8), dict(result="Failed")):
            with self.subTest(changes=changes), self.assertRaises(ValueError):
                runner.verify_summary(summary | changes, 9)


if __name__ == "__main__":
    unittest.main()
