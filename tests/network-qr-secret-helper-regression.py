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


def expect_diagnostic(error: type[BaseException], code: str,
                      callback: Any) -> None:
    try:
        callback()
    except error as caught:
        if getattr(caught, "code", "") == code:
            return
        raise AssertionError("unexpected QR secret diagnostic") from caught
    raise AssertionError("missing QR secret diagnostic")


def main() -> int:
    module = runpy.run_path(str(HELPER))
    parse = module["parse_request"]
    extract = module["extract_psk"]
    bounded_settings_size = module["bounded_settings_size"]
    interactive_secrets = module["interactive_secrets"]
    authorization_code = module["authorization_failure_code"]
    active_code = module["active_failure_code"]
    profile_code = module["profile_failure_code"]
    error = module["SecretError"]
    diagnostic_error = module["DiagnosticError"]
    request = parse(canonical())
    if request["profileUuid"] != "11111111-2222-4333-8444-555555555555":
        raise AssertionError("valid QR secret request was rejected")
    if authorization_code(
            "org.freedesktop.NetworkManager.Settings.PermissionDenied") \
            != "authorization-denied" \
            or authorization_code(
                "org.freedesktop.NetworkManager.AgentManager.UserCanceled") \
            != "authorization-denied" \
            or authorization_code("org.freedesktop.DBus.Error.NoReply") \
            != "authorization-timeout" \
            or authorization_code("org.example.Other") \
            != "authorization-failed":
        raise AssertionError("authorization diagnostics are not fail-closed")
    if active_code("active network entity mismatch") \
            != "preflight-active-network" \
            or active_code("unknown") != "preflight-active" \
            or profile_code("profile security identity mismatch") \
            != "preflight-profile-security" \
            or profile_code("unknown") != "preflight-profile":
        raise AssertionError("preflight diagnostics are not fail-closed")

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
        {
            "connection": {"type": "802-11-wireless"},
            "802-11-wireless-security": {"psk": "correct horse"},
        },
    ]
    for value in invalid_maps:
        expect_error(error, lambda value=value: extract(value, "wpa2-psk"))
    expect_error(error, lambda: bounded_settings_size({
        "oversized": b"x" * (module["MAX_SETTINGS_BYTES"] + 1)
    }))

    class SecretReply:
        def __init__(self, signature: str = "a{sa{sv}}",
                     values: list[Any] | None = None) -> None:
            self.signature = signature
            self.values = values if values is not None else [{
                "802-11-wireless-security": {"psk": "correct horse"}
            }]
        def get_signature(self) -> str:
            return self.signature
        def get_args_list(self, **kwargs: Any) -> list[Any]:
            if kwargs != {"byte_arrays": True}:
                raise AssertionError("secret reply requested unsafe conversion")
            return self.values

    class SecretBus:
        def __init__(self, reply: SecretReply) -> None:
            self.reply = reply
            self.message: Any = None
            self.timeout: float = 0
        def send_message_with_reply_and_block(
            self, message: Any, timeout_s: float
        ) -> SecretReply:
            self.message = message
            self.timeout = timeout_s
            return self.reply

    secret_bus = SecretBus(SecretReply())
    secret_map = interactive_secrets(secret_bus, ":1.77",
        "/org/freedesktop/NetworkManager/Settings/1")
    message = secret_bus.message
    if secret_map["802-11-wireless-security"]["psk"] != "correct horse" \
            or message.get_destination() != ":1.77" \
            or message.get_path() \
                != "/org/freedesktop/NetworkManager/Settings/1" \
            or message.get_interface() != module["CONNECTION_INTERFACE"] \
            or message.get_member() != "GetSecrets" \
            or str(message.get_signature()) != "s" \
            or [str(value) for value in message.get_args_list()] \
                != ["802-11-wireless-security"] \
            or message.get_auto_start() \
            or not message.get_allow_interactive_authorization() \
            or secret_bus.timeout != module["AUTHORIZATION_TIMEOUT_SECONDS"]:
        raise AssertionError("interactive secret message crossed its exact boundary")
    expect_error(error, lambda: interactive_secrets(
        SecretBus(SecretReply("s", ["unexpected"])), ":1.77",
        "/org/freedesktop/NetworkManager/Settings/1"))
    expect_error(error, lambda: interactive_secrets(
        SecretBus(SecretReply(values=[])), ":1.77",
        "/org/freedesktop/NetworkManager/Settings/1"))
    expect_error(error, lambda: interactive_secrets(
        SecretBus(SecretReply()), "org.freedesktop.NetworkManager",
        "/org/freedesktop/NetworkManager/Settings/1"))

    active_identity = module["active_identity"]
    globals_ = active_identity.__globals__
    original_prop = globals_["prop"]
    device = "/org/freedesktop/NetworkManager/Devices/1"
    active = "/org/freedesktop/NetworkManager/ActiveConnection/1"
    profile = "/org/freedesktop/NetworkManager/Settings/1"
    access_point = "/org/freedesktop/NetworkManager/AccessPoint/1"
    accessed_properties: list[tuple[str, str, str]] = []
    properties = {
        (device, module["DEVICE_INTERFACE"], "ActiveConnection"): active,
        (active, module["ACTIVE_INTERFACE"], "State"): 2,
        (active, module["ACTIVE_INTERFACE"], "Uuid"):
          request["profileUuid"],
        (active, module["ACTIVE_INTERFACE"], "Devices"): [device],
        (active, module["ACTIVE_INTERFACE"], "Connection"): profile,
        (profile, module["CONNECTION_INTERFACE"], "Unsaved"): False,
        (device, module["WIRELESS_INTERFACE"], "ActiveAccessPoint"):
          access_point,
        (access_point, module["ACCESS_POINT_INTERFACE"], "Ssid"):
          b"Private",
    }
    def fake_prop(_bus: object, _destination: str, path: str,
                  interface_name: str, key: str) -> Any:
        accessed_properties.append((path, interface_name, key))
        return properties[(path, interface_name, key)]
    globals_["prop"] = fake_prop
    try:
        if active_identity(object(), ":1.77", request, device) \
                != (active, profile, access_point):
            raise AssertionError("active QR identity projection changed")
        active_uuid_key = (active, module["ACTIVE_INTERFACE"], "Uuid")
        if active_uuid_key not in accessed_properties:
            raise AssertionError("active QR identity skipped its UUID binding")
        properties[active_uuid_key] = "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee"
        expect_error(error, lambda: active_identity(
            object(), ":1.77", request, device))
    finally:
        globals_["prop"] = original_prop

    run = module["run"]
    profile_snapshot = module["profile_snapshot"]
    globals_ = run.__globals__
    boundary_names = ["arm_parent_death", "owner", "device_path",
                      "active_identity", "profile_snapshot", "interface",
                      "interactive_secrets", "owner_unchanged", "prop"]
    boundary_originals = {name: globals_[name] for name in boundary_names}
    original_bus = globals_["dbus"].SystemBus
    base_settings = {
        "connection": {
            "uuid": request["profileUuid"],
            "type": "802-11-wireless",
        },
        "802-11-wireless": {"ssid": b"Private"},
        "802-11-wireless-security": {
            "key-mgmt": "wpa-psk",
            "proto": ["rsn"],
        },
    }
    for field, invalid in (
        ("uuid", "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee"),
        ("type", "802-3-ethernet"),
    ):
        settings = {key: dict(value) for key, value in base_settings.items()}
        settings["connection"][field] = invalid
        secret_reads = [0]
        class ProfileConnection:
            def GetSettings(self) -> dict[str, Any]:
                return settings
            def GetSecrets(self, _setting: str) -> dict[str, Any]:
                secret_reads[0] += 1
                return {"802-11-wireless-security": {"psk": "correct horse"}}
        globals_["arm_parent_death"] = lambda _pid: None
        globals_["owner"] = lambda _bus: ":1.77"
        globals_["device_path"] = lambda *_args: device
        globals_["active_identity"] = lambda *_args: (
            active, profile, access_point)
        globals_["profile_snapshot"] = profile_snapshot
        globals_["interface"] = lambda *_args: ProfileConnection()
        globals_["interactive_secrets"] = lambda *_args: (
            secret_reads.__setitem__(0, secret_reads[0] + 1)
            or {"802-11-wireless-security": {"psk": "correct horse"}})
        globals_["owner_unchanged"] = lambda *_args: None
        globals_["prop"] = lambda *_args: 7
        globals_["dbus"].SystemBus = lambda: object()
        try:
            expect_error(error, lambda: run(request))
        finally:
            globals_["dbus"].SystemBus = original_bus
            globals_.update(boundary_originals)
        if secret_reads[0] != 0:
            raise AssertionError(
                "mismatched profile settings crossed GetSecrets")

    globals_ = run.__globals__
    names = ["arm_parent_death", "owner", "device_path", "active_identity",
             "profile_snapshot", "interface", "interactive_secrets",
             "owner_unchanged"]
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
        calls.append(("settings-interface", destination + path)) or Connection()
    )
    def valid_secrets(_bus: object, destination: str,
                      path: str) -> dict[str, dict[str, str]]:
        calls.append(("secret-owner", destination + path))
        return {"802-11-wireless-security": {"psk": "correct horse"}}
    def malformed_secrets(*_args: Any) -> Any:
        raise error("unexpected secret response signature")
    globals_["interactive_secrets"] = valid_secrets
    globals_["owner_unchanged"] = lambda _bus, destination: calls.append(
        ("revalidate-owner", destination)
    )
    original_bus = globals_["dbus"].SystemBus
    globals_["dbus"].SystemBus = lambda: object()
    try:
        globals_["interactive_secrets"] = malformed_secrets
        expect_diagnostic(
            diagnostic_error, "secret-response", lambda: run(request))
        globals_["interactive_secrets"] = valid_secrets
        result = run(request)
    finally:
        globals_["dbus"].SystemBus = original_bus
        globals_.update(originals)
    if result["psk"] != "correct horse" \
            or ("secret-owner", ":1.77/profile/1") not in calls \
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
    globals_["interactive_secrets"] = lambda *_args: {
        "802-11-wireless-security": {"psk": "correct horse"}
    }
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
    globals_["interactive_secrets"] = lambda *_args: {
        "802-11-wireless-security": {"psk": "correct horse"}
    }
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
