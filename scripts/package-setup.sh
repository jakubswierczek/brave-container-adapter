#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "${1:-}" == --help ]]; then
  echo 'Usage: scripts/package-setup.sh [--app-only OUTPUT_DIRECTORY]'
  echo 'Builds a universal local DMG, or stages the app for release signing.'
  exit 0
fi
if [[ $# != 0 && ( $# != 2 || "${1:-}" != --app-only ) ]]; then
  echo 'Usage: scripts/package-setup.sh [--app-only OUTPUT_DIRECTORY]' >&2; exit 2
fi
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
xcrun swift build -c release --arch arm64 --arch x86_64
build_dir="$(xcrun swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"
read -r version build_number <<< "$("$build_dir/cbc" version)"
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ || ! "$build_number" =~ ^[0-9]+$ ]]; then
  echo 'Invalid release version from cbc.' >&2; exit 1
fi
stage="$(mktemp -d "${TMPDIR:-/tmp}/cbc-package.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
app="$stage/Brave Container Setup.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" dist
cp "$build_dir/ContainerSetup" "$app/Contents/MacOS/ContainerSetup"
cp "$build_dir/ContainerReceiver" "$app/Contents/Resources/ContainerReceiver"
strip -S "$app/Contents/MacOS/ContainerSetup"
strip -S "$app/Contents/Resources/ContainerReceiver"
cp README.md "$app/Contents/Resources/README.md"
cp AGENTS.md CONTRIBUTING.md SECURITY.md "$app/Contents/Resources/"
cp -R docs "$app/Contents/Resources/docs"
scripts/build-info.py "$app/Contents/Resources/build-info.json"
if [[ -f LICENSE ]]; then cp LICENSE "$app/Contents/Resources/"; fi
mkdir -p "$app/Contents/Resources/assets"
cp assets/*.md "$app/Contents/Resources/assets/"
iconset="$stage/SetupIcon.iconset"
mkdir -p "$iconset"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" assets/SetupIcon.png --out "$iconset/icon_${size}x${size}.png" >/dev/null
  pixels=$((size * 2))
  sips -z "$pixels" "$pixels" assets/SetupIcon.png --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o "$app/Contents/Resources/SetupIcon.icns"
cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>app.choosy-brave-containers.setup</string>
<key>CFBundleName</key><string>Brave Container Setup</string>
<key>CFBundleDisplayName</key><string>Brave Container Setup</string>
<key>CFBundleExecutable</key><string>ContainerSetup</string>
<key>CFBundleIconFile</key><string>SetupIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$version</string>
<key>CFBundleVersion</key><string>$build_number</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$app/Contents/Resources/ContainerReceiver"
codesign --force --sign - "$app"
codesign --verify --strict "$app"
lipo "$app/Contents/MacOS/ContainerSetup" -verify_arch arm64 x86_64
lipo "$app/Contents/Resources/ContainerReceiver" -verify_arch arm64 x86_64
if [[ $# == 2 ]]; then
  mkdir -p "$2"
  target="$2/Brave Container Setup.app"
  if [[ -e "$target" || -L "$target" ]]; then
    echo 'App output already exists; choose an empty signing directory.' >&2; exit 1
  fi
  ditto "$app" "$target"
  echo "Staged $target"
else
  scripts/create-dmg.sh "$app" "$PWD/dist/Brave-Container-Adapter.dmg"
fi
