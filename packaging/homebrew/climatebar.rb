# Homebrew cask for ClimateBar.
#
# This file belongs in a SEPARATE tap repo: github.com/SPiercer/homebrew-tap
# at Casks/climatebar.rb. Scripts/release.sh fills in version + sha256 for you.
# Users then install with:
#
#   brew install --cask spiercer/tap/climatebar
#
cask "climatebar" do
  version "0.2"
  sha256 "dea222347094d43a09c0c64f302c294f28beee24bd9c8c0735b2c89db32fa3e1"

  url "https://github.com/SPiercer/climate_bar/releases/download/v#{version}/ClimateBar-#{version}.zip"
  name "ClimateBar"
  desc "Control Midea air conditioners from the macOS menu bar, over the LAN"
  homepage "https://github.com/SPiercer/climate_bar"

  app "ClimateBar.app"

  caveats <<~EOS
    On first connection macOS asks to let ClimateBar "find devices on your local
    network" — click Allow, or it can't reach your ACs. Requires macOS 26+.
  EOS
end
