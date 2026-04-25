#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_BUNDLE="${APP_BUNDLE:-$ROOT_DIR/dist/LoqBar.app}"
ZIP_PATH="${ZIP_PATH:-$ROOT_DIR/dist/LoqBar.zip}"
KEYCHAIN_PROFILE="${KEYCHAIN_PROFILE:-}"

if [[ -z "$KEYCHAIN_PROFILE" ]]; then
  echo "Set KEYCHAIN_PROFILE to a configured notarytool profile before running this script." >&2
  echo "Example:" >&2
  echo "  KEYCHAIN_PROFILE=LoqBarNotary ./Packaging/notarize-app.sh" >&2
  exit 1
fi

if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "Missing app bundle: $APP_BUNDLE" >&2
  exit 1
fi

if [[ ! -f "$ZIP_PATH" ]]; then
  echo "Missing release ZIP: $ZIP_PATH" >&2
  exit 1
fi

echo "Submitting ZIP for notarization..."
xcrun notarytool submit "$ZIP_PATH" --keychain-profile "$KEYCHAIN_PROFILE" --wait

echo "Stapling notarization ticket..."
xcrun stapler staple "$APP_BUNDLE"

echo "Re-validating stapled app..."
spctl --assess --type execute "$APP_BUNDLE"

echo
echo "Notarization complete:"
echo "  $APP_BUNDLE"
