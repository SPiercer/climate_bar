# ClimateBar

Control your Midea air conditioners from the macOS menu bar — entirely over your
local network. After a one-time setup, no cloud connection is used.

ClimateBar speaks the Midea V3 LAN protocol directly (reverse-engineered, ported
from [midea-local](https://github.com/midea-lan/midea-local)): a thermostat dial,
fan control, and on/off, in a SwiftUI menu bar panel.

> **Why local?** Midea's protocol-3 units require a per-device `token`/`key` for
> LAN control. Those are issued by Midea's cloud when you pair the AC in the
> MSmartHome app. ClimateBar fetches them **once** at setup, then talks to the
> ACs only over your LAN — you can even firewall the units off the internet
> afterward.

## Requirements

- macOS 26+ (the panel uses Liquid Glass) with Swift 6.2 toolchain
- Your ACs on the same Wi-Fi/LAN as your Mac, already paired in the MSmartHome app
- Python with the [`midealocal`](https://pypi.org/project/midea-local/) package,
  for the one-time setup (`pipx install midea-local`)

## Install

```sh
brew install --cask spiercer/tap/climatebar
```

ClimateBar isn't signed with an Apple Developer ID, so the **first** time you
open it macOS will say it "cannot be verified". Open it once via right-click →
**Open**, or System Settings → Privacy & Security → **Open Anyway**. After that
it launches normally.

On first launch the app asks you to sign in with your Midea account, finds your
ACs on the LAN, and lists them to confirm — then talks to them only over your
LAN. The cloud is not contacted again.

## Build from source

```sh
./Scripts/bundle.sh        # builds build/ClimateBar.app (ad-hoc signed)
open build/ClimateBar.app
```

To cut a release and update the Homebrew cask, run `./Scripts/release.sh`.

## Command-line tools

For power users, the Python tools reuse the same local protocol and
`devices.json` (run `ac_setup.py` instead of the in-app login to generate it):

| Tool | Does |
|------|------|
| `ac.py list` | Show each AC and its state |
| `ac.py on\|off <ac>` | Power an AC on/off (`<ac>` is a number, IP, or `all`) |
| `ac.py temp 24 <ac>` | Set target temperature |
| `ac_direct.py <ip> on\|off\|26` | Send a single raw command to one AC by IP |

Run them with the Python that has `midealocal` installed.

## Security

`devices.json` and `midea-devices.json` hold per-device tokens and keys — treat
them like passwords. Both are git-ignored and written with `0600` permissions;
never commit them.

## License

Apache License 2.0 — see [LICENSE](LICENSE) and [NOTICE](NOTICE).
