#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONFIGURATION="${CONFIGURATION:-release}"
DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
BUILD_HOME="${BUILD_HOME:-/tmp/loqbar-packaging-home}"
export DEVELOPER_DIR
export HOME="$BUILD_HOME"
export CLANG_MODULE_CACHE_PATH="$BUILD_HOME/clang-module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$BUILD_HOME/swiftpm-module-cache"
export COPYFILE_DISABLE=1

APP_NAME="LoqBar"
BUNDLE_ID="${BUNDLE_ID:-com.loqbar.app}"
MARKETING_VERSION="${MARKETING_VERSION:-0.1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
SIGNING_IDENTITY="${SIGNING_IDENTITY:--}"
RELEASE_FEED_URL="${RELEASE_FEED_URL:-}"
RELEASE_PAGE_URL="${RELEASE_PAGE_URL:-}"
OUTPUT_ROOT="${OUTPUT_ROOT:-$ROOT_DIR/dist}"
BUILD_ROOT="$ROOT_DIR/.build/apple/$CONFIGURATION"
APP_BUNDLE="$OUTPUT_ROOT/$APP_NAME.app"
ZIP_PATH="$OUTPUT_ROOT/$APP_NAME.zip"

INFO_PLIST_TEMPLATE="$ROOT_DIR/Packaging/LoqBar-Info.plist"
ENTITLEMENTS_FILE="$ROOT_DIR/Packaging/LoqBar.entitlements"
APPICONSET_PATH="$ROOT_DIR/Packaging/LoqBar.appiconset"
ICNS_PATH="$ROOT_DIR/Packaging/LoqBar.icns"

mkdir -p "$OUTPUT_ROOT"
mkdir -p "$BUILD_HOME" "$CLANG_MODULE_CACHE_PATH" "$SWIFTPM_MODULECACHE_OVERRIDE"
rm -rf "$APP_BUNDLE"
rm -f "$ZIP_PATH"

if [[ ! -f "$ICNS_PATH" && -d "$APPICONSET_PATH" ]]; then
  echo "Generating LoqBar.icns from app icon set..."
  TEMP_ICONSET_DIR="$(mktemp -d /tmp/loqbar-iconset.XXXXXX).iconset"
  mkdir -p "$TEMP_ICONSET_DIR"
  cp "$APPICONSET_PATH"/icon_*.png "$TEMP_ICONSET_DIR/"
  iconutil --convert icns "$TEMP_ICONSET_DIR" --output "$ICNS_PATH"
  rm -rf "$TEMP_ICONSET_DIR"
fi

echo "Building $APP_NAME ($CONFIGURATION)..."
swift build -c "$CONFIGURATION" --product "$APP_NAME"

PRODUCT_BINARY="$ROOT_DIR/.build/$CONFIGURATION/$APP_NAME"
if [[ ! -f "$PRODUCT_BINARY" ]]; then
  echo "Expected binary not found at $PRODUCT_BINARY" >&2
  exit 1
fi

mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
cp "$PRODUCT_BINARY" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

INFO_PLIST="$APP_BUNDLE/Contents/Info.plist"
cp "$INFO_PLIST_TEMPLATE" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $MARKETING_VERSION" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Set :LoqBarReleaseFeedURL $RELEASE_FEED_URL" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Set :LoqBarReleasePageURL $RELEASE_PAGE_URL" "$INFO_PLIST"

if [[ -f "$ROOT_DIR/Packaging/LoqBar.icns" ]]; then
  cp "$ROOT_DIR/Packaging/LoqBar.icns" "$APP_BUNDLE/Contents/Resources/LoqBar.icns"
else
  /usr/libexec/PlistBuddy -c "Delete :CFBundleIconFile" "$INFO_PLIST" >/dev/null 2>&1 || true
fi

echo "Codesigning with identity: $SIGNING_IDENTITY"
codesign --force --deep --timestamp=none --entitlements "$ENTITLEMENTS_FILE" --sign "$SIGNING_IDENTITY" "$APP_BUNDLE"

echo "Creating distributable ZIP..."
ditto --norsrc -c -k --keepParent "$APP_BUNDLE" "$ZIP_PATH"

echo
echo "Built app bundle:"
echo "  $APP_BUNDLE"
echo "Built release ZIP:"
echo "  $ZIP_PATH"
echo
echo "Next steps:"
echo "  open \"$APP_BUNDLE\""
echo "  codesign --verify --deep --strict \"$APP_BUNDLE\""
echo "  spctl --assess --type execute \"$APP_BUNDLE\""
echo "  unzip -l \"$ZIP_PATH\""
echo
echo "For distribution signing:"
echo "  SIGNING_IDENTITY=\"Developer ID Application: Your Name (TEAMID)\" ./Packaging/build-app.sh"
