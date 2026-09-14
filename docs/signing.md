# Developer ID signing

The v1.1.1, v1.1.2, and v1.2.0 ZIPs are Developer ID signed and notarized. The older v1.1.0 ZIP is ad-hoc signed. Developer ID releases use the `-notarized.zip` filename. An individual or company Apple Developer Program membership can provide Developer ID signing, but membership alone does not install a certificate or grant certificate creation rights.

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

From the checkout on the signing Mac:

```bash
scripts/notarize-setup.sh YOUR_40_CHARACTER_CERTIFICATE_HASH cbc-notary
```

The script verifies the identity and saved credentials before building. It signs the embedded receiver and then the setup app with Hardened Runtime and secure timestamps. It submits the ZIP to Apple, requires an `Accepted` result, staples and validates the ticket, and requires a successful Gatekeeper assessment before making the distribution ZIP. These steps follow [Apple's notarization requirements](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).

Each attempt stays in an ignored `dist/notarization.XXXXXX/` directory. A successful attempt contains `Brave-Container-Setup-notarized.zip` and its SHA-256 file. Failed or timed-out attempts retain `result.json` and the submitted app for diagnosis. A timeout does not cancel Apple's processing. Use the submission ID with `xcrun notarytool info` or `log` and the same Keychain profile before deciding to resubmit. The script does not publish releases or overwrite a previous attempt.

After success, test the ZIP downloaded onto another Mac and publish that exact ZIP/checksum. Confirm that setup opens and can install a destination, then check browser-switcher routing. A local Gatekeeper assessment alone does not prove a clean download works.

## Check submission status

On the Mac where the Keychain profile is saved, replace `SUBMISSION_ID` with the
ID printed when the upload completes:

```bash
xcrun notarytool info SUBMISSION_ID --keychain-profile cbc-notary
```

To keep polling in Terminal until completion or a one-hour timeout:

```bash
xcrun notarytool wait SUBMISSION_ID --keychain-profile cbc-notary --timeout 1h
```

`In Progress` means Apple is still processing. `Accepted` means notarization
succeeded; attach the ticket and verify the distribution before publishing.
For a failed result, retrieve the report with `notarytool log`. Stopping the
monitor or reaching its timeout does not cancel the submission or submit a new
copy. These commands report status rather than a completion estimate.

## Scope and verification

Signing covers the portable setup app and its embedded receiver. Generated destination apps have local configuration and new bundle identities; the generator ad-hoc signs those apps on the destination Mac. They do not inherit the setup app's notarization ticket. The signing private key is never embedded in the setup or destination apps.

Local verification on 2026-09-13 covered script syntax, argument validation, and rejection of a missing identity before building or uploading. On 2026-09-14, a valid individual Developer ID identity signed v1.1.1's setup app and receiver; both signatures, secure timestamps, and Hardened Runtime flags were verified. All 24 tests passed, and the setup GUI still installed an isolated test destination. See [the integration record](integration.md) for notarization and distribution status.
