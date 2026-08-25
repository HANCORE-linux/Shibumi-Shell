#!/usr/bin/python3

from __future__ import annotations

import json
from pathlib import Path
import runpy
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT / "hancore.shibumi.network/scripts/network-qr-secret"


def canonical() -> bytes:
    device_id = "shibumi-network-v1:" + json.dumps(
        ["device", "wifi", "mac", "02:00:00:00:00:01"],
        separators=(",", ":"),
    )
    network_id = "shibumi-network-v1:" + json.dumps(
        ["network", device_id, "Private", "wpa2-psk"],
        separators=(",", ":"),
    )
    value = {
        "schemaVersion": 1,
        "requestToken": "shibumi-qr-secret-v1:[1,1]",
        "networkId": network_id,
        "profileUuid": "11111111-2222-4333-8444-555555555555",
        "deviceId": device_id,
        "interfaceName": "wlan0",
        "hardwareAddress": "02:00:00:00:00:01",
        "ssidHex": "50726976617465",
        "security": "wpa2-psk",
        "generation": 7,
    }
    return json.dumps(value, separators=(",", ":")).encode() + b"\n"


def expect_error(error: type[BaseException], callback: Any) -> None:
    try:
        callback()
    except error:
        return
    raise AssertionError("malformed QR secret input was accepted")


def main() -> int:
    module = runpy.run_path(str(HELPER))
    parse = module["parse_request"]
    extract = module["extract_psk"]
    bounded_settings_size = module["bounded_settings_size"]
    error = module["SecretError"]
    request = parse(canonical())
    if request["profileUuid"] != "11111111-2222-4333-8444-555555555555":
        raise AssertionError("valid QR secret request was rejected")

    malformed = [
        canonical()[:-1],
        canonical() + b"\n",
        canonical().replace(b'"generation":7', b'"generation":-1'),
        canonical().replace(b'"wlan0"', b'"../../wlan0"'),
        canonical().replace(b"02:00:00:00:00:01", b"00:00:00:00:00:00"),
        canonical().replace(b'"wpa2-psk"', b'"wpa2-eap"'),
        canonical().replace(b'"schemaVersion":1', b'"schemaVersion":1,"schemaVersion":1'),
    ]
    for value in malformed:
        expect_error(error, lambda value=value: parse(value))

    if extract({"802-11-wireless-security": {"psk": "correct horse"}},
               "wpa2-psk") != "correct horse":
        raise AssertionError("exact saved PSK was rejected")
    invalid_maps = [
        {},
        {"802-11-wireless-security": {}},
        {"802-11-wireless-security": {
            "psk": "correct horse", "identity": "unexpected"
        }},
        {"802-11-wireless-security": {"psk": "short"}},
        {"wifi-security": {"psk": "correct horse"}},
    ]
    for value in invalid_maps:
        expect_error(error, lambda value=value: extract(value, "wpa2-psk"))
    expect_error(error, lambda: bounded_settings_size({
        "oversized": b"x" * (module["MAX_SETTINGS_BYTES"] + 1)
    }))

    run = module["run"]
    globals_ = run.__globals__
    names = ["arm_parent_death", "owner", "device_path", "active_identity",
             "profile_snapshot", "interface", "owner_unchanged"]
    originals = {name: globals_[name] for name in names}
    calls: list[tuple[str, str]] = []

    class Connection:
        def GetSecrets(self, setting: str) -> dict[str, dict[str, str]]:
            calls.append(("GetSecrets", setting))
            return {"802-11-wireless-security": {"psk": "correct horse"}}

    globals_["arm_parent_death"] = lambda _pid: None
    globals_["owner"] = lambda _bus: ":1.77"
    globals_["device_path"] = lambda _bus, destination, _request: (
        calls.append(("device-owner", destination)) or "/device/1"
    )
    identity = ("/active/1", "/profile/1", "/ap/1")
    globals_["active_identity"] = lambda _bus, destination, _request, _device: (
        calls.append(("active-owner", destination)) or identity
    )
    globals_["profile_snapshot"] = (
        lambda _bus, destination, _profile, _request:
          calls.append(("settings-owner", destination))
          or (7, "50726976617465", "wpa2-psk")
    )
    globals_["interface"] = lambda _bus, destination, path, _name: (
        calls.append(("secret-owner", destination + path)) or Connection()
    )
    globals_["owner_unchanged"] = lambda _bus, destination: calls.append(
        ("revalidate-owner", destination)
    )
    original_bus = globals_["dbus"].SystemBus
    globals_["dbus"].SystemBus = lambda: object()
    try:
        result = run(request)
    finally:
        globals_["dbus"].SystemBus = original_bus
        globals_.update(originals)
    if result["psk"] != "correct horse" \
            or ("GetSecrets", "802-11-wireless-security") not in calls \
            or any(":1.77" not in value for kind, value in calls
                   if kind.endswith("owner")):
        raise AssertionError("QR secret read crossed its exact owner/setting boundary")

    globals_.update(originals)
    globals_["arm_parent_death"] = lambda _pid: None
    globals_["owner"] = lambda _bus: ":1.77"
    globals_["device_path"] = lambda _bus, _destination, _request: "/device/1"
    globals_["active_identity"] = (
        lambda _bus, _destination, _request, _device: identity
    )
    snapshots = iter([
        (7, "50726976617465", "wpa2-psk"),
        (8, "50726976617465", "wpa2-psk"),
    ])
    globals_["profile_snapshot"] = (
        lambda _bus, _destination, _profile, _request: next(snapshots)
    )
    globals_["interface"] = lambda *_args: Connection()
    globals_["owner_unchanged"] = lambda *_args: None
    globals_["dbus"].SystemBus = lambda: object()
    try:
        expect_error(error, lambda: run(request))
    finally:
        globals_["dbus"].SystemBus = original_bus
        globals_.update(originals)

    globals_["arm_parent_death"] = lambda _pid: None
    globals_["owner"] = lambda _bus: ":1.77"
    globals_["device_path"] = lambda _bus, _destination, _request: "/device/1"
    globals_["active_identity"] = (
        lambda _bus, _destination, _request, _device: identity
    )
    globals_["profile_snapshot"] = (
        lambda _bus, _destination, _profile, _request:
          (7, "50726976617465", "wpa2-psk")
    )
    globals_["interface"] = lambda *_args: Connection()
    final_checks = 0
    def changing_owner(_bus: object, _destination: str) -> None:
        nonlocal final_checks
        final_checks += 1
        if final_checks == 2:
            raise error("NetworkManager owner changed")
    globals_["owner_unchanged"] = changing_owner
    globals_["dbus"].SystemBus = lambda: object()
    try:
        expect_error(error, lambda: run(request))
    finally:
        globals_["dbus"].SystemBus = original_bus
        globals_.update(originals)

    print("network QR secret helper regression passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
