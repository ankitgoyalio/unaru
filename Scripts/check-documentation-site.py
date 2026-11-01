#!/usr/bin/env python3
"""Verify the landing routes, render data, and assets of the static DocC site."""

import argparse
from html.parser import HTMLParser
import json
from pathlib import Path
import sys
from urllib.parse import unquote, urlsplit


class Assets(HTMLParser):
    def __init__(self):
        super().__init__()
        self.paths = []

    def handle_starttag(self, tag, attrs):
        for key, value in attrs:
            if value and ((tag == "script" and key == "src") or (tag == "link" and key == "href")):
                self.paths.append(value)


def check_site(site, base):
    base = "/" + base.strip("/") if base.strip("/") else ""
    if not (site / "index.html").is_file() or not (site / ".nojekyll").is_file():
        raise ValueError("Missing site landing page or .nojekyll")
    count = 0
    for module in ("shared", "backend", "unaru"):
        root = site / module
        landing = root / "documentation" / module / "index.html"
        if not landing.is_file():
            raise ValueError(f"Missing static landing route: {landing}")
        parser = Assets()
        parser.feed(landing.read_text())
        for asset in parser.paths:
            url = urlsplit(asset)
            if url.scheme or url.netloc:
                continue
            path = unquote(url.path)
            prefix = f"{base}/{module}/"
            if not path.startswith(prefix):
                raise ValueError(f"Wrong hosting prefix in {module}: {path}")
            if not (root / path[len(prefix):]).is_file():
                raise ValueError(f"Missing asset in {module}: {path}")
        pages = list((root / "data/documentation").rglob("*.json"))
        if not pages:
            raise ValueError(f"No render data for {module}")
        for page in pages:
            data = json.loads(page.read_text())
            for reference in data.get("references", {}).values():
                url = reference.get("url", "")
                if reference.get("type") == "topic" and url.startswith("/documentation/"):
                    target = root / "data" / (url.lstrip("/") + ".json")
                    if not target.is_file():
                        raise ValueError(f"Broken DocC topic in {page}: {url}")
            count += 1
    return count


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("site", type=Path)
    parser.add_argument("--base-path", default="/unaru")
    args = parser.parse_args()
    try:
        count = check_site(args.site, args.base_path)
    except (ValueError, OSError) as error:
        sys.exit(str(error))
    print(f"Verified static routes, assets, and {count} DocC render pages")


if __name__ == "__main__":
    main()
