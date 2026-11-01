#!/usr/bin/env python3
"""Build all Unaru DocC catalogs, audit coverage, and package a Pages site."""

import argparse
import json
from pathlib import Path
import platform
import shutil
import subprocess
import sys
import tarfile

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / ".build/documentation"
MODULES = {
    "Shared": ("packages/Shared", "Sources/Shared/Shared.docc", "public"),
    "Backend": ("backend", "Sources/Backend/Backend.docc", "internal"),
    "unaru": ("apps/unaru", "unaru/unaru.docc", "internal"),
}


def run(*args, cwd=ROOT):
    subprocess.run(args, cwd=cwd, check=True)


def audit_coverage(module, graphs):
    """Require comments on authored declarations and omit compiler-generated symbols."""
    inventory = {}
    missing = []
    for graph in graphs.glob("*.json"):
        data = json.loads(graph.read_text())
        symbols = data["symbols"]
        authored = []
        type_locations = {
            json.dumps(symbol["location"], sort_keys=True)
            for symbol in symbols
            if symbol["kind"]["identifier"] in {"swift.struct", "swift.class", "swift.enum"}
            and "location" in symbol
        }
        for symbol in symbols:
            if not symbol.get("location"):
                continue
            # Implicit memberwise initializers point at their type declaration.
            if (symbol["kind"]["identifier"] == "swift.init"
                    and json.dumps(symbol["location"], sort_keys=True) in type_locations):
                continue
            identifier = symbol["identifier"]["precise"]
            inventory[identifier] = symbol["names"]["title"]
            authored.append(symbol)
            if not any(line["text"].strip() for line in symbol.get("docComment", {}).get("lines", [])):
                missing.append(symbol["names"]["title"])
        data["symbols"] = authored
        identifiers = {symbol["identifier"]["precise"] for symbol in authored}
        data["relationships"] = [
            relationship for relationship in data.get("relationships", [])
            if relationship["source"] in identifiers
        ]
        graph.write_text(json.dumps(data))
    if not inventory:
        sys.exit(f"No authored {module} symbols were extracted.")
    if missing:
        sys.exit(f"Undocumented {module} symbols: {', '.join(sorted(set(missing)))}")
    return inventory


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base-path", default="/unaru", help="Pages project path, or / for a custom domain")
    args = parser.parse_args()
    base = "/" + args.base_path.strip("/") if args.base_path.strip("/") else ""
    run(sys.executable, "Scripts/check-documentation.py")
    run(sys.executable, "Scripts/check-documentation-examples.py")
    docc = shutil.which("docc")
    if not docc:
        docc = subprocess.check_output(["xcrun", "--find", "docc"], text=True).strip()
    site = OUTPUT / "site"
    if site.exists():
        shutil.rmtree(site)
    site.mkdir(parents=True)
    inventories = {}
    for module, (package, catalog, access) in MODULES.items():
        package = ROOT / package
        graphs = OUTPUT / "symbols" / module
        if graphs.exists():
            shutil.rmtree(graphs)
        graphs.mkdir(parents=True)
        if module == "unaru":
            run("xcodebuild", "build", "-project", "apps/unaru/unaru.xcodeproj",
                "-scheme", "unaru", "-destination", "generic/platform=macOS",
                "-derivedDataPath", str(ROOT / ".build/docc-app"),
                "CODE_SIGNING_ALLOWED=NO", "ONLY_ACTIVE_ARCH=YES")
            sdk = subprocess.check_output(["xcrun", "--show-sdk-path"], text=True).strip()
            run("xcrun", "swift-symbolgraph-extract", "-module-name", "unaru",
                "-I", str(ROOT / ".build/docc-app/Build/Products/Debug"),
                "-target", f"{platform.machine()}-apple-macosx15.0", "-sdk", sdk,
                "-minimum-access-level", "internal", "-skip-synthesized-members",
                "-output-dir", str(graphs))
        else:
            run("swift", "package", "dump-symbol-graph", "--minimum-access-level", access,
                "--skip-synthesized-members", cwd=package)
            for graph in (package / ".build/out/symbolgraph").glob(f"{module}*.symbols.json"):
                shutil.copy2(graph, graphs / graph.name)
        inventories[module] = audit_coverage(module, graphs)
        archive = OUTPUT / f"{module}.doccarchive"
        if archive.exists():
            shutil.rmtree(archive)
        run(docc, "convert", str(package / catalog),
            "--additional-symbol-graph-dir", str(graphs), "--output-path", str(archive),
            "--fallback-bundle-identifier", f"io.ankitgoyal.unaru.{module}",
            "--fallback-display-name", module, "--warnings-as-errors", "--analyze",
            "--experimental-documentation-coverage", "--coverage-summary-level", "detailed",
            "--transform-for-static-hosting", "--hosting-base-path", f"{base}/{module.lower()}",
            "--diagnostics-file", str(OUTPUT / f"{module}-diagnostics.json"))
        shutil.copytree(archive, site / module.lower())
    (OUTPUT / "api-inventory.json").write_text(json.dumps(inventories, indent=2) + "\n")
    links = "\n".join(
        f'<li><a href="{base}/{module.lower()}/documentation/{module.lower()}/">{module}</a></li>'
        for module in MODULES
    )
    (site / "index.html").write_text(
        '<!doctype html><html lang="en"><head><meta charset="utf-8">'
        '<meta name="viewport" content="width=device-width, initial-scale=1">'
        '<title>Unaru documentation</title></head><body><main>'
        '<h1>Unaru development documentation</h1><ul>' + links + '</ul>'
        '<p>Documentation for the current main branch.</p></main></body></html>\n'
    )
    (site / ".nojekyll").touch()
    run(sys.executable, "Scripts/check-documentation-site.py", str(site), "--base-path", base or "/")
    # DocC symbol filenames contain colons, which upload-artifact rejects.
    with tarfile.open(OUTPUT / "docc-validation.tar", "w") as bundle:
        for path in sorted(OUTPUT.iterdir()):
            if path.name == "site" or path.suffix in {".doccarchive", ".json"}:
                bundle.add(path, arcname=path.name)
    print(f"Verified Pages artifact: {site}")


if __name__ == "__main__":
    main()
