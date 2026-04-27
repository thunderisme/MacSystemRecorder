#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONFIGURATION="${1:-release}"
PRODUCT_DIR="$ROOT_DIR/.build/$CONFIGURATION"
DIST_DIR="$ROOT_DIR/dist/$CONFIGURATION"
APP_DIR="$DIST_DIR/MacSystemRecorder.app"
DMG_ROOT="$DIST_DIR/dmgroot"
DMG_PATH="$DIST_DIR/MacSystemRecorder.dmg"

if [[ ! -d "$APP_DIR" ]]; then
  echo "Missing app bundle at $APP_DIR"
  echo "Run:"
  echo "  swift build -c $CONFIGURATION"
  echo "  ./Scripts/make-app.sh $CONFIGURATION"
  exit 1
fi

rm -rf "$DMG_ROOT"
rm -f "$DMG_PATH"
mkdir -p "$DMG_ROOT"

COPYFILE_DISABLE=1 ditto --norsrc --noextattr --noqtn "$APP_DIR" "$DMG_ROOT/MacSystemRecorder.app"
ln -s /Applications "$DMG_ROOT/Applications"

if command -v xattr >/dev/null 2>&1; then
  xattr -cr "$DMG_ROOT" 2>/dev/null || true
fi

hdiutil create \
  -volname "MacSystemRecorder" \
  -srcfolder "$DMG_ROOT" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

echo "Created $DMG_PATH"
