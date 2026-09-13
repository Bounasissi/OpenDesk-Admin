#!/bin/bash
# Build OpenDesk Admin.app (ad-hoc signed) from the Swift package.
# Usage: ./scripts/build-app.sh [release|debug]
set -euo pipefail

CONFIG="${1:-release}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="OpenDesk Admin"
BUNDLE_ID="org.opendesk.admin"
BUILD_DIR="$REPO_ROOT/.build"
BIN_NAME="opendesk-gui"

if [[ "$CONFIG" == "release" ]]; then
  swift build -c release
  BIN="$BUILD_DIR/release/$BIN_NAME"
else
  swift build
  BIN="$BUILD_DIR/arm64-apple-macosx/debug/$BIN_NAME"
fi

APP="$BUILD_DIR/$APP_NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN" "$APP/Contents/MacOS/$BIN_NAME"

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$BIN_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.3.0</string>
    <key>CFBundleVersion</key>
    <string>3</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>MIT Licensed. Not affiliated with Apple Inc.</string>
</dict>
</plist>
EOF

cat > "$APP/Contents/PkgInfo" <<EOF
APPL????
EOF

codesign --force --sign - "$APP"

echo "Built: $APP"
codesign --verify --verbose=1 "$APP"
echo "Ad-hoc signature verified."
