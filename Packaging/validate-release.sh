#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_BUNDLE="${APP_BUNDLE:-$ROOT_DIR/dist/LoqBar.app}"
ZIP_PATH="${ZIP_PATH:-$ROOT_DIR/dist/LoqBar.zip}"
MANAGED_EXECUTABLE_IN_BUNDLE="$APP_BUNDLE/Contents/Resources/ManagedTranscription/whisper-cli"

if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "Missing app bundle: $APP_BUNDLE" >&2
  exit 1
fi

if [[ ! -f "$ZIP_PATH" ]]; then
  echo "Missing release ZIP: $ZIP_PATH" >&2
  exit 1
fi

echo "Validating codesign..."
codesign --verify --deep --strict "$APP_BUNDLE"

SIGNATURE_INFO="$(codesign -dvv "$APP_BUNDLE" 2>&1 || true)"
if echo "$SIGNATURE_INFO" | grep -qi "Signature=adhoc"; then
  echo "Gatekeeper assessment skipped for ad-hoc signature."
else
  echo "Assessing with Gatekeeper..."
  spctl --assess --type execute "$APP_BUNDLE"
fi

echo "Inspecting ZIP contents..."
unzip -l "$ZIP_PATH"

if [[ -x "$MANAGED_EXECUTABLE_IN_BUNDLE" ]]; then
  echo "Managed whisper-cli is bundled:"
  echo "  $MANAGED_EXECUTABLE_IN_BUNDLE"
else
  echo "Warning: managed whisper-cli is not bundled in the app."
fi

echo
echo "Validation complete:"
echo "  $APP_BUNDLE"
echo "  $ZIP_PATH"
