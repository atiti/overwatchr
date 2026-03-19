#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREFIX="${PREFIX:-/usr/local/bin}"
APP_NAME="Overwatchr.app"
APP_DESTINATION="${APP_DESTINATION:-/Applications}"
INSTALL_APP="${INSTALL_APP:-1}"
BUILD_CONFIGURATION="${BUILD_CONFIGURATION:-release}"
DIST_DIR="${DIST_DIR:-$ROOT_DIR/dist}"

echo "Building overwatchr (${BUILD_CONFIGURATION})..."
cd "$ROOT_DIR"
swift build -c "$BUILD_CONFIGURATION"

CLI_BINARY="$ROOT_DIR/.build/${BUILD_CONFIGURATION}/overwatchr"

mkdir -p "$PREFIX"
install -m 755 "$CLI_BINARY" "$PREFIX/overwatchr"
echo "CLI ready at $PREFIX/overwatchr"

if [[ "$INSTALL_APP" == "1" ]]; then
  BUILD_CONFIGURATION="$BUILD_CONFIGURATION" CREATE_ARCHIVE=0 DIST_DIR="$DIST_DIR" "$ROOT_DIR/scripts/build_app_bundle.sh"

  if [[ ! -w "$APP_DESTINATION" ]]; then
    APP_DESTINATION="$HOME/Applications"
    mkdir -p "$APP_DESTINATION"
  fi

  APP_BUNDLE="$APP_DESTINATION/$APP_NAME"
  rm -rf "$APP_BUNDLE"
  ditto "$DIST_DIR/$APP_NAME" "$APP_BUNDLE"

  echo "Menu bar app ready at $APP_BUNDLE"
fi

echo "Done. Your terminal agents now have a lookout."
