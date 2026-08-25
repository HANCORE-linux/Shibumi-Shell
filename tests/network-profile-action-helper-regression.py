#!/usr/bin/python3

from __future__ import annotations

import json
from pathlib import Path
import runpy

ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT / "hancore.shibumi.network/scripts/network-profile-action"


def canonical(action: str = "connect") -> bytes:
    value = {
        "schemaVersion": 1,
        "action": action,
        "requestToken": "shibumi-profile-action-v1:[1,1]",
        "uuid": "11111111-2222-4333-8444-555555555555",
        "deviceId": "shibumi-network-v1:[\"device\",\"wifi\"]" if action == "connect" else "",
        "interfaceName": "wlan0" if action == "connect" else "",
        "hardwareAddress": "02:00:00:00:00:01" if action == "connect" else "",
        "generation": 7,
    }
    return json.dumps(value, separators=(",", ":")).encode() + b"\n"


def expect_error(error: type[BaseException], callback: object) -> None:
    try:
        callback()
    except error:
        return
    raise AssertionError("malformed profile action was accepted")


def main() -> int:
    module = runpy.run_path(str(HELPER))
    parse = module["parse_request"]
    error = module["ActionError"]
    if parse(canonical())["action"] != "connect" \
            or parse(canonical("forget"))["action"] != "forget":
        raise AssertionError("valid exact profile action was rejected")
    malformed = [
        canonical()[:-1],
        canonical() + b"\n",
        canonical().replace(b'"generation":7', b'"generation":-1'),
        canonical().replace(b'"wlan0"', b'"../../wlan0"'),
        canonical().replace(b"02:00:00:00:00:01", b"00:00:00:00:00:00"),
        canonical("forget").replace(b'"deviceId":""', b'"deviceId":"x"'),
        canonical().replace(b'"action":"connect"', b'"action":"delete"'),
    ]
    for value in malformed:
        expect_error(error, lambda value=value: parse(value))

    run = module["run"]
    globals_ = run.__globals__
    originals = {name: globals_[name] for name in [
        "arm_parent_death", "owner", "profile_path", "device_path",
        "interface", "wait_connected", "owner_unchanged"
    ]}
    destinations: list[str] = []

    class Root:
        def ActivateConnection(self, profile: str, device: str, specific: str) -> str:
            if (profile, device, specific) != ("/profile/1", "/device/1", "/"):
                raise AssertionError("activation identity changed")
            return "/org/freedesktop/NetworkManager/ActiveConnection/1"

    globals_["arm_parent_death"] = lambda _pid: None
    globals_["owner"] = lambda _bus: ":1.77"
    globals_["profile_path"] = (
        lambda _bus, destination, _uuid:
          destinations.append(destination) or "/profile/1"
    )
    globals_["device_path"] = (
        lambda _bus, destination, _request:
          destinations.append(destination) or "/device/1"
    )
    globals_["interface"] = (
        lambda _bus, destination, _path, _name:
          destinations.append(destination) or Root()
    )
    globals_["wait_connected"] = (
        lambda _bus, destination, _active, _request, _device, _deadline:
          destinations.append(destination)
    )
    globals_["owner_unchanged"] = (
        lambda _bus, destination: destinations.append(destination)
    )
    original_bus = globals_["dbus"].SystemBus
    globals_["dbus"].SystemBus = lambda: object()
    try:
        result = run(parse(canonical()))
    finally:
        globals_["dbus"].SystemBus = original_bus
        globals_.update(originals)
    if result["status"] != "completed" or set(destinations) != {":1.77"}:
        raise AssertionError("profile action crossed NetworkManager owner")
    print("network profile action helper regression passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
