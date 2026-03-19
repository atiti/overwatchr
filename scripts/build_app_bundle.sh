#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_CONFIGURATION="${BUILD_CONFIGURATION:-release}"
DIST_DIR="${DIST_DIR:-$ROOT_DIR/dist}"
APP_NAME="Overwatchr.app"
APP_BUNDLE="$DIST_DIR/$APP_NAME"
VERSION="${VERSION:-$(git -C "$ROOT_DIR" describe --tags --always --dirty 2>/dev/null || echo "0.1.0")}"
CREATE_ARCHIVE="${CREATE_ARCHIVE:-1}"

mkdir -p "$DIST_DIR"

if [[ "${SKIP_BUILD:-0}" != "1" ]]; then
  echo "Building overwatchr (${BUILD_CONFIGURATION})..."
  swift build -c "$BUILD_CONFIGURATION" --package-path "$ROOT_DIR"
fi

APP_BINARY="$ROOT_DIR/.build/${BUILD_CONFIGURATION}/overwatchr-app"
CLI_BINARY="$ROOT_DIR/.build/${BUILD_CONFIGURATION}/overwatchr"
ICONSET_SOURCE="$ROOT_DIR/Assets/overwatchr.iconset"
MASTER_ICON="$DIST_DIR/AppIcon-1024.png"
ICONSET_DIR="$(mktemp -d /tmp/overwatchr-icon.XXXXXX).iconset"
mv "${ICONSET_DIR%.iconset}" "$ICONSET_DIR"
trap 'rm -rf "$ICONSET_DIR"' EXIT

if [[ -d "$ICONSET_SOURCE" ]]; then
  cp -R "$ICONSET_SOURCE/" "$ICONSET_DIR/"
else
  swift "$ROOT_DIR/scripts/render_app_icon.swift" --size 1024 --output "$MASTER_ICON"

  for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$MASTER_ICON" --out "$ICONSET_DIR/icon_${size}x${size}.png" >/dev/null
    retina_size=$(( size * 2 ))
    sips -z "$retina_size" "$retina_size" "$MASTER_ICON" --out "$ICONSET_DIR/icon_${size}x${size}@2x.png" >/dev/null
  done
fi

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"

install -m 755 "$APP_BINARY" "$APP_BUNDLE/Contents/MacOS/overwatchr-app"
iconutil -c icns "$ICONSET_DIR" -o "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$APP_BUNDLE/Contents/PkgInfo"

/bin/cat > "$APP_BUNDLE/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDisplayName</key>
  <string>Overwatchr</string>
  <key>CFBundleExecutable</key>
  <string>overwatchr-app</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleIdentifier</key>
  <string>dev.overwatchr.menubar</string>
  <key>CFBundleName</key>
  <string>Overwatchr</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>${VERSION}</string>
  <key>CFBundleVersion</key>
  <string>${VERSION}</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSAppleEventsUsageDescription</key>
  <string>Overwatchr needs Apple Events access to bring the right terminal window to the front.</string>
</dict>
</plist>
EOF

echo "Built app bundle at $APP_BUNDLE"

if [[ "$CREATE_ARCHIVE" == "1" ]]; then
  APP_ARCHIVE="$DIST_DIR/overwatchr-${VERSION}-macos-app.zip"
  CLI_ARCHIVE="$DIST_DIR/overwatchr-${VERSION}-macos-cli.zip"
  rm -f "$APP_ARCHIVE" "$CLI_ARCHIVE"
  ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$APP_ARCHIVE"
  ditto -c -k --keepParent "$CLI_BINARY" "$CLI_ARCHIVE"
  echo "Packaged $APP_ARCHIVE"
  echo "Packaged $CLI_ARCHIVE"
fi
