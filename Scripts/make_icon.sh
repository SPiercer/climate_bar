#!/bin/sh
# Regenerate packaging/ClimateBar.icns from Scripts/make_icon.swift.
# Only needed when the icon design changes; the .icns is committed.
set -e
cd "$(dirname "$0")/.."
PNG=build/icon-1024.png
mkdir -p build
swift Scripts/make_icon.swift "$PNG"

SET=build/ClimateBar.iconset
rm -rf "$SET" && mkdir -p "$SET"
for s in 16 32 128 256 512; do
  sips -z $s $s       "$PNG" --out "$SET/icon_${s}x${s}.png"    >/dev/null
  sips -z $((s*2)) $((s*2)) "$PNG" --out "$SET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$SET" -o packaging/ClimateBar.icns
rm -rf "$SET"
echo "wrote packaging/ClimateBar.icns"
