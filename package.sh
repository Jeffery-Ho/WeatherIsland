#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_PATH="$ROOT_DIR/WeatherIslandXcode/WeatherIsland.xcodeproj"
SCHEME_NAME="WeatherIsland"
CONFIGURATION="${CONFIGURATION:-Release}"
DERIVED_DATA_PATH="$ROOT_DIR/dist-dmg/DerivedData"
STAGING_DIR="$ROOT_DIR/dist-dmg/staging"
DMG_PATH="$ROOT_DIR/dist-dmg/WeatherIsland-macOS.dmg"
APP_NAME="WeatherIsland.app"
APP_PATH="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/$APP_NAME"
README_PATH="$ROOT_DIR/dist-dmg/README-install.txt"

echo "==> Root: $ROOT_DIR"
echo "==> Configuration: $CONFIGURATION"

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "xcodebuild not found. Please install Xcode and Command Line Tools." >&2
  exit 1
fi

if ! command -v hdiutil >/dev/null 2>&1; then
  echo "hdiutil not found. This script must run on macOS." >&2
  exit 1
fi

if [ ! -d "$PROJECT_PATH" ]; then
  echo "Project not found at: $PROJECT_PATH" >&2
  exit 1
fi

if [ ! -f "$README_PATH" ]; then
  echo "Missing DMG install guide: $README_PATH" >&2
  exit 1
fi

echo "==> Cleaning previous DMG staging"
rm -rf "$STAGING_DIR"
rm -f "$DMG_PATH"

echo "==> Building macOS app"
xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME_NAME" \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  -destination 'platform=macOS' \
  build

if [ ! -d "$APP_PATH" ]; then
  echo "Build succeeded but app bundle was not found at: $APP_PATH" >&2
  exit 1
fi

echo "==> Preparing DMG staging"
mkdir -p "$STAGING_DIR"
cp -R "$APP_PATH" "$STAGING_DIR/$APP_NAME"
cp "$README_PATH" "$STAGING_DIR/README-install.txt"
ln -s /Applications "$STAGING_DIR/Applications"

echo "==> Creating DMG"
hdiutil create \
  -volname "WeatherIsland" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

echo
echo "Build complete."
echo "App: $APP_PATH"
echo "DMG: $DMG_PATH"
