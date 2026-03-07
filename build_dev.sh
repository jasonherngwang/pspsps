#!/bin/bash
set -e

echo "Building Debug version..."
xcodebuild -project pspsps.xcodeproj -scheme pspsps -configuration Debug -destination 'platform=macOS' build | tail -10 || true

echo "Extracting app path..."
APP_PATH=$(xcodebuild -project pspsps.xcodeproj -scheme pspsps -configuration Debug -destination 'platform=macOS' -showBuildSettings | grep " BUILD_DIR =" | awk -F'=' '{print $2}' | tr -d ' ')/Debug/pspsps.app

echo "Killing existing pspsps..."
pkill -x pspsps || true

echo "Opening $APP_PATH ..."
open "$APP_PATH"
