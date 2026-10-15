#!/usr/bin/env python3
"""Turn a Midea AC on/off with hand-built protocol frames (no device classes).

    ~/.local/pipx/venvs/midea-local/bin/python ac_direct.py 192.168.1.101 on|off|26

Layers: TCP 6444 -> 8370 (handshake + AES-CBC) -> 5A5A (AES-ECB) -> AA frame.
Only midealocal's crypto/packet helpers are reused; the AA frames are built here.
"""
import json
import socket
import sys

from midealocal.crc8 import calculate as crc8
from midealocal.packet_builder import PacketBuilder
from midealocal.security import LocalSecurity

msg_id = 0


def aa_frame(frame_type: int, body: list[int], version: int = 0) -> bytes:
    global msg_id
    msg_id = msg_id % 253 + 1
    body = body + [msg_id]
    body.append(crc8(bytearray(body)))
    frame = [0xAA, 10 + len(body), 0xAC, 0, 0, 0, 0, 0, version, frame_type] + body
    frame.append((256 - sum(frame[1:]) % 256) % 256)
    return bytes(frame)


def query() -> bytes:
    return aa_frame(0x03, [0x41, 0x81, 0x00, 0xFF] + [0] * 16)


def set_state(c0: bytes, version: int, on: bool | None = None, temp: float | None = None) -> bytes:
    """0x40 set body, carrying the current state over from the C0 status body."""
    b = c0
    on = bool(b[1] & 0x01) if on is None else on
    temp_bits = b[2] & 0x1F if temp is None else (int(temp) & 0x0F) | (0x10 if temp % 1 else 0)
    payload = [0] * 22
    payload[0] = (0x01 if on else 0) | 0x40         # power | beep
    payload[1] = (b[2] & 0xE0) | temp_bits            # mode<<5 | temp-16 | half-degree
    payload[2] = b[3] & 0x7F                          # fan speed
    payload[6] = 0x30 | (b[7] & 0x0F)                 # swing
    payload[7] = b[8] & 0x28                          # boost, power saving
    payload[8] = (b[9] & 0x2C) | (0x80 if b[9] & 0x10 else 0) | (0x01 if b[8] & 0x40 else 0)  # dry/aux/anion, eco, smart eye
    payload[9] = b[10] & 0x07                         # sleep, boost, fahrenheit
    payload[16] = 0x40 if b[9] & 0x02 else 0          # natural wind
    payload[20] = b[21] & 0x80 if len(b) > 21 else 0  # frost protect
    payload[21] = b[22] & 0x01 if len(b) > 22 else 0  # comfort
    return aa_frame(0x02, [0x40] + payload, version)


class Session:
    def __init__(self, ip: str, device_id: int, token: str, key: str):
        self.sec, self.device_id, self.buf = LocalSecurity(), device_id, b""
        self.sock = socket.create_connection((ip, 6444), timeout=5)
        self.sock.send(self.sec.encode_8370(bytes.fromhex(token), 0x0))
        reply = self.sock.recv(512)
        if len(reply) < 72:
            raise ConnectionError(f"handshake rejected: {reply!r}")
        self.sec.tcp_key(reply[8:72], bytes.fromhex(key))  # raises on wrong token/key

    def send(self, frame: bytes) -> None:
        packet = PacketBuilder(self.device_id, frame).finalize()
        print(f"  -> AA {frame.hex(' ')}")
        self.sock.send(self.sec.encode_8370(packet, 0x6))

    def read_status(self) -> bytes:
        """Next AA frame carrying a C0 status body (skips heartbeats)."""
        while True:
            packets, self.buf = self.sec.decode_8370(self.buf + self.sock.recv(1024))
            for p in packets:
                if len(p) <= 56 or p == b"ERROR":
                    continue
                frame = bytes(self.sec.aes_decrypt(p[40:-16]))
                if frame[:1] == b"\xaa" and frame[10] == 0xC0:
                    print(f"  <- AA {frame.hex(' ')}")
                    return frame


def connect(ip: str) -> Session:
    # The token only authenticates against its own AC, so try each cached one.
    for entry in json.load(open("midea-devices.json"))["devices"]:
        try:
            return Session(ip, int(entry["device_id"]), entry["token"], entry["key"])
        except Exception as e:  # noqa: BLE001
            print(f"  {entry['device_id']}: {e}")
    sys.exit(f"no cached token works for {ip}")


def main() -> None:
    ip, action = sys.argv[1], sys.argv[2]
    change = {"on": {"on": True}, "off": {"on": False}}.get(action)
    if change is None:
        temp = float(action)
        if not 16 <= temp <= 30 or temp * 2 % 1:
            sys.exit("temp must be 16-30 in 0.5 steps")
        change = {"temp": temp}
    s = connect(ip)
    print(f"authenticated as {s.device_id}; querying")
    s.send(query())
    status = s.read_status()
    show = lambda f: f"power={bool(f[11] & 1)} target={(f[12] & 0x0F) + 16 + (0.5 if f[12] & 0x10 else 0)}"
    print(f"before: {show(status)}; sending {change}")
    s.send(set_state(status[10:-1], status[8], **change))
    print(f"after:  {show(s.read_status())}")
    s.sock.close()


if __name__ == "__main__":
    main()
