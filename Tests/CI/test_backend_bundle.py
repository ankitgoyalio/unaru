"""Keep current-run helper reuse restricted to complete Debug CI artifacts."""

import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class BackendBundleTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        tools = self.root / "bin"
        tools.mkdir()
        xcrun = tools / "xcrun"
        xcrun.write_text(
            "#!/usr/bin/env python3\n"
            "from pathlib import Path\nimport sys\n"
            "assert sys.argv[1] == 'lipo', 'Prebuilt slices must not invoke SwiftPM'\n"
            "if sys.argv[2] == '-archs':\n"
            "    print(Path(sys.argv[3]).read_text())\n"
            "else:\n"
            "    assert sys.argv[2] == '-create'\n"
            "    assert len(sys.argv[3:sys.argv.index('-output')]) == 2\n"
            "    Path(sys.argv[-1]).write_text('universal Backend')\n"
        )
        xcrun.chmod(0o755)
        slices = self.root / "slices"
        for architecture in ("arm64", "x86_64"):
            (slices / architecture).mkdir(parents=True)
            (slices / architecture / "Backend").write_text(architecture)
        self.environment = os.environ | dict(
            PATH=str(tools) + os.pathsep + os.environ["PATH"],
            PLATFORM_NAME="macosx", SRCROOT=str(ROOT / "apps/unaru"),
            CONFIGURATION="Debug", TARGET_BUILD_DIR=str(self.root / "build"),
            CONTENTS_FOLDER_PATH="unaru.app/Contents", ARCHS="arm64 x86_64",
            CODE_SIGNING_ALLOWED="NO", CI="true", UNARU_PREBUILT_BACKENDS_DIR=str(slices),
        )

    def build(self, **overrides):
        return subprocess.run(["sh", str(ROOT / "Scripts/bundle-backend.sh")],
                              env=self.environment | overrides, capture_output=True, text=True)

    def test_combines_both_current_run_architectures_without_recompiling(self):
        result = self.build()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.root / "build/unaru.app/Contents/Helpers/Backend").read_text(),
                         "universal Backend")

    def test_rejects_missing_or_wrong_architecture(self):
        binary = self.root / "slices/x86_64/Backend"
        binary.write_text("arm64")
        self.assertNotEqual(self.build().returncode, 0)
        binary.unlink()
        self.assertNotEqual(self.build().returncode, 0)

    def test_distribution_and_local_builds_cannot_reuse_ci_artifacts(self):
        self.assertNotEqual(self.build(CONFIGURATION="Release").returncode, 0)
        self.assertNotEqual(self.build(CI="false").returncode, 0)


if __name__ == "__main__":
    unittest.main()
