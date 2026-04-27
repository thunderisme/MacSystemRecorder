#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONFIGURATION="${1:-release}"
VERSION="${VERSION:-0.3.0}"
PRODUCT_DIR="$ROOT_DIR/.build/$CONFIGURATION"
DIST_DIR="$ROOT_DIR/dist/$CONFIGURATION"
APP_DIR="$DIST_DIR/MacSystemRecorder.app"
PKG_PATH="$DIST_DIR/MacSystemRecorder.pkg"

if [[ ! -d "$APP_DIR" ]]; then
  echo "Missing app bundle at $APP_DIR"
  echo "Run:"
  echo "  swift build -c $CONFIGURATION"
  echo "  ./Scripts/make-app.sh $CONFIGURATION"
  exit 1
fi

rm -f "$PKG_PATH"

if command -v xattr >/dev/null 2>&1; then
  xattr -cr "$APP_DIR" 2>/dev/null || true
fi

PKGBUILD_ARGS=(
  --component "$APP_DIR"
  --install-location /Applications
  --identifier com.thunderisme.MacSystemRecorder
  --version "$VERSION"
)

if [[ -n "${INSTALLER_SIGN_IDENTITY:-}" ]]; then
  PKGBUILD_ARGS+=(--sign "$INSTALLER_SIGN_IDENTITY")
fi

pkgbuild "${PKGBUILD_ARGS[@]}" "$PKG_PATH"

echo "Created $PKG_PATH"
