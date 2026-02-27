#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="URLSafeClipboard"
APP_PATH="$ROOT_DIR/dist/$APP_NAME.app"
DMG_PATH="$ROOT_DIR/dist/$APP_NAME.dmg"
TMP_DMG="$ROOT_DIR/dist/$APP_NAME.tmp.dmg"
MOUNT_POINT="/Volumes/$APP_NAME"
STAGE_DIR="$ROOT_DIR/dist/dmg-root"
BACKGROUND_SRC="$ROOT_DIR/assets/background.tiff"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"

"$ROOT_DIR/scripts/build-app.sh"

rm -rf "$STAGE_DIR" "$TMP_DMG" "$DMG_PATH"
mkdir -p "$STAGE_DIR/.background"

cp -R "$APP_PATH" "$STAGE_DIR/"
ln -s /Applications "$STAGE_DIR/Applications"

if [[ -f "$BACKGROUND_SRC" ]]; then
  cp "$BACKGROUND_SRC" "$STAGE_DIR/.background/background.tiff"
fi

codesign --force --deep --sign "$SIGN_IDENTITY" "$STAGE_DIR/$APP_NAME.app" >/dev/null 2>&1 || true

hdiutil create -srcfolder "$STAGE_DIR" -volname "$APP_NAME" -fs HFS+ -format UDRW "$TMP_DMG" >/dev/null

hdiutil attach "$TMP_DMG" -mountpoint "$MOUNT_POINT" -noverify -noautoopen >/dev/null

if command -v osascript >/dev/null 2>&1; then
  osascript <<APPLE_SCRIPT >/dev/null 2>&1 || true
tell application "Finder"
  tell disk "$APP_NAME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set bounds of container window to {120, 120, 820, 520}
    tell icon view options of container window
      set arrangement to not arranged
      set icon size to 128
      if exists file ".background:background.tiff" then
        set background picture to file ".background:background.tiff"
      end if
    end tell
    set position of item "$APP_NAME.app" to {190, 250}
    set position of item "Applications" to {510, 250}
    close
    open
    update without registering applications
    delay 1
  end tell
end tell
APPLE_SCRIPT
fi

hdiutil detach "$MOUNT_POINT" >/dev/null
hdiutil convert "$TMP_DMG" -format UDZO -o "$DMG_PATH" >/dev/null
rm -f "$TMP_DMG"

codesign --force --sign "$SIGN_IDENTITY" "$DMG_PATH" >/dev/null 2>&1 || true

echo "Built DMG: $DMG_PATH"
