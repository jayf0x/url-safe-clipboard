#!/usr/bin/env bash
set -euo pipefail

APP_NAME="URLSafeClipboard"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_BIN="$ROOT_DIR/.build/release/$APP_NAME"
APP_DIR="$ROOT_DIR/dist/$APP_NAME.app"
ICON_PNG="$ROOT_DIR/assets/logo.png"
ICONSET_DIR="$ROOT_DIR/dist/AppIcon.iconset"
ICON_ICNS="$ROOT_DIR/dist/AppIcon.icns"

swift build -c release --package-path "$ROOT_DIR" --product "$APP_NAME"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

cp "$BUILD_BIN" "$APP_DIR/Contents/MacOS/$APP_NAME"
cp "$ROOT_DIR/URLSafeClipboard-Info.plist" "$APP_DIR/Contents/Info.plist"
cp -R "$ROOT_DIR/assets" "$APP_DIR/Contents/Resources/assets"

if [[ -f "$ICON_PNG" ]]; then
  rm -rf "$ICONSET_DIR" "$ICON_ICNS"
  mkdir -p "$ICONSET_DIR"

  sips -z 16 16     "$ICON_PNG" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null
  sips -z 32 32     "$ICON_PNG" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null
  sips -z 32 32     "$ICON_PNG" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null
  sips -z 64 64     "$ICON_PNG" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null
  sips -z 128 128   "$ICON_PNG" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null
  sips -z 256 256   "$ICON_PNG" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
  sips -z 256 256   "$ICON_PNG" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null
  sips -z 512 512   "$ICON_PNG" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
  sips -z 512 512   "$ICON_PNG" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null
  cp "$ICON_PNG" "$ICONSET_DIR/icon_512x512@2x.png"

  iconutil -c icns "$ICONSET_DIR" -o "$ICON_ICNS"
  cp "$ICON_ICNS" "$APP_DIR/Contents/Resources/AppIcon.icns"
fi

codesign --force --deep --sign - "$APP_DIR" >/dev/null 2>&1 || true

echo "Built app bundle: $APP_DIR"
