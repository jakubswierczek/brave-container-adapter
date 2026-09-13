#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

usage() {
  echo 'Usage: scripts/notarize-setup.sh DEVELOPER_ID_SHA1 NOTARY_KEYCHAIN_PROFILE'
  echo 'Builds, signs, submits to Apple, and staples the portable setup app.'
  echo 'The certificate and its private key must already be in Keychain.'
}
if [[ "${1:-}" == --help ]]; then usage; exit 0; fi
if [[ $# != 2 || ! "$1" =~ ^[[:xdigit:]]{40}$ || -z "$2" ]]; then
  usage >&2; exit 2
fi
identity="$(printf '%s' "$1" | tr '[:lower:]' '[:upper:]')"
profile="$2"
if ! security find-identity -v -p codesigning | grep -E "[[:space:]]$identity \"Developer ID Application: " > /dev/null; then
  echo 'No matching valid Developer ID Application identity. Install the certificate and private key first.' >&2
  exit 1
fi
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
# Verify saved credentials before building or uploading anything.
xcrun notarytool history --keychain-profile "$profile" --output-format json > /dev/null
scripts/package-setup.sh

# Keep each attempt separate, including rejected/timed-out submission evidence.
attempt="$(mktemp -d "$PWD/dist/notarization.XXXXXX")"
echo "Signing attempt: $attempt"
ditto -x -k dist/Brave-Container-Setup-universal.zip "$attempt"
app="$attempt/Brave Container Setup.app"
receiver="$app/Contents/Resources/ContainerReceiver"
codesign --force --sign "$identity" --options runtime --timestamp "$receiver"
codesign --force --sign "$identity" --options runtime --timestamp "$app"
codesign --verify --strict "$receiver"
codesign --verify --strict "$app"
lipo "$app/Contents/MacOS/ContainerSetup" -verify_arch arm64 x86_64
lipo "$receiver" -verify_arch arm64 x86_64
ditto -c -k --sequesterRsrc --keepParent "$app" "$attempt/submission.zip"
if ! xcrun notarytool submit "$attempt/submission.zip" --keychain-profile "$profile" \
    --wait --timeout 30m --output-format json > "$attempt/result.json"; then
  echo "Submission failed or timed out. Inspect $attempt/result.json; no distribution ZIP was produced." >&2
  exit 1
fi
status="$(plutil -extract status raw -o - "$attempt/result.json")"
if [[ "$status" != Accepted ]]; then
  echo "Notarization was not accepted. Inspect $attempt/result.json; no distribution ZIP was produced." >&2
  exit 1
fi
xcrun stapler staple "$app"
xcrun stapler validate "$app"
codesign --verify --strict "$app"
spctl --assess --type execute --verbose=2 "$app"
archive=Brave-Container-Setup-notarized.zip
ditto -c -k --sequesterRsrc --keepParent "$app" "$attempt/$archive"
(cd "$attempt" && shasum -a 256 "$archive" > "$archive.sha256")
echo "Signed, notarized, and assessed: $attempt/$archive"
