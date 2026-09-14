#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

usage() {
  echo 'Usage: scripts/notarize-setup.sh DEVELOPER_ID_SHA1 NOTARY_KEYCHAIN_PROFILE'
  echo 'Builds, signs, submits to Apple, and staples the setup app and its distribution DMG.'
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

# Keep each attempt separate, including rejected/timed-out submission evidence.
attempt="$(mktemp -d "$PWD/dist/notarization.XXXXXX")"
echo "Signing attempt: $attempt"
scripts/package-setup.sh --app-only "$attempt"
app="$attempt/Brave Container Setup.app"
receiver="$app/Contents/Resources/ContainerReceiver"
codesign --force --sign "$identity" --options runtime --timestamp "$receiver"
codesign --force --sign "$identity" --options runtime --timestamp "$app"
codesign --verify --strict "$receiver"
codesign --verify --strict "$app"
lipo "$app/Contents/MacOS/ContainerSetup" -verify_arch arm64 x86_64
lipo "$receiver" -verify_arch arm64 x86_64
ditto -c -k --sequesterRsrc --keepParent "$app" "$attempt/submission.zip"
submit_and_wait() {
  local file="$1" label="$2" submission_id status
  xcrun notarytool submit "$file" --keychain-profile "$profile" \
    --output-format json > "$attempt/$label-submission.json"
  submission_id="$(plutil -extract id raw -o - "$attempt/$label-submission.json")"
  echo "$label submission: $submission_id"
  if ! xcrun notarytool wait "$submission_id" --keychain-profile "$profile" \
      --timeout 30m --output-format json > "$attempt/$label-result.json"; then
    echo "Waiting failed or timed out. Check submission $submission_id before retrying." >&2
    exit 1
  fi
  status="$(plutil -extract status raw -o - "$attempt/$label-result.json")"
  if [[ "$status" != Accepted ]]; then
    echo "$label was not accepted. Inspect $attempt/$label-result.json; do not distribute this attempt." >&2
    exit 1
  fi
  xcrun notarytool log "$submission_id" --keychain-profile "$profile" "$attempt/$label-log.json"
}
# Staple the inner app before creating the image, so copied apps have an offline ticket.
submit_and_wait "$attempt/submission.zip" app
xcrun stapler staple "$app"
xcrun stapler validate "$app"
codesign --verify --strict "$app"
spctl --assess --type execute --verbose=2 "$app"
image="$attempt/Brave-Container-Adapter.dmg"
scripts/create-dmg.sh "$app" "$image"
# A pre-signing checksum must not be mistaken for a completed release.
rm "$image.sha256"
codesign --sign "$identity" --timestamp "$image"
codesign --verify --strict "$image"
submit_and_wait "$image" dmg
xcrun stapler staple "$image"
xcrun stapler validate "$image"
codesign --verify --strict "$image"
hdiutil verify -quiet "$image"
spctl --assess --type open --context context:primary-signature --verbose=2 "$image"
(cd "$attempt" && shasum -a 256 Brave-Container-Adapter.dmg > Brave-Container-Adapter.dmg.sha256)
echo "Ready for distribution: $image"
