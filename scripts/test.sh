#!/usr/bin/env bash
# Runs the SubtitleCore tests. With only the Command Line Tools installed (no Xcode), SwiftPM does not
# locate the swift-testing macro plugin on its own, so load it explicitly when present.
set -euo pipefail
cd "$(dirname "$0")/.."
PLUGIN="$(xcode-select -p)/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib"
if [[ -f "$PLUGIN" ]]; then
  exec swift test -Xswiftc -load-plugin-library -Xswiftc "$PLUGIN" "$@"
else
  exec swift test "$@"
fi
