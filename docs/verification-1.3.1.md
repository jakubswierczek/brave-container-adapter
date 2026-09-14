# Version 1.3.1 verification

Date: 2026-09-14. Host: Apple silicon, macOS 26.6.2, Swift 6.3.3.
Installed Brave bundle version: `153.1.95.101`.

## Source checks

- 40 Swift Testing tests passed after the preset and shared-version changes.
- Optimized CLI and receiver build passed.
- Published baseline history: Gitleaks positive control passed, then no history findings.
- Five historical release ZIPs: checksums and targeted privacy scans passed.
- Gitleaks scans of the working source and all five ZIP payloads found no secrets.
- Repository structure, relative documentation links and shell syntax checks passed.

## Distribution checks

- Universal DMG built successfully, passed image verification and mounted read-only.
- Contents: Setup app, Applications shortcut and installation text. Setup reports 1.3.1.
- Copied Setup outside the DMG, verified its local signature, then ejected the image.
- The copied app opened its native window and displayed the expected empty state.
- Visually inspected all six rendered preset icons; lettering was visible and unclipped.

Signing, notarization and the final downloaded artifact checks are recorded here as
they complete. Documentation inside a release
app is frozen at build time; the repository copy of this record is authoritative
for checks performed after packaging.

## Coverage limits

Routing behavior is unchanged. This release's icon/packaging checks do not repeat
or extend the earlier browser integration proof. No third-party switcher, second
Mac, Intel runtime or macOS 14 runtime check is claimed. Use the [manual matrix](testing.md).
