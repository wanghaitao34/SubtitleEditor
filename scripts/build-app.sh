#!/usr/bin/env bash
# Builds a release binary and wraps it in build/SubtitleEditor.app.
#
# Usage:
#   ./scripts/build-app.sh
#       Ad-hoc signed build for local use.
#   ./scripts/build-app.sh --identity "Developer ID Application: Name (TEAMID)" \
#                          --notary-profile <notarytool-keychain-profile>
#       Developer ID signing (hardened runtime + timestamp), notarization,
#       stapling and verification. Produces build/SubtitleEditor.zip.
#       Credentials live in the keychain profile created with
#       `xcrun notarytool store-credentials`; no passwords are passed here.
set -euo pipefail
cd "$(dirname "$0")/.."

IDENTITY=""
NOTARY_PROFILE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --identity) IDENTITY="$2"; shift 2 ;;
    --notary-profile) NOTARY_PROFILE="$2"; shift 2 ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done
if [[ -n "$NOTARY_PROFILE" && -z "$IDENTITY" ]]; then
  echo "--notary-profile requires --identity" >&2; exit 2
fi

APP_NAME="SubtitleEditor"
DISPLAY_NAME="字幕编辑器"
APP="build/${APP_NAME}.app"
ZIP="build/${APP_NAME}.zip"

swift build -c release --product "$APP_NAME"
BIN="$(swift build -c release --show-bin-path)/$APP_NAME"

rm -rf "$APP" "$ZIP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"

# SwiftPM records the deployment target as the SDK version (e.g. 14.0), which makes
# macOS 26+ treat the app as legacy (old flat window controls, no Liquid Glass).
# If the recorded SDK is older than the current one, stamp the real SDK version
# while keeping minos unchanged.
EXE="$APP/Contents/MacOS/$APP_NAME"
SDK_VERSION="$(xcrun --show-sdk-version)"
BUILD_INFO="$(vtool -show-build "$EXE")"
MINOS="$(awk '$1=="minos"{print $2; exit}' <<<"$BUILD_INFO")"
BIN_SDK="$(awk '$1=="sdk"{print $2; exit}' <<<"$BUILD_INFO")"
if [[ "$(printf '%s\n%s\n' "$BIN_SDK" "$SDK_VERSION" | sort -V | head -1)" != "$SDK_VERSION" ]]; then
  echo "Updating build version: minos $MINOS, sdk $BIN_SDK -> $SDK_VERSION"
  vtool -set-build-version macos "$MINOS" "$SDK_VERSION" -replace -output "$EXE" "$EXE"
fi
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>${DISPLAY_NAME}</string>
  <key>CFBundleDisplayName</key><string>${DISPLAY_NAME}</string>
  <key>CFBundleIdentifier</key><string>local.subtitle-editor</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleExecutable</key><string>${APP_NAME}</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>CFBundleDevelopmentRegion</key><string>zh_CN</string>
  <key>CFBundleDocumentTypes</key>
  <array>
    <dict>
      <key>CFBundleTypeName</key><string>Subtitle</string>
      <key>CFBundleTypeRole</key><string>Editor</string>
      <key>LSHandlerRank</key><string>Alternate</string>
      <key>CFBundleTypeExtensions</key><array><string>srt</string><string>vtt</string></array>
    </dict>
    <dict>
      <key>CFBundleTypeName</key><string>Video</string>
      <key>CFBundleTypeRole</key><string>Viewer</string>
      <key>LSHandlerRank</key><string>Alternate</string>
      <key>CFBundleTypeExtensions</key><array><string>mp4</string><string>mov</string><string>m4v</string></array>
    </dict>
  </array>
</dict>
</plist>
PLIST

if [[ -z "$IDENTITY" ]]; then
  codesign --force --sign - "$APP" >/dev/null
  echo "Built $APP (ad-hoc signed)"
  exit 0
fi

# Developer ID signing: nested code first (deepest paths first), then the app.
sign() {
  codesign --force --options runtime --timestamp --sign "$IDENTITY" "$1"
}
while IFS= read -r item; do
  sign "$item"
done < <(find "$APP/Contents" -mindepth 1 \
           \( -name "*.framework" -o -name "*.bundle" -o -name "*.xpc" -o -name "*.appex" \
              -o -name "*.app" -o -name "*.dylib" -o -name "*.so" \
              -o \( -type f -perm -u+x ! -path "$EXE" \) \) -print \
         | awk '{ print length($0) "\t" $0 }' | sort -rn | cut -f2-)
sign "$EXE"
sign "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
echo "Signed $APP with: $IDENTITY"

if [[ -z "$NOTARY_PROFILE" ]]; then
  ditto -c -k --keepParent "$APP" "$ZIP"
  echo "Built $ZIP (signed, not notarized)"
  exit 0
fi

ditto -c -k --keepParent "$APP" "$ZIP"
echo "Submitting $ZIP for notarization..."
RESULT="$(xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait --output-format json)"
echo "$RESULT"
SUBMISSION_ID="$(plutil -extract id raw -o - - <<<"$RESULT")"
STATUS="$(plutil -extract status raw -o - - <<<"$RESULT")"
if [[ "$STATUS" != "Accepted" ]]; then
  echo "Notarization failed ($STATUS). Log:" >&2
  xcrun notarytool log "$SUBMISSION_ID" --keychain-profile "$NOTARY_PROFILE" >&2 || true
  exit 1
fi

xcrun stapler staple "$APP"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

codesign --verify --deep --strict --verbose=2 "$APP"
spctl -a -vvv -t execute "$APP"
xcrun stapler validate "$APP"
echo "Built $ZIP (Developer ID signed, notarized, stapled)"
