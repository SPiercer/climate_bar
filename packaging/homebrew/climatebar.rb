# Homebrew cask for ClimateBar.
#
# This file belongs in a SEPARATE tap repo: github.com/SPiercer/homebrew-tap
# at Casks/climatebar.rb. Scripts/release.sh fills in version + sha256 for you.
# Users then install with:
#
#   brew install --cask spiercer/tap/climatebar
#
cask "climatebar" do
  version "0.4"
  sha256 "0153a9da21ae998da1b742fac4d11296a9c0198a3e7d6a89665726b7dd42b10a"

  url "https://github.com/SPiercer/climate_bar/releases/download/v#{version}/ClimateBar-#{version}.zip"
  name "ClimateBar"
  desc "Control Midea air conditioners from the macOS menu bar, over the LAN"
  homepage "https://github.com/SPiercer/climate_bar"

  app "ClimateBar.app"

  caveats <<~EOS
    On first connection macOS asks to let ClimateBar "find devices on your local
    network" — click Allow, or it can't reach your ACs. Requires macOS 15+.
  EOS
end
