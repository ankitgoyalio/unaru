"""Require every module when CI assembles documentation on Linux."""

import importlib.util
import io
import json
from pathlib import Path
import sys
import tarfile
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("docc_builder", ROOT / "Scripts/build-documentation.py")
builder = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(builder)


class AssemblyTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.output = self.root / "output"
        self.inputs = self.root / "inputs"
        self.inputs.mkdir()

    def module(self, name):
        source = self.root / name
        source.mkdir()
        archive = source / f"{name}.doccarchive"
        route = archive / "documentation" / name.lower()
        route.mkdir(parents=True)
        (route / "index.html").write_text(f'<script src="/unaru/{name.lower()}/js/app.js"></script>')
        (archive / "js").mkdir()
        (archive / "js/app.js").write_text("// DocC runtime")
        data = archive / "data/documentation"
        data.mkdir(parents=True)
        (data / f"{name.lower()}.json").write_text(json.dumps({"references": {}}))
        (source / f"{name}-inventory.json").write_text(json.dumps({name: "documented API"}))
        (source / f"{name}-diagnostics.json").write_text("[]")
        destination = self.inputs / name
        destination.mkdir()
        with tarfile.open(destination / "docc-validation.tar", "w") as bundle:
            for path in source.iterdir():
                bundle.add(path, arcname=path.name)

    def assemble(self):
        with patch.object(builder, "OUTPUT", self.output), patch.object(
            sys, "argv", ["build-documentation.py", "--assemble-only", "--inputs", str(self.inputs)]
        ):
            builder.main()

    def test_complete_archives_build_a_verified_site_without_xcode(self):
        for name in builder.MODULES:
            self.module(name)
        self.assemble()
        self.assertEqual(set(json.loads((self.output / "api-inventory.json").read_text())),
                         set(builder.MODULES))
        self.assertTrue((self.output / "docc-validation.tar").is_file())

    def test_stale_module_cannot_replace_a_missing_job_artifact(self):
        for name in builder.MODULES:
            self.module(name)
        self.assemble()
        (self.inputs / "unaru/docc-validation.tar").unlink()
        with self.assertRaises(FileNotFoundError):
            self.assemble()
        self.assertFalse((self.output / "site/unaru").exists())

    def test_archive_cannot_write_outside_assembly_directory(self):
        stream = io.BytesIO()
        with tarfile.open(fileobj=stream, mode="w") as bundle:
            entry = tarfile.TarInfo("../outside")
            entry.size = 1
            bundle.addfile(entry, io.BytesIO(b"x"))
        stream.seek(0)
        with tarfile.open(fileobj=stream) as bundle, self.assertRaisesRegex(ValueError, "escapes"):
            builder.extract_modules(bundle, self.output)


if __name__ == "__main__":
    unittest.main()
