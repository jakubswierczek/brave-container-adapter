# Signing and releases

Release downloads use `Brave-Container-Adapter.dmg` and its `.sha256` file. The setup
app and DMG are Developer ID signed and notarized. Local package builds and locally
generated destination apps are ad-hoc signed. Filenames do not describe signing state.

Apple lists **Account Holder** as the role required to create a Developer ID certificate. Some admins have access to cloud-managed certificates. This script needs a **local Developer ID Application certificate and its private key**; an Apple Development certificate or cloud-only identity does not satisfy it. See [Apple's certificate instructions](https://developer.apple.com/help/account/certificates/create-developer-id-certificates).

## Prepare the signing Mac

1. In Xcode Settings, select Apple Accounts (Accounts in some versions), your Apple ID, then the paid individual or company team. Open Manage Certificates. If permitted, add **Developer ID Application**. If this option is unavailable, the team's Account Holder must help provision the signing identity. A free Personal Team cannot issue this certificate. Do not revoke existing certificates.
2. Check locally:

   ```bash
   security find-identity -v -p codesigning
   ```

   Copy the 40-character hash next to the intended `Developer ID Application` identity. The signature identifies that individual or company.
3. Save notarization credentials in Keychain using an interactive Terminal session:

   ```bash
   xcrun notarytool store-credentials cbc-notary \
     --apple-id 'YOUR_APPLE_ID_EMAIL' --team-id 'YOUR_TEAM_ID'
   ```

   Use the team associated with your signing certificate. Find its Team ID in your developer account's Membership details. At the secure prompt, enter an [app-specific password](https://support.apple.com/en-us/102654) generated at account.apple.com under Sign-In and Security. This differs from your normal account password and the password protecting a certificate export. Enter it only locally, never in chat or a committed file. The explicit flags select Apple ID authentication without asking for an API private key. A suitable App Store Connect API key is another supported authentication method; see `xcrun notarytool store-credentials --help`.

## Build and notarize

Run checks from a clean source commit first. The signing script rejects uncommitted changes. Setup includes a public-safe `build-info.json` with its source commit, toolchain and dependency inventory. The release version and build number
come from `Sources/BraveDestinations/ReleaseVersion.swift`.

```bash
scripts/check-repo.py
scripts/test.sh
scripts/build.sh
scripts/notarize-setup.sh YOUR_40_CHARACTER_CERTIFICATE_HASH cbc-notary
```

The signing script verifies the local identity and saved credentials, builds both
architectures, and signs the receiver then Setup with Hardened Runtime and secure
timestamps. It submits an internal ZIP, waits for acceptance, and staples the app.
It then creates and signs the DMG, submits that image, and staples its ticket.
The two submissions let both the mounted disk and the copied app carry tickets.
No ZIP is published. See [Apple's notarization workflow](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).

Each attempt stays in ignored `dist/notarization.XXXXXX/`. It contains separate
`app-submission.json`, `app-result.json`, `app-log.json` and corresponding `dmg-*`
records. The script checks signatures, both architectures, ticket validity, image
integrity and Gatekeeper. Only a completed attempt gets its final DMG checksum.
It never publishes to GitHub.

## Monitor or resume

Each submission ID is printed after upload and saved before waiting. On the signing Mac:

```bash
xcrun notarytool info SUBMISSION_ID --keychain-profile cbc-notary
xcrun notarytool wait SUBMISSION_ID --keychain-profile cbc-notary --timeout 1h
xcrun notarytool log SUBMISSION_ID --keychain-profile cbc-notary report.json
```

`In Progress` gives no completion estimate. A wait timeout does not cancel Apple's
processing. Inspect the existing submission before uploading again. Failed or
incomplete attempts must not be distributed.

If the app submission later becomes accepted, staple and validate that same app,
create the DMG with `scripts/create-dmg.sh`, sign it, and submit the DMG. If only the
DMG wait timed out, continue with that same DMG after acceptance; do not rebuild.
These manual completion steps use the same commands as `scripts/notarize-setup.sh`.

## Validate the distribution

Replace the example path with the successful attempt directory:

```bash
cd dist/notarization.XXXXXX
shasum -a 256 -c Brave-Container-Adapter.dmg.sha256
hdiutil verify Brave-Container-Adapter.dmg
codesign --verify --strict Brave-Container-Adapter.dmg
xcrun stapler validate Brave-Container-Adapter.dmg
spctl --assess --type open --context context:primary-signature --verbose=2 Brave-Container-Adapter.dmg
```

Mount read-only. Confirm it contains Setup, the Applications shortcut and `Read Me.txt`.
Copy Setup outside the disk image. Verify its signature and ticket, both executable
architectures, then assess it with `spctl --assess --type execute --verbose=2`.
Open that copy, inspect icons and install a destination using disposable data.

Scan the DMG payload for real destination configuration, browser data, private paths,
credentials and unintended files. Embedded documentation must contain only public-safe
examples. A Developer ID signature exposes its publisher name and Team ID by design.

## Publish

Create a release from the verified source commit. Upload only the final DMG and
checksum. Keep credentials and notarization records local. Use a body file for release
notes and include exact checks, supported versions and remaining manual checks.
Download the uploaded assets again; verify checksum, signatures, tickets, image
contents and Gatekeeper. A GitHub CLI download does not simulate a browser's quarantine
first-open flow. Complete the [second-Mac matrix](testing.md) before claiming that proof.

Do not remove old releases, move tags or rewrite history without explicit authorization.
The v1.3.1 cleanup replaces the five earlier ZIP releases at the owner's request;
source tags remain for traceability. Changing the repository name does not change
existing app bundle identities.

## Signing scope

Destination apps contain new local configuration and bundle identities. The generator
ad-hoc signs them on the destination Mac. They do not inherit Setup's ticket, and no
signing private key is embedded in either app. Create destinations on each target Mac.
