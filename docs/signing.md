# Developer ID signing

The published v1.1.0 ZIP is ad-hoc signed. A company Apple Developer Program membership can provide Developer ID signing, but membership alone does not install a certificate or grant certificate creation rights.

Apple lists **Account Holder** as the role required to create a Developer ID certificate. Some admins have access to cloud-managed certificates. This script needs a **local Developer ID Application certificate and its private key**; an Apple Development certificate or cloud-only identity does not satisfy it. See [Apple's certificate instructions](https://developer.apple.com/help/account/certificates/create-developer-id-certificates).

## Prepare the signing Mac

1. In Xcode Settings, select Apple Accounts (Accounts in some versions), your Apple ID, then the company team. Open Manage Certificates. If permitted, add **Developer ID Application**. If this option is unavailable, the company's Account Holder must help provision the signing identity. Do not revoke existing certificates.
2. Check locally:

   ```bash
   security find-identity -v -p codesigning
   ```

   Copy the 40-character hash next to the intended `Developer ID Application` identity. The signature will identify the company.
3. Save notarization credentials in Keychain using an interactive Terminal session:

   ```bash
   xcrun notarytool store-credentials cbc-notary
   ```

   Follow the prompts for your Apple ID, the company Team ID, and an app-specific password. Obtain the password through your Apple Account's security settings. Enter it only into the local secure prompt, never in chat or a committed file. A suitable App Store Connect API key is another supported authentication method; see `xcrun notarytool store-credentials --help`.

## Build and notarize

From the checkout on the signing Mac:

```bash
scripts/notarize-setup.sh YOUR_40_CHARACTER_CERTIFICATE_HASH cbc-notary
```

The script verifies the identity and saved credentials before building. It signs the embedded receiver and then the setup app with Hardened Runtime and secure timestamps. It submits the ZIP to Apple, requires an `Accepted` result, staples and validates the ticket, and requires a successful Gatekeeper assessment before making the distribution ZIP. These steps follow [Apple's notarization requirements](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).

Each attempt stays in an ignored `dist/notarization.XXXXXX/` directory. A successful attempt contains `Brave-Container-Setup-notarized.zip` and its SHA-256 file. Failed or timed-out attempts retain `result.json` and the submitted app for diagnosis. A timeout does not cancel Apple's processing. Use the submission ID with `xcrun notarytool info` or `log` and the same Keychain profile before deciding to resubmit. The script does not publish releases or overwrite a previous attempt.

After success, test the ZIP downloaded onto another Mac and publish that exact ZIP/checksum. Confirm that setup opens and can install a destination, then check Choosy routing. A local Gatekeeper assessment alone does not prove a clean download works.

## Scope and verification

Signing covers the portable setup app and its embedded receiver. Generated destination apps have local configuration and new bundle identities; the generator ad-hoc signs those apps on the destination Mac. They do not inherit the setup app's notarization ticket. The signing private key is never embedded in the setup or destination apps.

Local verification on 2026-09-13 covered script syntax, argument validation, and rejection of a missing identity before building or uploading. Developer ID signing, Apple's acceptance, ticket stapling, and the resulting Gatekeeper behavior remain untested because this Mac has no signing identity. The existing ad-hoc release remains unchanged.
