#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_PATH="$ROOT_DIR/WeatherIslandXcode/WeatherIsland.xcodeproj"
SCHEME_NAME="WeatherIsland"
CONFIGURATION="${CONFIGURATION:-Release}"
DERIVED_DATA_PATH="$ROOT_DIR/dist-build/DerivedData"
APP_NAME="WeatherIsland.app"
APP_PATH="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/$APP_NAME"

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "xcodebuild not found. Please install Xcode and select it as the active developer directory." >&2
  exit 1
fi

if [ ! -d "$PROJECT_PATH" ]; then
  echo "Project not found at: $PROJECT_PATH" >&2
  exit 1
fi

rm -rf "$ROOT_DIR/dist-build"

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

echo "Built app bundle at: $APP_PATH"
