# Build and validate DocC

Use the toolchain in [Development](../docs/development.md).
The catalogs live with Shared, Backend, and the SwiftUI app sources.

Run the following commands from the repository root:

```fish
python3 Scripts/check-documentation.py
python3 Scripts/check-documentation-examples.py
python3 Scripts/build-documentation.py
```

The build extracts symbol graphs with SwiftPM and Xcode, checks declaration
comments, and runs DocC with analysis and warnings treated as errors. It then
checks the static module routes, JavaScript and stylesheet assets, and topic
references. A failed check stops publication.

The default hosting prefix is `/unaru`. Pass `--base-path /` when building for
a dedicated domain. Use the same prefix when checking the resulting site.

CI builds Shared and Backend documentation beside their package tests with
`--modules Shared Backend`. A separate Mac runner builds the app documentation
with `--modules unaru`, including both Mac helper architectures. Each job uploads
its module archives, inventories, and diagnostics. Linux assembly uses
`--assemble-only --inputs <directory>` to combine those artifacts and verify the
complete site. Missing module output fails assembly. The default local command
still builds and validates all three modules.

Outputs live in ignored `.build/documentation/`:

- `Shared.doccarchive`, `Backend.doccarchive`, and `unaru.doccarchive` contain module archives.
- `site/` contains the combined Pages site and its landing page.
- `api-inventory.json` records the documented declarations.
- Each module has diagnostics and DocC coverage output.
- `docc-validation.tar` packages the archives, site, inventory, and diagnostics for CI.

DocC filenames can contain colons. CI uploads the validation tar rather than
individual archive files.

Swift code fences in the Shared and Backend catalogs are complete Swift Testing
test bodies. After editing an example, regenerate the compilation units:

```fish
python3 Scripts/check-documentation-examples.py --write
swift test --package-path packages/Shared
swift test --package-path backend
```

Commit the generated tests with the catalog changes. The generation check rejects
stale examples, and the package suites compile and execute them without credentials.
