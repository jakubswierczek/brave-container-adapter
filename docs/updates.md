# Setup updates

Only Brave Container Setup uses [Sparkle](https://sparkle-project.org/). The CLI,
receiver and generated destinations do not link it. Updating Setup does not replace
existing destination apps; regenerate those through Setup when needed.

Setup offers an explicit **Check for Updates…** action. Automatic checks, permission
prompts for automatic checks, automatic downloads/installations and system profiling
are disabled by bundled defaults. `SUAllowsAutomaticUpdates=false` removes Sparkle's
automatic installation option. Installing an offered update requires user action.

## Dependency and packaging

`Package.swift` pins Sparkle **2.10.0**, verified against the
[official stable release](https://github.com/sparkle-project/Sparkle/releases/tag/2.10.0).
`Package.resolved` pins its Git revision. SwiftPM verifies the upstream binary archive
checksum. `build-info.json` records version, revision, archive checksum, license and
Setup-only linking. Setup includes `Sparkle-LICENSE` with upstream third-party notices.

Packaging copies the universal framework into `Contents/Frameworks` with `ditto`,
preserving versioned-framework symlinks. Packaging builds explicit arm64 and x86_64
slices with native SwiftPM, then combines them with `lipo`; it verifies each slice
rather than assuming a multi-architecture driver returned universal binaries. Setup uses
`@executable_path/../Frameworks`; checkout-specific SwiftPM rpaths are removed.
`scripts/sign-setup.py` signs nested Mach-O files, XPC services, updater app,
framework and Setup inside out. It preserves helper entitlements, verifies signatures
and checks both architectures throughout. Local packaging uses ad-hoc signatures.
Developer ID packaging adds Hardened Runtime and timestamps before notarization.

## Key configuration

Tracked public configuration is `config/updater-public-key.txt`: one base64 Ed25519
public key, with an optional final newline. No example key is installed. Without that
file local builds remain usable, omit `SUPublicEDKey`, and disable Check for Updates.
Release notarization fails before building or submitting anything. A malformed file
also fails local packaging.

The private EdDSA key stays in Keychain under account **brave-container-adapter**.
A signing operator provisions it once, interactively, using the pinned distribution's
tools. These commands are operator steps, never automatic build steps:

```bash
swift package resolve
.build/artifacts/sparkle/Sparkle/bin/generate_keys --account brave-container-adapter
mkdir -p config
.build/artifacts/sparkle/Sparkle/bin/generate_keys \
  --account brave-container-adapter -p > config/updater-public-key.txt
python3 scripts/updater.py require-key
```

`generate_keys -p` only reads the existing public key; it does not generate one.
Review and commit the public file before release. Do not export the private key,
put it in source/environment variables, or pass it in arguments. Preserve the
Keychain item across signing-machine changes. Losing this key can block existing
clients; follow [Sparkle's key rotation rules](https://sparkle-project.org/documentation/#security).
Never rotate both the Developer ID identity and EdDSA key in one update.

## Appcast and release assets

Stable feed:

```text
https://github.com/jakubswierczek/brave-container-adapter/releases/latest/download/appcast.xml
```

After both app and DMG are notarized and stapled, `scripts/notarize-setup.sh`
checks the existing Keychain public key before any notarization upload,
creates the final checksum, then invokes `scripts/release-appcast.py ATTEMPT_DIRECTORY`.
The helper also supports completing a previously notarized attempt. It:

1. Requires a regular DMG and matching final SHA-256 checksum.
2. Verifies DMG signature, stapled ticket, image integrity and Gatekeeper assessment.
3. Mounts read-only; checks Setup, nested signatures, both architectures, app ticket
   and Gatekeeper. Reads version/build/minimum OS from that mounted app.
4. Requires bundled feed/key to match tracked configuration, and the signing account's
   existing public key to match both. No secret is exported.
5. Uses Sparkle's `sign_update` on the final DMG and verifies that signature.
6. Writes `appcast.xml` with build number, display version, minimum macOS **14.0.0**,
   exact byte length, EdDSA signature and immutable GitHub asset URL
   `/releases/download/vVERSION/Brave-Container-Adapter.dmg`.

The helper refuses existing `appcast.xml` and detects DMG changes during generation.
Never sign an intermediate DMG or modify/staple it after appcast generation. Release
assets are now exactly the final DMG, its `.sha256`, and `appcast.xml`. The release tag
must be `vVERSION` matching the bundled display version. Build numbers must increase
for every update. Publish a stable release, since GitHub's `latest` redirect excludes
prereleases and drafts. No script here publishes assets.

The feed contains the current full update only. No delta archives, separate release
notes, or signed-feed requirement are configured. HTTPS transports the feed;
`SUVerifyUpdateBeforeExtraction=true` requires a signed archive before extraction.
The EdDSA signature authenticates the DMG; Developer ID and notarization authenticate
the app. Follow [Sparkle's publishing guide](https://sparkle-project.org/documentation/publishing/).

## Verification

```bash
python3 scripts/test-updater.py
scripts/check-repo.py
scripts/test.sh
scripts/build.sh
scripts/package-setup.sh
```

Synthetic helper tests cover malformed/missing public configuration, manual defaults,
appcast metadata, changed DMGs, bundle-key mismatch and Keychain-key mismatch without
accessing Keychain or signing anything. Package checks inspect all nested code,
symlinks, universal architectures, standalone rpath and receiver/CLI isolation.

Mount the local DMG and inspect its copied app with `scripts/sign-setup.py`.
For actual updater integration, use two signed/notarized builds and a controlled feed:
verify no network check on launch, manual check/no-update/failure states, offered
version, signature rejection after archive tampering, explicit install/relaunch and
installed version. Use a disposable app copy and defaults domain; never downgrade or
replace the user's installed copy. A local package check does not establish this
end-to-end update coverage. Existing releases without Sparkle require one manual DMG
installation before they can update in-app.
