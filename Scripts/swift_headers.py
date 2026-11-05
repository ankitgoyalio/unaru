"""Generate Swift headers once and validate recorded metadata without Git history."""

from datetime import datetime, timezone
import os
from pathlib import Path
import re

SWIFTFORMAT_VERSION = "0.64.5"
MISSING_HEADER = "missing source header"
HEADER = re.compile(
    rb"\A//\r?\n//  (?P<filename>[^\r\n]+)\r?\n//  unaru\r?\n//\r?\n"
    rb"//  Created by (?P<author>[^\r\n]*) on (?P<date>[^\r\n]*)\.\r?\n(?:\r?\n|\Z)"
)


def filename(path):
    """Keep filenames on one comment line, including Git's unusual filenames."""
    return (os.fsencode(Path(os.fsdecode(path)).name).replace(b"\\", b"\\\\")
            .replace(b"\r", b"\\r").replace(b"\n", b"\\n"))


def is_manifest(path, content):
    # Match SwiftFormat's exception for SwiftPM's required first-line directive.
    return Path(os.fsdecode(path)).name == "Package.swift" and content.startswith(b"// swift-tools-version:")


def valid_author(author):
    return (bool(author) and author == author.strip()
            and not any(ord(char) < 32 for char in author)
            and "{" not in author and "}" not in author)


def recorded_header(content):
    match = HEADER.match(content)
    if match is None:
        # Do not replace damaged metadata with a newly invented author or date.
        first_comment = content.split(b"\n\n", 1)[0]
        if (content.startswith((b"//\n//  ", b"//\r\n//  "))
                or content.startswith((b"//", b"/*")) and b"Created by" in first_comment):
            raise ValueError("malformed source header; correct the existing author and date")
        return None
    author = match["author"].decode("utf-8")
    if not valid_author(author):
        raise ValueError("source header needs a nonempty author without surrounding whitespace")
    date = match["date"].decode("ascii")
    if not re.fullmatch(r"\d{2}/\d{2}/\d{4}", date):
        raise ValueError("source header date must use DD/MM/YYYY")
    try:
        datetime.strptime(date, "%d/%m/%Y")
    except ValueError as error:
        raise ValueError("source header date must be a valid calendar date") from error
    return match


def header_error(path, content):
    """Return a diagnostic for a missing or invalid header, without modifying it."""
    if is_manifest(path, content):
        return None
    try:
        header = recorded_header(content)
    except (ValueError, UnicodeError) as error:
        return str(error)
    if header is None:
        return MISSING_HEADER
    if header["filename"] != filename(path):
        return "source header filename does not match the file"
    return None


def format_header(path, content, *, author=None, today=None):
    """Add missing metadata or update a renamed file, preserving recorded identity."""
    if is_manifest(path, content):
        return content
    header = recorded_header(content)
    name = filename(path)
    if header is not None:
        start, end = header.span("filename")
        return content[:start] + name + content[end:]
    if not valid_author(author):
        raise ValueError("configure git user.name before generating a missing source header")
    date = (today or datetime.now(timezone.utc).date()).strftime("%d/%m/%Y").encode("ascii")
    return (b"//\n//  " + name + b"\n//  unaru\n//\n//  Created by "
            + author.encode("utf-8") + b" on " + date + b".\n\n" + content)
