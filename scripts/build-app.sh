#!/bin/bash
# Builds "Comics Reshape.app" (Apple Silicon + Intel) and a shareable zip in dist/.
# Usage: ./scripts/build-app.sh [version]   (version defaults to 1.0)
set -euo pipefail

APP_NAME="Comics Reshape"
EXECUTABLE="ImageInspector"            # product name from Package.swift
BUNDLE_ID="com.autoshi.comics-reshape"
VERSION="${1:-1.0}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"
ZIP="$DIST/$APP_NAME.zip"

cd "$ROOT"

echo "→ Building release binary (arm64 + x86_64)…"
swift build -c release --arch arm64 --arch x86_64
BIN_DIR="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"

echo "→ Assembling $APP_NAME.app…"
rm -rf "$APP" "$ZIP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/$EXECUTABLE" "$APP/Contents/MacOS/$EXECUTABLE"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>                <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>         <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>          <string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key>          <string>$EXECUTABLE</string>
    <key>CFBundlePackageType</key>         <string>APPL</string>
    <key>CFBundleShortVersionString</key>  <string>$VERSION</string>
    <key>CFBundleVersion</key>             <string>$VERSION</string>
    <key>LSMinimumSystemVersion</key>      <string>14.0</string>
    <key>NSHighResolutionCapable</key>     <true/>
    <key>NSPrincipalClass</key>            <string>NSApplication</string>
</dict>
</plist>
PLIST

echo "→ Signing (ad-hoc)…"
codesign --force --deep --sign - "$APP"

echo "→ Zipping…"
ditto -c -k --keepParent "$APP" "$ZIP"

echo
echo "Done:"
echo "  App: $APP"
echo "  Zip: $ZIP  ($(du -h "$ZIP" | cut -f1))"
echo
echo "Your friend should unzip it, then right-click the app → Open → Open the first time"
echo "(or System Settings → Privacy & Security → Open Anyway)."
