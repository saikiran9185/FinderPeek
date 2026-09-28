#!/bin/bash
# Build FinderPeek.app and install it to /Applications.
set -euo pipefail
cd "$(dirname "$0")"

APP=FinderPeek.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

swiftc -O FinderPeek.swift -o "$APP/Contents/MacOS/FinderPeek"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>com.saikiran.FinderPeek</string>
  <key>CFBundleName</key><string>FinderPeek</string>
  <key>CFBundleExecutable</key><string>FinderPeek</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
</dict></plist>
PLIST

# Signing with a real identity keeps the Accessibility grant across rebuilds.
IDENTITY=$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/{print $2; exit}')
codesign --force --sign "${IDENTITY:--}" "$APP"

pkill -x FinderPeek || true
rm -rf /Applications/$APP
cp -R "$APP" /Applications/
open /Applications/$APP
echo "Installed /Applications/$APP (signed: ${IDENTITY:-ad-hoc})"
