"""Keep generated declarations out of coverage without hiding undocumented APIs."""

import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("docs_build", ROOT / "Scripts/build-documentation.py")
builder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(builder)


def symbol(identifier, kind, location=None, documented=False):
    result = {
        "identifier": {"precise": identifier}, "names": {"title": identifier},
        "kind": {"identifier": kind},
    }
    if location is not None:
        result["location"] = {"uri": "file:///source.swift", "position": {"line": location}}
    if documented:
        result["docComment"] = {"lines": [{"text": "An authored declaration."}]}
    return result


class CoverageTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.graphs = Path(self.temp.name)
        self.graph = self.graphs / "Example.symbols.json"

    def write(self, symbols, relationships=None):
        self.graph.write_text(json.dumps({"symbols": symbols, "relationships": relationships or []}))

    def test_filters_macros_and_implicit_initializers_but_keeps_documented_types(self):
        self.write([
            symbol("View", "swift.struct", 1, True),
            symbol("implicit-init", "swift.init", 1),
            symbol("preview-macro", "swift.struct"),
        ], [{"source": "preview-macro", "target": "View"}])
        self.assertEqual(builder.audit_coverage("Example", self.graphs), {"View": "View"})
        data = json.loads(self.graph.read_text())
        self.assertEqual(len(data["symbols"]), 1)
        self.assertEqual(data["relationships"], [])

    def test_authored_undocumented_initializer_fails(self):
        self.write([symbol("View", "swift.struct", 1, True), symbol("init", "swift.init", 2)])
        with self.assertRaisesRegex(SystemExit, "Undocumented Example symbols: init"):
            builder.audit_coverage("Example", self.graphs)

    def test_authored_undocumented_function_fails(self):
        self.write([symbol("function", "swift.func", 1)])
        with self.assertRaisesRegex(SystemExit, "Undocumented"):
            builder.audit_coverage("Example", self.graphs)

    def test_empty_graph_fails(self):
        self.write([])
        with self.assertRaisesRegex(SystemExit, "No authored"):
            builder.audit_coverage("Example", self.graphs)


if __name__ == "__main__":
    unittest.main()
