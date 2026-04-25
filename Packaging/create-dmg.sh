#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="LoqBar"
OUTPUT_ROOT="${OUTPUT_ROOT:-$ROOT_DIR/dist}"
APP_BUNDLE="${APP_BUNDLE:-$OUTPUT_ROOT/$APP_NAME.app}"
DMG_PATH="${DMG_PATH:-$OUTPUT_ROOT/$APP_NAME.dmg}"
DMG_VOLUME_NAME="${DMG_VOLUME_NAME:-LoqBar}"
TEMP_RW_DMG="${OUTPUT_ROOT}/${APP_NAME}-temp.dmg"
MOUNT_ROOT="$(mktemp -d /tmp/loqbar-dmg-mount.XXXXXX)"
STAGING_DIR="$(mktemp -d /tmp/loqbar-dmg-stage.XXXXXX)"
BACKGROUND_IMAGE="${BACKGROUND_IMAGE:-$ROOT_DIR/Packaging/dmg-background.png}"
ENABLE_FINDER_STYLING="${ENABLE_FINDER_STYLING:-1}"
APP_POSITION_X="${APP_POSITION_X:-170}"
APP_POSITION_Y="${APP_POSITION_Y:-220}"
APPLICATIONS_POSITION_X="${APPLICATIONS_POSITION_X:-430}"
APPLICATIONS_POSITION_Y="${APPLICATIONS_POSITION_Y:-220}"
WINDOW_LEFT="${WINDOW_LEFT:-200}"
WINDOW_TOP="${WINDOW_TOP:-120}"
WINDOW_RIGHT="${WINDOW_RIGHT:-760}"
WINDOW_BOTTOM="${WINDOW_BOTTOM:-500}"
VOLUME_MOUNTPOINT="$MOUNT_ROOT/$DMG_VOLUME_NAME"

cleanup() {
  hdiutil detach "$VOLUME_MOUNTPOINT" -quiet >/dev/null 2>&1 || true
  rm -rf "$MOUNT_ROOT"
  rm -rf "$STAGING_DIR"
  rm -f "$TEMP_RW_DMG"
}
trap cleanup EXIT

if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "Missing app bundle: $APP_BUNDLE" >&2
  echo "Run ./Packaging/build-app.sh first." >&2
  exit 1
fi

rm -f "$DMG_PATH"
rm -f "$TEMP_RW_DMG"
mkdir -p "$OUTPUT_ROOT"

cp -R "$APP_BUNDLE" "$STAGING_DIR/$APP_NAME.app"
ln -s /Applications "$STAGING_DIR/Applications"

echo "Creating temporary writable DMG..."
hdiutil create \
  -srcfolder "$STAGING_DIR" \
  "$TEMP_RW_DMG" \
  -volname "$DMG_VOLUME_NAME" \
  -format UDRW \
  -ov >/dev/null

echo "Mounting temporary DMG..."
hdiutil attach "$TEMP_RW_DMG" -mountpoint "$VOLUME_MOUNTPOINT" -nobrowse -quiet

if [[ -f "$BACKGROUND_IMAGE" ]]; then
  mkdir -p "$VOLUME_MOUNTPOINT/.background"
  cp "$BACKGROUND_IMAGE" "$VOLUME_MOUNTPOINT/.background/$(basename "$BACKGROUND_IMAGE")"
fi

if [[ "$ENABLE_FINDER_STYLING" == "1" ]] && command -v osascript >/dev/null 2>&1; then
  echo "Applying Finder layout..."
  BG_NAME=""
  if [[ -f "$BACKGROUND_IMAGE" ]]; then
    BG_NAME="$(basename "$BACKGROUND_IMAGE")"
  fi

  osascript <<EOF || echo "Finder styling skipped."
with timeout of 10 seconds
tell application "Finder"
    tell disk "$DMG_VOLUME_NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set sidebar width of container window to 0
        set the bounds of container window to {$WINDOW_LEFT, $WINDOW_TOP, $WINDOW_RIGHT, $WINDOW_BOTTOM}
        set opts to the icon view options of container window
        set arrangement of opts to not arranged
        set icon size of opts to 128
        set text size of opts to 14
$(if [[ -n "$BG_NAME" ]]; then
cat <<BGEOF
        set background picture of opts to file ".background:$BG_NAME"
BGEOF
fi)
        set position of item "$APP_NAME.app" of container window to {$APP_POSITION_X, $APP_POSITION_Y}
        set position of item "Applications" of container window to {$APPLICATIONS_POSITION_X, $APPLICATIONS_POSITION_Y}
        update without registering applications
        delay 1
        close
        open
        delay 1
    end tell
end tell
end timeout
EOF
fi

sync
hdiutil detach "$VOLUME_MOUNTPOINT" -quiet

echo "Creating DMG..."
hdiutil convert "$TEMP_RW_DMG" \
  -ov \
  -format UDZO \
  -o "$DMG_PATH"

echo
echo "Built DMG:"
echo "  $DMG_PATH"
echo
echo "Next steps:"
echo "  open \"$DMG_PATH\""
echo "  hdiutil verify \"$DMG_PATH\""
