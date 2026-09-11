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
cp "$build_dir/cbc" "$build_dir/ContainerReceiver" dist/bin/
echo 'Built dist/bin/cbc and dist/bin/ContainerReceiver'
