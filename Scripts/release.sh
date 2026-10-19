#!/bin/sh
# Cut a ClimateBar release zip and update the Homebrew cask to match.
#
#   ./Scripts/release.sh [version]     # version defaults to 0.1
#
# Produces build/ClimateBar-<version>.zip, then rewrites the version + sha256
# in packaging/homebrew/climatebar.rb. Steps after that are manual:
#   1. Create a GitHub release tagged v<version> and attach the zip.
#   2. Copy packaging/homebrew/climatebar.rb into the tap repo
#      (github.com/SPiercer/homebrew-tap) at Casks/climatebar.rb and push.
set -e
cd "$(dirname "$0")/.."
VERSION="${1:-0.1}"
CASK="packaging/homebrew/climatebar.rb"

CLIMATEBAR_VERSION="$VERSION" ./Scripts/bundle.sh   # builds + signs build/ClimateBar.app
APP=build/ClimateBar.app

# Notarize when a notary profile is configured (see README); otherwise skip and
# ship the signed-but-unnotarized app. Set up once with:
#   xcrun notarytool store-credentials climatebar \
#     --apple-id <id> --team-id 3DV3M49G95 --password <app-specific-password>
if security find-generic-password -s "com.apple.gke.notary.climatebar" >/dev/null 2>&1 \
   || xcrun notarytool history --keychain-profile climatebar >/dev/null 2>&1; then
  NOTARIZE_ZIP="build/notarize.zip"
  ditto -c -k --keepParent "$APP" "$NOTARIZE_ZIP"
  echo "Submitting to notary service (this can take a few minutes)…"
  xcrun notarytool submit "$NOTARIZE_ZIP" --keychain-profile climatebar --wait
  xcrun stapler staple "$APP"
  rm -f "$NOTARIZE_ZIP"
  echo "Notarized + stapled."
else
  echo "No notary profile 'climatebar' — shipping signed but NOT notarized."
fi

ZIP="build/ClimateBar-$VERSION.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
SHA=$(shasum -a 256 "$ZIP" | cut -d' ' -f1)

# Update the cask in place (BSD sed).
sed -i '' -E "s/^  version \".*\"/  version \"$VERSION\"/" "$CASK"
sed -i '' -E "s/^  sha256 \".*\"/  sha256 \"$SHA\"/" "$CASK"

echo "Built $ZIP"
echo "sha256 $SHA"
echo "Updated $CASK — now make the GitHub release and push the tap."
