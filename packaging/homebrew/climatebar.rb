# Homebrew cask for ClimateBar.
#
# This file belongs in a SEPARATE tap repo: github.com/SPiercer/homebrew-tap
# at Casks/climatebar.rb. Scripts/release.sh fills in version + sha256 for you.
# Users then install with:
#
#   brew install --cask spiercer/tap/climatebar
#
cask "climatebar" do
  version "0.1"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"

  url "https://github.com/SPiercer/climate_bar/releases/download/v#{version}/ClimateBar-#{version}.zip"
  name "ClimateBar"
  desc "Control Midea air conditioners from the macOS menu bar, over the LAN"
  homepage "https://github.com/SPiercer/climate_bar"

  app "ClimateBar.app"

  caveats <<~EOS
    ClimateBar is not signed with an Apple Developer ID, so the first time you
    open it macOS will say it "cannot be verified". To open it once:

      • Open your Applications folder, right-click ClimateBar, choose Open, then
        click Open in the dialog.
      • Or: System Settings > Privacy & Security, scroll down, click
        "Open Anyway" next to ClimateBar.

    You only have to do this once. Requires macOS 26 or newer.
  EOS
end
