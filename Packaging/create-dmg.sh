#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="LoqBar"
OUTPUT_ROOT="${OUTPUT_ROOT:-$ROOT_DIR/dist}"
APP_BUNDLE="${APP_BUNDLE:-$OUTPUT_ROOT/$APP_NAME.app}"
DMG_PATH="${DMG_PATH:-$OUTPUT_ROOT/$APP_NAME.dmg}"
DMG_VOLUME_NAME="${DMG_VOLUME_NAME:-LoqBar}"
STAGING_DIR="$(mktemp -d /tmp/loqbar-dmg.XXXXXX)"

cleanup() {
  rm -rf "$STAGING_DIR"
}
trap cleanup EXIT

if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "Missing app bundle: $APP_BUNDLE" >&2
  echo "Run ./Packaging/build-app.sh first." >&2
  exit 1
fi

rm -f "$DMG_PATH"
mkdir -p "$OUTPUT_ROOT"

cp -R "$APP_BUNDLE" "$STAGING_DIR/$APP_NAME.app"
ln -s /Applications "$STAGING_DIR/Applications"

echo "Creating DMG..."
hdiutil create \
  -volname "$DMG_VOLUME_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

echo
echo "Built DMG:"
echo "  $DMG_PATH"
echo
echo "Next steps:"
echo "  open \"$DMG_PATH\""
echo "  hdiutil verify \"$DMG_PATH\""
