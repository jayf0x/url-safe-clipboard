#!/usr/bin/env bash
set -euo pipefail

APP_NAME="URLSafeClipboard"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_BIN="$ROOT_DIR/.build/release/$APP_NAME"
APP_DIR="$ROOT_DIR/dist/$APP_NAME.app"

swift build -c release --package-path "$ROOT_DIR" --product "$APP_NAME"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

cp "$BUILD_BIN" "$APP_DIR/Contents/MacOS/$APP_NAME"
cp "$ROOT_DIR/URLSafeClipboard-Info.plist" "$APP_DIR/Contents/Info.plist"
cp -R "$ROOT_DIR/assets" "$APP_DIR/Contents/Resources/assets"

codesign --force --deep --sign - "$APP_DIR" >/dev/null 2>&1 || true

echo "Built app bundle: $APP_DIR"
