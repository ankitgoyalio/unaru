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
import time

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / ".build/documentation"
MODULES = {
    "Shared": ("packages/Shared", "Sources/Shared/Shared.docc", "public"),
    "Backend": ("backend", "Sources/Backend/Backend.docc", "internal"),
    "unaru": ("apps/unaru", "unaru/unaru.docc", "internal"),
}


def run(*args, cwd=ROOT):
    started = time.monotonic()
    print("Running: " + " ".join(map(str, args)), flush=True)
    try:
        subprocess.run(args, cwd=cwd, check=True)
    finally:
        print(f"Elapsed: {time.monotonic() - started:.1f}s", flush=True)


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


def extract_modules(bundle, output):
    """Extract regular documentation files safely on Python 3.9 and later."""
    for member in bundle:
        destination = (output / member.name).resolve()
        if not destination.is_relative_to(output.resolve()):
            raise ValueError(f"Archive path escapes documentation output: {member.name}")
        if member.isdir():
            destination.mkdir(parents=True, exist_ok=True)
        elif member.isfile():
            destination.parent.mkdir(parents=True, exist_ok=True)
            with bundle.extractfile(member) as source, destination.open("wb") as target:
                shutil.copyfileobj(source, target)
        else:
            raise ValueError(f"Unexpected documentation archive entry: {member.name}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base-path", default="/unaru", help="Pages project path, or / for a custom domain")
    parser.add_argument("--modules", nargs="+", choices=MODULES, default=list(MODULES))
    parser.add_argument("--assemble-only", action="store_true", help="Verify and combine previously built modules")
    parser.add_argument("--inputs", type=Path, help="Directory containing module validation tar files")
    args = parser.parse_args()
    base = "/" + args.base_path.strip("/") if args.base_path.strip("/") else ""
    run(sys.executable, "Scripts/check-documentation.py")
    run(sys.executable, "Scripts/check-documentation-examples.py")
    if args.inputs and args.assemble_only and OUTPUT.exists():
        if OUTPUT.resolve() in args.inputs.resolve().parents:
            parser.error("Module inputs must be outside the assembly output directory")
        shutil.rmtree(OUTPUT)
    OUTPUT.mkdir(parents=True, exist_ok=True)
    if args.inputs:
        if not args.assemble_only:
            parser.error("--inputs requires --assemble-only")
        for archive in sorted(args.inputs.rglob("docc-validation.tar")):
            with tarfile.open(archive) as bundle:
                extract_modules(bundle, OUTPUT)
    docc = shutil.which("docc") if not args.assemble_only else None
    if not docc and not args.assemble_only:
        docc = subprocess.check_output(["xcrun", "--find", "docc"], text=True).strip()
    site = OUTPUT / "site"
    if site.exists():
        shutil.rmtree(site)
    site.mkdir(parents=True)
    inventories = {}
    for module in ([] if args.assemble_only else args.modules):
        package, catalog, access = MODULES[module]
        package = ROOT / package
        graphs = OUTPUT / "symbols" / module
        if graphs.exists():
            shutil.rmtree(graphs)
        graphs.mkdir(parents=True)
        if module == "unaru":
            run("xcodebuild", "build", "-project", "apps/unaru/unaru.xcodeproj",
                "-scheme", "unaru", "-destination", "generic/platform=macOS",
                "-derivedDataPath", str(ROOT / ".build/docc-app"),
                "CODE_SIGNING_ALLOWED=NO", "ONLY_ACTIVE_ARCH=YES", "-showBuildTimingSummary")
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
        (OUTPUT / f"{module}-inventory.json").write_text(json.dumps(inventories[module], indent=2) + "\n")
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
    # Partial builds package only their own modules. Assembly fails on any missing
    # module instead of publishing a partial site or a previous build's output.
    complete = args.assemble_only or set(args.modules) == set(MODULES)
    if not complete:
        with tarfile.open(OUTPUT / "docc-validation.tar", "w") as bundle:
            for module in args.modules:
                for name in (f"{module}.doccarchive", f"{module}-inventory.json", f"{module}-diagnostics.json"):
                    bundle.add(OUTPUT / name, arcname=name)
        return
    for module in MODULES:
        inventory = json.loads((OUTPUT / f"{module}-inventory.json").read_text())
        json.loads((OUTPUT / f"{module}-diagnostics.json").read_text())
        if not inventory:
            sys.exit(f"Missing {module} API inventory")
        inventories[module] = inventory
        shutil.copytree(OUTPUT / f"{module}.doccarchive", site / module.lower())
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
