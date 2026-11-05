"""Validate header generation and immutable recorded metadata."""

from datetime import date
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "Scripts"))
from swift_headers import format_header, header_error

HEADER = b"//\n//  Example.swift\n//  unaru\n//\n//  Created by Original Author on 04/11/2026.\n\n"


class SwiftHeaderTests(unittest.TestCase):
    def test_missing_header_uses_supplied_author_and_date_and_keeps_doc_comments(self):
        source = b"/// A documented value.\nlet value = 1\n"
        self.assertEqual(format_header("Example.swift", source, author="Original Author",
                                       today=date(2026, 11, 4)), HEADER + source)
        self.assertIn("missing", header_error("Example.swift", source))

    def test_existing_header_ignores_current_identity_and_date(self):
        source = HEADER + b"let value = 1\n"
        self.assertEqual(format_header("Example.swift", source, author="Squash Author",
                                       today=date(2026, 11, 5)), source)
        self.assertIsNone(header_error("Example.swift", source))
        self.assertEqual(format_header("Example.swift", source), source)

    def test_rename_updates_only_filename(self):
        source = HEADER + b"let value = 1\n"
        self.assertIn("filename", header_error("Renamed.swift", source))
        self.assertEqual(format_header("Renamed.swift", source),
                         source.replace(b"Example.swift", b"Renamed.swift"))

    def test_malformed_metadata_is_rejected_without_guessing(self):
        for source in (HEADER.replace(b"04/11/2026", b"31/02/2026"),
                       HEADER.replace(b"04/11/2026", b"4/11/2026"),
                       HEADER.replace(b"Original Author", b""),
                       HEADER.replace(b"Original Author", b"{author.name}"),
                       HEADER.replace(b" on ", b" at "),
                       HEADER.replace(b"\n\n", b"\n") + b"let value = 1\n"):
            with self.subTest(source=source):
                self.assertIsNotNone(header_error("Example.swift", source))
                with self.assertRaises(ValueError):
                    format_header("Example.swift", source, author="New Author")

    def test_missing_header_requires_configured_identity(self):
        for author in (None, "", " ", "Author\nInjected", " Author"):
            with self.subTest(author=author), self.assertRaises(ValueError):
                format_header("Example.swift", b"let value = 1\n", author=author)

    def test_package_manifests_keep_required_directive(self):
        content = b"// swift-tools-version: 6.4\nimport PackageDescription\n"
        self.assertIsNone(header_error("backend/Package.swift", content))
        self.assertEqual(format_header("backend/Package.swift", content), content)
        self.assertIsNotNone(header_error("Other.swift", content))

    def test_unicode_and_control_characters_in_filenames_stay_in_comment(self):
        path = "folder/雪 ' quote\nfile.swift"
        content = format_header(path, b"let value = 1\n", author="Original Author",
                                today=date(2026, 11, 4))
        self.assertEqual(content.splitlines()[1], "//  雪 ' quote\\nfile.swift".encode())
        self.assertIsNone(header_error(path, content))

    def test_crlf_metadata_is_preserved(self):
        content = HEADER.replace(b"\n", b"\r\n") + b"let value = 1\r\n"
        self.assertIsNone(header_error("Example.swift", content))
        self.assertEqual(format_header("Example.swift", content), content)


if __name__ == "__main__":
    unittest.main()
