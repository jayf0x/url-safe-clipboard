#!/usr/bin/env bash
set -euo pipefail

APP_NAME="URLSafeClipboard"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"
BUILD_BIN="$ROOT_DIR/.build/release/$APP_NAME"
ICON_PNG="$ROOT_DIR/assets/logo.png"
ICONSET_DIR="$DIST_DIR/AppIcon.iconset"
ICON_ICNS="$DIST_DIR/AppIcon.icns"
STAGE_DIR="$DIST_DIR/dmg-root"
TMP_DMG="$DIST_DIR/$APP_NAME.tmp.dmg"
FINAL_DMG="$ROOT_DIR/$APP_NAME.dmg"
MOUNT_POINT="/Volumes/$APP_NAME"
BACKGROUND_SRC="$ROOT_DIR/assets/background.tiff"
GOLDEN_DS_STORE="$ROOT_DIR/assets/golden.DS_Store"
SIGN_IDENTITY="${SIGN_IDENTITY:-}"

cleanup() {
  if mount | grep -q "on $MOUNT_POINT "; then
    hdiutil detach "$MOUNT_POINT" -force || true
  fi
  rm -rf "$STAGE_DIR" "$ICONSET_DIR"
  rm -f "$TMP_DMG" "$ICON_ICNS"
}

trap cleanup EXIT

mkdir -p "$DIST_DIR"

echo "Building app binary..."
swift build -c release --package-path "$ROOT_DIR" --product "$APP_NAME"

echo "Assembling app bundle..."
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BUILD_BIN" "$APP_DIR/Contents/MacOS/$APP_NAME"
cp "$ROOT_DIR/URLSafeClipboard-Info.plist" "$APP_DIR/Contents/Info.plist"
cp -R "$ROOT_DIR/assets" "$APP_DIR/Contents/Resources/assets"

if [[ -f "$ICON_PNG" ]]; then
  echo "Generating app icon from assets/logo.png..."
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
  echo "Signing app bundle with identity: $SIGN_IDENTITY"
  codesign --force --deep --sign "$SIGN_IDENTITY" "$APP_DIR"
fi

echo "Preparing DMG staging directory..."
rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR/.background"
cp -R "$APP_DIR" "$STAGE_DIR/"
ln -s /Applications "$STAGE_DIR/Applications"

if [[ -f "$BACKGROUND_SRC" ]]; then
  cp "$BACKGROUND_SRC" "$STAGE_DIR/.background/background.tiff"
fi

if [[ -f "$GOLDEN_DS_STORE" ]]; then
  cp "$GOLDEN_DS_STORE" "$STAGE_DIR/.DS_Store"
else
  touch "$STAGE_DIR/.DS_Store"
fi

echo "Creating writable DMG..."
rm -f "$TMP_DMG" "$FINAL_DMG"
hdiutil create -srcfolder "$STAGE_DIR" -volname "$APP_NAME" -fs HFS+ -format UDRW "$TMP_DMG"

echo "Applying Finder layout and background..."
hdiutil attach "$TMP_DMG" -mountpoint "$MOUNT_POINT" -noverify -noautoopen
set +e
osascript <<EOF
tell application "Finder"
  tell disk "$APP_NAME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set bounds of container window to {120, 120, 860, 540}
    tell icon view options of container window
      set arrangement to not arranged
      set icon size to 128
      set background picture to file ".background:background.tiff"
    end tell
    set position of item "$APP_NAME.app" to {190, 250}
    set position of item "Applications" to {530, 250}
    update without registering applications
    delay 1
    close
  end tell
end tell
EOF
APPLE_SCRIPT_EXIT=$?
set -e

if [[ $APPLE_SCRIPT_EXIT -ne 0 ]]; then
  echo "Warning: Finder AppleScript layout step failed (likely Automation permission). Continuing with DMG build."
fi

echo "Syncing and detaching volume..."
sync
hdiutil detach "$MOUNT_POINT"

echo "Converting to compressed read-only DMG..."
hdiutil convert "$TMP_DMG" -format UDZO -o "$FINAL_DMG"

if [[ -n "$SIGN_IDENTITY" ]]; then
  echo "Signing DMG with identity: $SIGN_IDENTITY"
  codesign --force --sign "$SIGN_IDENTITY" "$FINAL_DMG"
fi

echo "Built DMG: $FINAL_DMG"
