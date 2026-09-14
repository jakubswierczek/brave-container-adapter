#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Command Line Tools can build AppKit apps but omit Swift Testing.
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
xcrun swift build -c release
mkdir -p dist/bin
build_dir="$(xcrun swift build -c release --show-bin-path)"
# Replace each inode so macOS does not retain an earlier executable's signature cache.
stage="$(mktemp -d "$PWD/dist/.bin.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
for executable in cbc ContainerReceiver; do
  cp "$build_dir/$executable" "$stage/$executable"
  mv -f "$stage/$executable" "dist/bin/$executable"
done
echo 'Built dist/bin/cbc and dist/bin/ContainerReceiver'
