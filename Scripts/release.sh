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

./Scripts/bundle.sh                       # builds build/ClimateBar.app
ZIP="build/ClimateBar-$VERSION.zip"
rm -f "$ZIP"
ditto -c -k --keepParent build/ClimateBar.app "$ZIP"
SHA=$(shasum -a 256 "$ZIP" | cut -d' ' -f1)

# Update the cask in place (BSD sed).
sed -i '' -E "s/^  version \".*\"/  version \"$VERSION\"/" "$CASK"
sed -i '' -E "s/^  sha256 \".*\"/  sha256 \"$SHA\"/" "$CASK"

echo "Built $ZIP"
echo "sha256 $SHA"
echo "Updated $CASK — now make the GitHub release and push the tap."
