"""Reject broken static DocC assets, hosting prefixes, and topic links."""

import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("site_check", ROOT / "Scripts/check-documentation-site.py")
checker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checker)


class StaticSiteTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.site = Path(self.temp.name)
        (self.site / "index.html").write_text("Unaru documentation")
        (self.site / ".nojekyll").touch()
        for module in ("shared", "backend", "unaru"):
            root = self.site / module
            landing = root / "documentation" / module
            landing.mkdir(parents=True)
            (landing / "index.html").write_text(
                f'<script src="/unaru/{module}/js/app.js"></script>'
            )
            (root / "js").mkdir()
            (root / "js/app.js").write_text("// renderer")
            data = root / "data/documentation"
            data.mkdir(parents=True)
            (data / f"{module}.json").write_text(json.dumps({"references": {}}))

    def test_complete_project_site_passes(self):
        self.assertEqual(checker.check_site(self.site, "/unaru"), 3)

    def test_missing_asset_fails(self):
        (self.site / "shared/js/app.js").unlink()
        with self.assertRaisesRegex(ValueError, "Missing asset"):
            checker.check_site(self.site, "/unaru")

    def test_wrong_hosting_prefix_fails(self):
        with self.assertRaisesRegex(ValueError, "Wrong hosting prefix"):
            checker.check_site(self.site, "/other-repo")

    def test_broken_topic_reference_fails(self):
        (self.site / "backend/data/documentation/backend.json").write_text(json.dumps({
            "references": {"missing": {"type": "topic", "url": "/documentation/backend/missing"}},
        }))
        with self.assertRaisesRegex(ValueError, "Broken DocC topic"):
            checker.check_site(self.site, "/unaru")

    def test_missing_module_route_fails(self):
        (self.site / "unaru/documentation/unaru/index.html").unlink()
        with self.assertRaisesRegex(ValueError, "Missing static landing"):
            checker.check_site(self.site, "/unaru")


if __name__ == "__main__":
    unittest.main()
