"""Protect acceptance coverage when the UI suite is partitioned across runners."""

import importlib.util
import json
from pathlib import Path
import shutil
import sys
import tempfile
import unittest
from unittest.mock import patch

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

    def test_shared_products_run_without_recompiling(self):
        products = self.root / "Products"
        products.mkdir()
        test_run = products / "unaru.xctestrun"
        test_run.touch()
        summary = dict(result="Passed", totalTestCount=9, passedTests=9,
                       failedTests=0, skippedTests=0, expectedFailures=0)
        with patch.object(sys, "argv", ["run-ui-tests.py", "1", "--products", str(products)]), \
                patch.object(runner, "ROOT", self.root), \
                patch.object(runner.subprocess, "run") as execute, \
                patch.object(runner.subprocess, "check_output", return_value=json.dumps(summary)):
            runner.main()
        command = execute.call_args_list[0].args[0]
        self.assertEqual(command[:4], ["xcodebuild", "test-without-building", "-xctestrun", str(test_run)])
        self.assertEqual(sum(arg.startswith("-only-testing:") for arg in command), 9)

    def test_missing_shared_test_specification_fails_instead_of_rebuilding(self):
        products = self.root / "Products"
        products.mkdir()
        with patch.object(sys, "argv", ["run-ui-tests.py", "1", "--products", str(products)]), \
                patch.object(runner, "ROOT", self.root), self.assertRaisesRegex(ValueError, "one test run"):
            runner.main()


if __name__ == "__main__":
    unittest.main()
