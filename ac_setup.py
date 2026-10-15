#!/usr/bin/env python3
"""One-time cloud onboarding for ClimateBar: log in, list ACs, save their keys.

    ~/.local/pipx/venvs/midea-local/bin/python ac_setup.py

Shows a login form (native macOS dialogs), logs into the Midea cloud once to
fetch each AC's LAN token/key, lists the ACs it found on your network as
confirmation, and on "Add" writes them to the file ClimateBar reads:

    ~/Library/Application Support/ClimateBar/devices.json

After this runs the app talks to the ACs only over your LAN; the cloud is never
touched again unless you re-run it (e.g. after a factory reset issues new keys).
"""
import asyncio
import json
import subprocess
import sys
from pathlib import Path

import aiohttp
from midealocal.cloud import get_midea_cloud
from midealocal.device import ProtocolVersion
from midealocal.devices import device_selector
from midealocal.discover import discover

CLOUD = "SmartHome"  # the overseas MSmartHome app these ACs were paired in
DEVICES_FILE = (
    Path.home() / "Library/Application Support/ClimateBar/devices.json"
)


def osa(script: str) -> str:
    """Run one AppleScript, return its stdout; '' if the user cancelled."""
    r = subprocess.run(
        ["osascript", "-e", script], capture_output=True, text=True
    )
    return r.stdout.strip() if r.returncode == 0 else ""


def ask(prompt: str, *, hidden: bool = False) -> str:
    answer = "with hidden answer" if hidden else ""
    out = osa(
        f'text returned of (display dialog "{prompt}" '
        f'default answer "" {answer} buttons {{"Cancel", "OK"}} '
        'default button "OK" with title "ClimateBar setup")'
    )
    if not out:
        sys.exit("Cancelled.")
    return out


def confirm(message: str) -> bool:
    # A non-zero exit (Cancel) means "don't add".
    return bool(
        osa(
            f'button returned of (display dialog "{message}" '
            f'buttons {{"Cancel", "Add"}} default button "Add" '
            'with title "ClimateBar setup")'
        )
        == "Add"
    )


def note(message: str) -> None:
    osa(
        f'display dialog "{message}" buttons {{"OK"}} default button "OK" '
        'with title "ClimateBar setup"'
    )


async def resolve(cloud, device: dict) -> dict | None:
    """Find the token/key that actually connects to this AC, or None.

    V1/V2 ACs need no key; V3 ones get candidate keys from the cloud and we
    keep whichever one authenticates, so a wrong candidate is never saved.
    """
    if device["protocol"] != ProtocolVersion.V3:
        candidates = [{"token": "", "key": ""}]
    else:
        candidates = list((await cloud.get_cloud_keys(device["device_id"])).values())

    for cand in candidates:
        dev = device_selector(
            name=str(device["device_id"]),
            device_id=device["device_id"],
            device_type=device["type"],
            ip_address=device["ip_address"],
            port=device["port"],
            token=cand["token"],
            key=cand["key"],
            device_protocol=device["protocol"],
            model=device["model"],
            subtype=0,
            customize="",
            mac=device["mac"],
            serial_number=device["sn"],
        )
        if dev.connect():  # connect() authenticates V3 with the key
            dev.close_socket()
            return {
                "name": f"AC @ {device['ip_address']}",
                "ip": device["ip_address"],
                "device_id": device["device_id"],
                "token": cand["token"],
                "key": cand["key"],
            }
    return None


async def main() -> None:
    username = ask("Midea account e-mail:")
    password = ask("Password:", hidden=True)

    async with aiohttp.ClientSession() as session:
        cloud = get_midea_cloud(
            cloud_name=CLOUD, session=session, account=username, password=password
        )
        if not await cloud.login():
            note("Cloud login failed. Check the e-mail and password.")
            sys.exit("login failed")

        found = discover()
        if not found:
            note("No ACs found on this network. Same Wi-Fi as the ACs?")
            sys.exit("no devices")

        saved = [d for d in (await resolve(cloud, dev) for dev in found.values()) if d]

    if not saved:
        note("Logged in, but none of the ACs accepted a key from this "
             "account. Sign in with the account that added them in the app.")
        sys.exit("no keys matched")

    listing = "\n".join(f"  • {d['name']}  (id {d['device_id']})" for d in saved)
    if not confirm(f"Found {len(saved)} AC(s):\n\n{listing}\n\nAdd to ClimateBar?"):
        sys.exit("Cancelled.")

    DEVICES_FILE.parent.mkdir(parents=True, exist_ok=True)
    DEVICES_FILE.write_text(json.dumps(saved, indent=2), encoding="utf-8")
    DEVICES_FILE.chmod(0o600)  # token/key are secrets
    note(f"Saved {len(saved)} AC(s) to:\n{DEVICES_FILE}\n\nOpen ClimateBar.")


if __name__ == "__main__":
    asyncio.run(main())
