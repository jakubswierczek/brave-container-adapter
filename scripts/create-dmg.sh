#!/bin/bash
set -euo pipefail
if [[ ${1:-} == --help ]]; then
  echo 'Usage: scripts/create-dmg.sh SETUP_APP OUTPUT.dmg'; exit 0
fi
if [[ $# != 2 || "$2" != *.dmg ]]; then
  echo 'Usage: scripts/create-dmg.sh SETUP_APP OUTPUT.dmg' >&2; exit 2
fi
app="$1"
output="$2"
if [[ -L "$app" || ! -d "$app" || -d "$output" || -L "$output" ]]; then
  echo 'Choose a setup app and a regular DMG output path.' >&2; exit 1
fi
identifier="$(plutil -extract CFBundleIdentifier raw -o - "$app/Contents/Info.plist")"
if [[ "$identifier" != app.choosy-brave-containers.setup ]]; then
  echo 'The input is not a Brave Container Setup app.' >&2; exit 1
fi
codesign --verify --strict "$app"
mkdir -p "$(dirname "$output")"
stage="$(mktemp -d "$(dirname "$output")/.dmg.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
mkdir "$stage/payload"
ditto "$app" "$stage/payload/Brave Container Setup.app"
ln -s /Applications "$stage/payload/Applications"
cat > "$stage/payload/Read Me.txt" <<'TEXT'
Brave Container Adapter

1. Drag Brave Container Setup to Applications.
2. Eject this disk image, then open Brave Container Setup from Applications.
3. Enable Containers in Brave. Select a destination, name and icon in Setup.
4. Click Install destination. Add the generated app to your browser switcher.

Generate destinations on each Mac; do not copy configured destination apps.
Setup requires macOS 14 or later. It includes Apple silicon and Intel binaries.

Instructions: https://github.com/jakubswierczek/brave-container-adapter
TEXT
hdiutil create -quiet -volname 'Brave Container Adapter' -srcfolder "$stage/payload" \
  -fs HFS+ -format UDZO "$stage/image.dmg"
hdiutil verify -quiet "$stage/image.dmg"
mv -f "$stage/image.dmg" "$output"
(cd "$(dirname "$output")" && shasum -a 256 "$(basename "$output")" > "$(basename "$output").sha256")
echo "Created $output"
