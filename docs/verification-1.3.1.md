# Version 1.3.1 verification

Date: 2026-09-14. Host: Apple silicon, macOS 26.6.2, Swift 6.3.3.
Installed Brave bundle version: `153.1.95.101`.
Release source: `be47ad0f47b236e7d2f05188126d5ddc7a400d66`.

## Source checks

- 40 Swift Testing tests passed after the preset and shared-version changes.
- Optimized CLI and receiver build passed.
- Published baseline history: Gitleaks positive control passed, then no history findings.
- Five historical release ZIPs: checksums and targeted privacy scans passed.
- Gitleaks scans of the working source and all five ZIP payloads found no secrets.
- Repository structure, relative documentation links and shell syntax checks passed.
- CLI smoke with synthetic files passed: Temporary generation, version metadata,
  name/icon update, unchanged bundle identity and signature verification.
- DMG packaging rejected an unrelated input app and preserved the existing output.
- [Hosted macOS CI](https://github.com/jakubswierczek/brave-container-adapter/actions/runs/34850698611)
  passed repository checks, all 40 tests, release build and universal DMG packaging.
  Runner: `macos-15-arm64`, image `20260907.0337.1`, macOS SDK 15.5 for packaging.

## Distribution checks

- Universal DMG built successfully, passed image verification and mounted read-only.
- Contents: Setup app, Applications shortcut and installation text. Setup reports 1.3.1.
- Copied Setup outside the DMG, verified its local signature, then ejected the image.
- The copied app opened its native window and displayed the expected empty state.
- Visually inspected all six rendered preset icons; lettering was visible and unclipped.

- App notarization `72aacddd-879d-486b-9f44-a54b26761e81`: **Accepted**, no issues.
- DMG notarization `a7d13db0-40e3-4114-831d-5e87030eb3e6`: **Accepted**, no issues.
- App and disk image passed strict signature, stapled-ticket and Gatekeeper checks.
  Both app executables passed arm64/x86_64 verification with Xcode's `lipo`.
- The signed app copied from the mounted image opened its native window.
- Targeted privacy scan of the signed app's 21 files and a Gitleaks payload scan
  found no private-path, credential or browser-configuration matches.
- A fresh GitHub download passed SHA-256, image integrity, DMG/app/receiver signature,
  both ticket and both Gatekeeper checks. The downloaded image mounted successfully.
- Removed releases v1.1.0, v1.1.1, v1.1.2, v1.2.0 and v1.3.0, including their ZIP and
  checksum assets. Retained their source tags. v1.3.1 is the sole published release.

[Release](https://github.com/jakubswierczek/brave-container-adapter/releases/tag/v1.3.1):
`Brave-Container-Adapter.dmg` and `Brave-Container-Adapter.dmg.sha256`.

DMG SHA-256:

```text
e39da332b513a5e1d213abfdde87d3d9b0b037c45f218bd774eb8d5c55a05ccc
```

Documentation inside a release app is frozen at build time; this repository record
includes checks performed after packaging. The DMG has not been rebuilt after signing.

## Coverage limits

Routing behavior is unchanged. This release's icon/packaging checks do not repeat
or extend the earlier browser integration proof. No third-party switcher, second
Mac, Intel runtime or macOS 14 runtime check is claimed. Use the [manual matrix](testing.md).
