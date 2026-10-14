#!/usr/bin/env python3
"""Control your Midea ACs locally. No IP, token or key to type.

`midealocal discover` already worked for you and saved each AC's token/key in
a file called midea-devices.json, in the folder you ran it from. This script
finds the ACs on your network and reuses that file.

Usage (run from the SAME folder that contains midea-devices.json, or pass
--cache /path/to/midea-devices.json):

    python ac.py list                 # show both ACs and their state
    python ac.py on 1                 # turn AC #1 on
    python ac.py off 2                # turn AC #2 off
    python ac.py temp 24 1            # set AC #1 to 24 C
    python ac.py temp 24 all          # set every AC to 24 C

The number is the AC's position in `list` (1, 2, ...), its IP, or "all".
Run it with the Python that has midea-local installed (the pipx venv).
"""
import argparse
import json
import sys
import time
from pathlib import Path

from midealocal.devices import device_selector
from midealocal.discover import discover

SHOW = [
    "power", "mode", "target_temperature", "indoor_temperature",
    "fan_speed", "swing_vertical", "swing_horizontal", "eco_mode",
    "sleep_mode", "error_code",
]


def load_cache(path: Path) -> dict:
    if not path.exists():
        sys.exit(
            f"Can't find {path}. Run this from the folder where you ran "
            "`midealocal discover`, or pass --cache <path>."
        )
    data = json.loads(path.read_text(encoding="utf-8"))
    return {str(e["device_id"]): e for e in data.get("devices", [])}


def connect_all(cache: dict) -> list:
    found = discover()
    if not found:
        sys.exit("No ACs found on the network. Same Wi-Fi? Router client isolation off?")
    devices = []
    for info in sorted(found.values(), key=lambda d: d["ip_address"]):
        entry = cache.get(str(info["device_id"]))
        if entry is None:
            print(f"Skipping {info['ip_address']}: no cached key. "
                  "Re-run `midealocal discover` first.")
            continue
        dev = device_selector(
            name=str(info["device_id"]),
            device_id=info["device_id"],
            device_type=info["type"],
            ip_address=info["ip_address"],
            port=info["port"],
            token=entry["token"],
            key=entry["key"],
            device_protocol=info["protocol"],
            model=info["model"],
            subtype=0,
            customize="",
            mac=info["mac"],
            serial_number=info["sn"],
        )
        if not dev.connect():
            print(f"Could not connect to {info['ip_address']} "
                  "(close the SmartHome app and retry).")
            continue
        dev.refresh_status(True)
        devices.append((info["ip_address"], dev))
    if not devices:
        sys.exit("No ACs could be reached.")
    return devices


def show(devices: list) -> None:
    for i, (ip, dev) in enumerate(devices, 1):
        dev.refresh_status()
        print(f"--- AC {i}  ({ip})")
        for k in SHOW:
            print(f"  {k}: {dev.attributes.get(k)}")


def pick(devices: list, target: str) -> list:
    if target == "all":
        return devices
    if target.isdigit() and 1 <= int(target) <= len(devices):
        return [devices[int(target) - 1]]
    chosen = [d for d in devices if d[0] == target]
    if not chosen:
        sys.exit(f"No AC matches '{target}'. Use 1..{len(devices)}, an IP, or all.")
    return chosen


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--cache", default="midea-devices.json")
    p.add_argument("action", choices=["list", "on", "off", "temp"])
    p.add_argument("args", nargs="*", help="temp: <degrees> <ac>; on/off: <ac>")
    a = p.parse_args()

    devices = connect_all(load_cache(Path(a.cache)))

    if a.action == "list":
        show(devices)
        return 0

    if a.action == "temp":
        if len(a.args) != 2:
            sys.exit("Usage: temp <degrees> <ac number|ip|all>")
        value, target = float(a.args[0]), a.args[1]
        chosen = pick(devices, target)
        for _, dev in chosen:
            dev.set_attribute("target_temperature", value)
    else:
        if len(a.args) != 1:
            sys.exit(f"Usage: {a.action} <ac number|ip|all>")
        chosen = pick(devices, a.args[0])
        for _, dev in chosen:
            dev.set_attribute("power", a.action == "on")

    time.sleep(3)
    show(chosen)
    for _, dev in devices:
        dev.close_socket()
    return 0


if __name__ == "__main__":
    sys.exit(main())
