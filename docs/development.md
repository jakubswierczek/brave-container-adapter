# Development

## Build and test

```bash
scripts/test.sh
scripts/build.sh
dist/bin/cbc help
# Optional: package the portable GUI for both Mac architectures
scripts/package-setup.sh
```

The scripts select `/Applications/Xcode.app` for that invocation if `DEVELOPER_DIR` is unset. They do not change `xcode-select`. Apple's standalone Command Line Tools can build the executables but may omit the `Testing` module. For a different Xcode installation:

```bash
DEVELOPER_DIR=/path/to/Xcode.app/Contents/Developer scripts/test.sh
```

The build places `cbc` and `ContainerReceiver` together in `dist/bin`. Keep them together when moving the CLI, or specify `--receiver /absolute/path/to/ContainerReceiver`. Generated apps copy the receiver into `Contents/MacOS`; they do not depend on `dist`, `.build`, or this checkout. Runtime dependencies are system frameworks and Swift libraries.


## Repository checks

```bash
scripts/check-repo.py
scripts/test.sh
scripts/build.sh
scripts/package-setup.sh
```

`check-repo.py` validates documentation links, the instruction symlink, shell syntax, and tracked-file hygiene. The macOS CI workflow runs these checks plus tests, release build and local DMG packaging. It uses read-only repository permissions, a pinned checkout action, and no signing secrets. The aggregate `checks` job is the required branch check. See [maintenance](maintenance.md) for runner retirement and release policy.

The package has no third-party Swift dependencies. Runtime APIs require macOS 14. Minimum deployment target is not proof of runtime compatibility; see [testing](testing.md).

## Version and packaging

`Sources/BraveDestinations/ReleaseVersion.swift` is the single source for release version and build number. `cbc version` prints both; destination generation and setup packaging use the same values. Increment the version and build number for a changed release binary.

`scripts/package-setup.sh` creates an ad-hoc signed universal setup and `dist/Brave-Container-Adapter.dmg`. This is a local build, not an Apple-notarized release. `--app-only OUTPUT_DIRECTORY` stages the app for the signing script. Outputs stay under ignored `dist/` unless explicitly overridden.

`scripts/create-dmg.sh SETUP_APP OUTPUT.dmg` packages a verified setup app, an Applications shortcut and installation text. It stages the disk image before replacing an existing output. The app's existing signature and ticket are preserved. See [release signing](signing.md) for distribution.

Keep tests synthetic. GUI checks must use disposable profiles and neutral URLs. Do not write Brave preferences or use personal sessions as fixtures. See [CONTRIBUTING.md](../CONTRIBUTING.md).

Each setup bundle includes `Contents/Resources/build-info.json`: source commit/tree, dirty-state flag, Xcode/Swift versions, build OS, architectures and dependency inventory. It excludes local paths and credentials. Signed release builds require a clean working tree. Signatures, timestamps and notarization tickets prevent a byte-reproducibility claim.
