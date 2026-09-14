#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
xcrun swift build -c release --arch arm64 --arch x86_64
build_dir="$(xcrun swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"
stage="$(mktemp -d "${TMPDIR:-/tmp}/cbc-package.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
app="$stage/Brave Container Setup.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" dist
cp "$build_dir/ContainerSetup" "$app/Contents/MacOS/ContainerSetup"
cp "$build_dir/ContainerReceiver" "$app/Contents/Resources/ContainerReceiver"
strip -S "$app/Contents/MacOS/ContainerSetup"
strip -S "$app/Contents/Resources/ContainerReceiver"
cp README.md "$app/Contents/Resources/README.md"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>app.choosy-brave-containers.setup</string>
<key>CFBundleName</key><string>Brave Container Setup</string>
<key>CFBundleDisplayName</key><string>Brave Container Setup</string>
<key>CFBundleExecutable</key><string>ContainerSetup</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.1.1</string>
<key>CFBundleVersion</key><string>3</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$app/Contents/Resources/ContainerReceiver"
codesign --force --sign - "$app"
codesign --verify --strict "$app"
lipo "$app/Contents/MacOS/ContainerSetup" -verify_arch arm64 x86_64
lipo "$app/Contents/Resources/ContainerReceiver" -verify_arch arm64 x86_64
archive="dist/Brave-Container-Setup-universal.zip"
ditto -c -k --sequesterRsrc --keepParent "$app" "$archive"
(cd dist && shasum -a 256 Brave-Container-Setup-universal.zip > Brave-Container-Setup-universal.zip.sha256)
echo "Packaged $archive (Apple silicon + Intel)"
