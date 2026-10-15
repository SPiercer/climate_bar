#!/bin/sh
# Builds a release binary (Apple Silicon) and wraps it in ClimateBar.app (ad-hoc signed).
set -e
cd "$(dirname "$0")/.."
swift build -c release
APP=build/ClimateBar.app
rm -rf "$APP" && mkdir -p "$APP/Contents/MacOS"
cp "$(swift build -c release --show-bin-path)/ClimateBar" "$APP/Contents/MacOS/"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>ClimateBar</string>
  <key>CFBundleIdentifier</key><string>com.spiercer.climatebar</string>
  <key>CFBundleName</key><string>ClimateBar</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>LSUIElement</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
echo "Built $APP"
