#!/usr/bin/env bash
set -euo pipefail

APP_NAME="PurePaste"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"
BUILD_BIN="$ROOT_DIR/.build/release/$APP_NAME"
PLIST_PATH="$ROOT_DIR/PurePaste-Info.plist"
ICON_PNG="$ROOT_DIR/assets/icon.png"
BACKGROUND_PNG="$ROOT_DIR/assets/background.png"

ICONSET_DIR="$DIST_DIR/AppIcon.iconset"
ICON_ICNS="$DIST_DIR/AppIcon.icns"
STAGE_DIR="$DIST_DIR/dmg-stage"

FINAL_DMG="$ROOT_DIR/$APP_NAME.dmg"
SIGN_IDENTITY="${SIGN_IDENTITY:-}"

cleanup() {
  rm -rf "$STAGE_DIR" "$ICONSET_DIR"
  rm -f "$ICON_ICNS"
  rm -f "$ROOT_DIR"/rw.*."$APP_NAME".dmg
}

trap cleanup EXIT

if ! command -v create-dmg >/dev/null 2>&1; then
  echo "Error: create-dmg is not installed or not in PATH."
  exit 1
fi

if [[ ! -f "$PLIST_PATH" ]]; then
  echo "Error: missing plist at $PLIST_PATH"
  exit 1
fi

if [[ ! -f "$BACKGROUND_PNG" ]]; then
  echo "Error: missing DMG background at $BACKGROUND_PNG"
  exit 1
fi

mkdir -p "$DIST_DIR"

echo "Building $APP_NAME..."
swift build -c release --package-path "$ROOT_DIR" --product "$APP_NAME"

echo "Assembling app bundle..."
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BUILD_BIN" "$APP_DIR/Contents/MacOS/$APP_NAME"
cp "$PLIST_PATH" "$APP_DIR/Contents/Info.plist"
cp -R "$ROOT_DIR/assets" "$APP_DIR/Contents/Resources/assets"

if [[ -f "$ICON_PNG" ]]; then
  mkdir -p "$ICONSET_DIR"
  sips -z 16 16 "$ICON_PNG" --out "$ICONSET_DIR/icon_16x16.png"
  sips -z 32 32 "$ICON_PNG" --out "$ICONSET_DIR/icon_16x16@2x.png"
  sips -z 32 32 "$ICON_PNG" --out "$ICONSET_DIR/icon_32x32.png"
  sips -z 64 64 "$ICON_PNG" --out "$ICONSET_DIR/icon_32x32@2x.png"
  sips -z 128 128 "$ICON_PNG" --out "$ICONSET_DIR/icon_128x128.png"
  sips -z 256 256 "$ICON_PNG" --out "$ICONSET_DIR/icon_128x128@2x.png"
  sips -z 256 256 "$ICON_PNG" --out "$ICONSET_DIR/icon_256x256.png"
  sips -z 512 512 "$ICON_PNG" --out "$ICONSET_DIR/icon_256x256@2x.png"
  sips -z 512 512 "$ICON_PNG" --out "$ICONSET_DIR/icon_512x512.png"
  cp "$ICON_PNG" "$ICONSET_DIR/icon_512x512@2x.png"
  iconutil -c icns "$ICONSET_DIR" -o "$ICON_ICNS"
  cp "$ICON_ICNS" "$APP_DIR/Contents/Resources/AppIcon.icns"
fi

if [[ -n "$SIGN_IDENTITY" ]]; then
  echo "Signing app with $SIGN_IDENTITY"
  codesign --force --deep --sign "$SIGN_IDENTITY" "$APP_DIR"
fi

echo "Creating DMG staging folder..."
rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR"
cp -R "$APP_DIR" "$STAGE_DIR/"

rm -f "$FINAL_DMG"

echo "Creating polished DMG via create-dmg..."
set +e


ICON_SIZE=128
WINDOW_WIDTH=800
WINDOW_HEIGHT=485

THIRD=$(( WINDOW_WIDTH / 3 ))
CENTER_X=$(( WINDOW_WIDTH / 2 - ICON_SIZE / 2 ))
CENTER_Y=$(( WINDOW_HEIGHT / 2 + ICON_SIZE / 2 ))
ICON_X=$(( CENTER_X - THIRD / 2 - ICON_SIZE / 2 ))
ICON_Y=$(( CENTER_Y - ICON_SIZE / 2 ))
APP_DROP_X=$(( CENTER_X + THIRD  + ICON_SIZE / 2 ))
APP_DROP_Y=$ICON_Y

create-dmg \
  --volname "$APP_NAME" \
  --window-size $WINDOW_WIDTH $WINDOW_HEIGHT \
  --icon-size $ICON_SIZE \
  --icon "$APP_NAME.app" $ICON_X $ICON_Y \
  --hide-extension "$APP_NAME.app" \
  --app-drop-link $APP_DROP_X $APP_DROP_Y \
  --background "$BACKGROUND_PNG" \
  --format UDZO \
  --no-internet-enable \
  "$FINAL_DMG" \
  "$STAGE_DIR"

create_dmg_exit=$?
set -e

if [[ -n "$SIGN_IDENTITY" ]]; then
  echo "Signing DMG with $SIGN_IDENTITY"
  codesign --force --sign "$SIGN_IDENTITY" "$FINAL_DMG"
fi

echo "Built DMG: $FINAL_DMG"
