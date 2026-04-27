#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONFIGURATION="${1:-release}"
VERSION="${VERSION:-0.3.0}"
SIGNING_MODE="${SIGNING_MODE:-adhoc}"
PRODUCT_DIR="$ROOT_DIR/.build/$CONFIGURATION"
DIST_DIR="$ROOT_DIR/dist/$CONFIGURATION"
APP_DIR="$DIST_DIR/MacSystemRecorder.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"

if [[ ! -x "$PRODUCT_DIR/MacSystemRecorder" ]]; then
  echo "Missing built binary at $PRODUCT_DIR/MacSystemRecorder"
  echo "Run: swift build -c $CONFIGURATION"
  exit 1
fi

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR"
cp "$PRODUCT_DIR/MacSystemRecorder" "$MACOS_DIR/MacSystemRecorder"

cat > "$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>MacSystemRecorder</string>
  <key>CFBundleIdentifier</key>
  <string>com.thunderisme.MacSystemRecorder</string>
  <key>CFBundleName</key>
  <string>MacSystemRecorder</string>
  <key>CFBundleDisplayName</key>
  <string>Mac System Recorder</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleSignature</key>
  <string>????</string>
  <key>CFBundleShortVersionString</key>
  <string>$VERSION</string>
  <key>CFBundleVersion</key>
  <string>$VERSION</string>
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.video</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

printf 'APPL????' > "$CONTENTS_DIR/PkgInfo"

case "$SIGNING_MODE" in
  identity)
    if [[ -z "${CODESIGN_IDENTITY:-}" ]]; then
      echo "SIGNING_MODE=identity requires CODESIGN_IDENTITY."
      exit 1
    fi
    codesign --force --deep --options runtime --timestamp --sign "$CODESIGN_IDENTITY" "$APP_DIR"
    ;;
  adhoc)
    codesign --force --deep --sign - "$APP_DIR"
    ;;
  unsigned)
    codesign --remove-signature "$MACOS_DIR/MacSystemRecorder" >/dev/null 2>&1 || true
    echo "Created an unsigned bundle. Unsigned arm64 apps may not launch on every Mac."
    ;;
  *)
    echo "Unknown SIGNING_MODE '$SIGNING_MODE'. Use adhoc, identity, or unsigned."
    exit 1
    ;;
esac

echo "Created $APP_DIR"
