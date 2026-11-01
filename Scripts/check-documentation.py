#!/usr/bin/env python3
"""Reject execution artifacts and broken local links in tracked documentation."""
import argparse
import html
from pathlib import PurePosixPath
import posixpath
import re
import subprocess
import sys
import unicodedata
from urllib.parse import unquote, urlsplit


GUIDES = {"README.md", "DocC.md", "Pages.md"}
ROOT_GUIDES = {"README.md", "AGENTS.md", "GLOSSARY.md", "CONTRIBUTING.md", "SECURITY.md"}
PROJECT_GUIDES = {"development.md", "agents/domain.md", "agents/issue-tracker.md",
                  "agents/triage-labels.md"}


def project_markdown(name):
    path = PurePosixPath(name)
    return path.suffix == ".md" and (
        len(path.parts) == 1 or name.startswith(("Documentation/", "docs/", "backend/", "packages/", "apps/"))
    )


def git(*args):
    return subprocess.check_output(["git", *args])


def without_fences(text):
    """Ignore fenced examples, including fences longer than three characters."""
    lines = []
    fence = None
    for line in text.splitlines():
        match = re.match(r"^ {0,3}(`{3,}|~{3,})(.*)$", line)
        if fence:
            if match and match[1][0] == fence[0] and len(match[1]) >= len(fence) and not match[2].strip():
                fence = None
            lines.append("")
        elif match:
            fence = match[1]
            lines.append("")
        else:
            lines.append(line)
    return "\n".join(lines)


def markdown_links(text):
    """Extract inline destinations, accepting balanced parentheses and link titles."""
    for match in re.finditer(r"\]\(\s*(<[^>\n]*>|[^\s<>]*)", text):
        destination = match[1]
        if destination.startswith("<"):
            yield destination[1:-1]
        else:
            # The regex consumes closing delimiters. Stop at the unmatched one,
            # retaining parentheses that belong to a file name or URL.
            depth = 0
            end = len(destination)
            for index, char in enumerate(destination):
                if char == "(":
                    depth += 1
                elif char == ")":
                    if depth == 0:
                        end = index
                        break
                    depth -= 1
            yield destination[:end]


def markdown_anchors(text):
    """Collect ordinary Markdown heading slugs and explicit HTML anchors."""
    text = without_fences(text)
    anchors = set()
    for tag in re.findall(r"<[A-Za-z][^>]*>", text):
        for value in re.findall(r"\b(?:id|name)\s*=\s*[\"']([^\"']+)[\"']", tag, re.I):
            anchors.add(html.unescape(value))
    used = set()
    lines = text.splitlines()
    for index, line in enumerate(lines):
        atx = re.match(r"^ {0,3}#{1,6}(?:[ \t]+(.*?)|[ \t]*)$", line)
        if atx:
            heading = re.sub(r"[ \t]+#+[ \t]*$", "", atx[1] or "")
        elif index + 1 < len(lines) and line.strip() and re.fullmatch(r" {0,3}(?:=+|-+)[ \t]*", lines[index + 1]):
            heading = line.strip()
        else:
            continue
        heading = re.sub(r"!?\[([^\]]*)\]\([^)]*\)", r"\1", heading)
        heading = html.unescape(re.sub(r"<[^>]*>", "", heading))
        heading = re.sub(r"(?<!\w)_{1,2}(.+?)_{1,2}(?!\w)", r"\1", heading)
        heading = re.sub(r"[*`~]", "", heading).lower()
        slug = "".join(char for char in heading if char in "_- " or char.isspace() or unicodedata.category(char)[0] in "LNM")
        slug = re.sub(r"\s", "-", slug)
        candidate = slug
        suffix = 0
        while candidate in used:
            suffix += 1
            candidate = f"{slug}-{suffix}"
        used.add(candidate)
        anchors.add(candidate)
    return anchors


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--staged", action="store_true", help="Read staged blobs, not working copies")
    args = parser.parse_args()
    paths = set(git("ls-files", "--cached", "-z").decode().strip("\0").split("\0")) - {""}
    errors = []
    for name in sorted(paths):
        path = PurePosixPath(name)
        if len(path.parts) == 1 and path.suffix == ".md" and name not in ROOT_GUIDES:
            errors.append(f"{name}: unregistered project guide; update an existing guide or register a durable topic in ROOT_GUIDES")
        if name.startswith("docs/"):
            relative = str(path.relative_to("docs"))
            adr = re.fullmatch(r"adr/\d{4}-[a-z0-9]+(?:-[a-z0-9]+)*\.md", relative)
            if relative not in PROJECT_GUIDES and not adr:
                errors.append(f"{name}: execution/history artifact or unregistered project guide; keep plans and publication records in GitHub Issues; register durable topics in PROJECT_GUIDES")
        if not name.startswith("Documentation/"):
            continue
        relative = str(path.relative_to("Documentation"))
        historical = re.match(r"(?:Evidence/|Ticket-\d+\.md$|Review\.md$|Partial-0x\.md$)", relative, re.I)
        if historical or relative not in GUIDES:
            errors.append(f"{name}: execution/history artifact or unregistered guide; use .test-results/, CI artifacts or the GitHub issue/PR; register intentional new guides in GUIDES")
    contents = {}
    anchors = {}

    def read(name):
        if name not in contents:
            contents[name] = (git("show", ":" + name).decode() if args.staged
                              else open(name, encoding="utf-8").read())
        return contents[name]

    # Remote URLs are not fetched. DocC symbol anchors require the DocC renderer;
    # retain path checks there but validate fragments only in ordinary Markdown.
    for name in sorted(paths):
        if not project_markdown(name):
            continue
        text = read(name)
        for target in markdown_links(without_fences(text)):
            parsed = urlsplit(target)
            if parsed.scheme or parsed.netloc:
                continue
            local = unquote(parsed.path)
            resolved = (posixpath.normpath(posixpath.join(posixpath.dirname(name), local))
                        if local else name)
            if resolved not in paths and not any(p.startswith(resolved + "/") for p in paths):
                errors.append(f"{name}: broken local link {target}")
                continue
            if parsed.fragment and resolved in paths and resolved.endswith(".md") and ".docc/" not in resolved:
                if resolved not in anchors:
                    anchors[resolved] = markdown_anchors(read(resolved))
                if unquote(parsed.fragment) not in anchors[resolved]:
                    errors.append(f"{name}: broken local fragment {target}")
    if errors:
        print("Documentation check failed:\n" + "\n".join(errors), file=sys.stderr)
        return 1
    print("Documentation layout and tracked local links verified" + (" (staged)" if args.staged else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main())
