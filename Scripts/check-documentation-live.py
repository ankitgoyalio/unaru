#!/usr/bin/env python3
"""Verify published DocC landing routes and module render data over HTTPS."""

import argparse
import json
from urllib.request import Request, urlopen
from urllib.error import URLError
import time


def fetch(url):
    # Pages can take a few seconds to serve a deployment after the API completes.
    for attempt in range(5):
        try:
            with urlopen(Request(url, headers={"User-Agent": "unaru-docs-check"}), timeout=30) as response:
                if response.status != 200:
                    raise ValueError(f"Unexpected HTTP status for {url}: {response.status}")
                return response.read()
        except (URLError, TimeoutError):
            if attempt == 4:
                raise
            time.sleep(3)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("url", help="Pages site URL, including its repository path")
    args = parser.parse_args()
    base = args.url.rstrip("/")
    if b"Unaru development documentation" not in fetch(base + "/"):
        raise ValueError("The published site is missing its Unaru landing page")
    for module in ("shared", "backend", "unaru"):
        fetch(f"{base}/{module}/documentation/{module}/")
        data = json.loads(fetch(f"{base}/{module}/data/documentation/{module}.json"))
        if data["identifier"]["interfaceLanguage"] != "swift":
            raise ValueError(f"Unexpected module render data: {module}")
    print(f"Verified published documentation: {base}/")


if __name__ == "__main__":
    main()
