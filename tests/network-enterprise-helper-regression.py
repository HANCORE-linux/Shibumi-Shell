#!/usr/bin/python3
"""Regression checks for the bounded Enterprise Wi-Fi action helper."""

from __future__ import annotations

import importlib.machinery
import importlib.util
import json
import subprocess
import sys
import tempfile
import types
import unittest.mock
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT / "hancore.shibumi.network/scripts/network-enterprise-connect"


def load_helper() -> types.ModuleType:
    loader = importlib.machinery.SourceFileLoader(
        "network_enterprise_connect", str(HELPER)
    )
    spec = importlib.util.spec_from_loader(loader.name, loader)
    assert spec is not None
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


def check(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def request(**changes: object) -> dict[str, object]:
    value: dict[str, object] = {
        "deviceId": 'shibumi-network-v1:["device",["wifi","AA","wlan0"]]',
        "entityId": 'shibumi-network-v1:["network",["device","Corp","wpa2-eap"]]',
        "generation": 7,
        "hardwareAddress": "02:00:00:00:00:01",
        "identity": "user@example.test",
        "interfaceName": "wlan0",
        "method": "peap-mschapv2",
        "password": "transient enterprise secret",
        "requestToken": "shibumi-enterprise-v1:[1,2]",
        "schemaVersion": 1,
        "security": "wpa2-eap",
        "serverDomain": "radius.example.test",
        "ssidHex": "436F7270",
    }
    value.update(changes)
    return value


def encoded(value: dict[str, object]) -> bytes:
    return json.dumps(
        value, ensure_ascii=False, separators=(",", ":"), sort_keys=True
    ).encode("utf-8")


class FakeBus:
    def __init__(self) -> None:
        self.closed = False

    def close(self) -> None:
        self.closed = True


class FakeMethod:
    pass


def plain(value: object) -> object:
    if isinstance(value, dict):
        return {str(key): plain(item) for key, item in value.items()}
    if isinstance(value, (list, tuple)):
        return [plain(item) for item in value]
    if isinstance(value, (str, int, bool, bytes)):
        return value
    return str(value)


def main() -> int:
    module = load_helper()
    source = HELPER.read_text(encoding="utf-8")

    parsed = module.parse_request(encoded(request()))
    check(parsed == request(), "canonical request changed at parser boundary")
    opaque_password = " secret\twith\nintentional whitespace "
    spaced = module.parse_request(encoded(request(password=opaque_password)))
    check(spaced["password"] == opaque_password,
          "opaque password whitespace was not preserved")
    malformed = [
        b" " + encoded(request()),
        encoded(request()) + b" ",
        b'{"deviceId":"a","deviceId":"b"}',
        encoded(request(extra=True)),
        encoded(request(schemaVersion=2)),
        encoded(request(method="ttls-pap")),
        encoded(request(identity="")),
        encoded(request(identity="bad\nidentity")),
        encoded(request(hardwareAddress="00:00:00:00:00:00")),
        encoded(request(hardwareAddress="02:00:00:00:00:GG")),
        encoded(request(password="")),
        encoded(request(password="bad\x00password")),
        encoded(request(serverDomain="example")),
        encoded(request(serverDomain="*.example.test")),
        encoded(request(serverDomain="radius.example.test.")),
        encoded(request(interfaceName="../../wlan0")),
        encoded(request(security="wpa-eap")),
        encoded(request(security="wpa3-suite-b-192")),
        encoded(request(ssidHex="00" * 33)),
        encoded(request(requestToken="stale")),
    ]
    for index, value in enumerate(malformed):
        try:
            module.parse_request(value)
        except module.EnterpriseError:
            continue
        raise AssertionError(f"malformed request accepted: {index}")

    settings = module.build_settings(request())
    projected = plain(settings)
    check(set(projected) == {
        "802-11-wireless", "802-11-wireless-security", "802-1x",
        "connection", "ipv4", "ipv6",
    }, "Enterprise settings escaped the fixed group allowlist")
    eap = projected["802-1x"]
    security = projected["802-11-wireless-security"]
    check(eap == {
        "domain-suffix-match": "radius.example.test",
        "eap": ["peap"],
        "identity": "user@example.test",
        "password": "transient enterprise secret",
        "password-flags": 0,
        "phase2-auth": "mschapv2",
        "system-ca-certs": 1,
    }, "PEAP/MSCHAPv2 trust or credential settings changed")
    check(security == {"key-mgmt": "wpa-eap", "proto": ["rsn"]},
          "WPA2 Enterprise security settings changed")
    check(projected["connection"]["autoconnect"] == 0,
          "volatile Enterprise profile gained autoconnect")
    check(projected["connection"]["id"] == "shibumi-enterprise-v1:[1,2]",
          "activation profile lost its exact request identity")
    check(bytes(settings["802-11-wireless"]["ssid"]) == b"Corp",
          "SSID byte identity changed")

    with unittest.mock.patch.object(
        module, "dbus_method", return_value=FakeMethod()
    ), unittest.mock.patch.object(module, "call", return_value=":1.0"):
        check(module.name_owner(FakeBus(), 10**9) == ":1.0",
              "valid zero-component unique owner was rejected")
    for malformed_owner in ("1.0", ":0.1", ":1.-1", ":1.a", ":1.0.extra"):
        with unittest.mock.patch.object(
            module, "dbus_method", return_value=FakeMethod()
        ), unittest.mock.patch.object(module, "call", return_value=malformed_owner):
            try:
                module.name_owner(FakeBus(), 10**9)
            except module.EnterpriseError:
                continue
            raise AssertionError(f"malformed unique owner accepted: {malformed_owner}")

    check(not module.ap_security_matches("wpa-eap", 0x200, 0),
          "legacy WPA Enterprise crossed the WPA2-only boundary")
    check(module.ap_security_matches("wpa2-eap", 0, 0x200),
          "WPA2 Enterprise AP was rejected")
    check(not module.ap_security_matches("wpa2-eap", 0, 0x2200),
          "Suite-B AP crossed the PEAP boundary")

    def activation_property(
        _bus: object, _owner: str, _path: str, interface: str,
        name: str, _deadline: float
    ) -> object:
        values = {
            (module.ACTIVE_CONNECTION_INTERFACE, "Id"):
                "shibumi-enterprise-v1:[1,2]",
            (module.ACTIVE_CONNECTION_INTERFACE, "Devices"): ["/device/7"],
            (module.ACTIVE_CONNECTION_INTERFACE, "State"): 2,
            (module.WIRELESS_INTERFACE, "ActiveAccessPoint"): "/accesspoint/9",
        }
        return values[(interface, name)]

    with unittest.mock.patch.object(
        module, "name_owner", return_value=":1.9"
    ), unittest.mock.patch.object(
        module, "property_value", side_effect=activation_property
    ), unittest.mock.patch.object(
        module, "device_path", return_value="/device/7"
    ), unittest.mock.patch.object(
        module, "ap_snapshot", return_value=(b"Corp", 0, 0x200, 75)
    ):
        activation = module.wait_for_activation(
            FakeBus(), ":1.9", "/active/1", "/device/7", request(), 10**9
        )
    check(activation["requestToken"] == "shibumi-enterprise-v1:[1,2]"
          and activation["status"] == "connected"
          and activation["hardwareAddress"] == "02:00:00:00:00:01",
          "exact active-connection completion was not emitted")

    fake_bus = FakeBus()
    method = FakeMethod()
    calls: list[tuple[object, ...]] = []

    def fake_call(method_value: object, _deadline: float, *arguments: object) \
            -> object:
        calls.append((method_value, *arguments))
        return (
            "/org/freedesktop/NetworkManager/Settings/99",
            "/org/freedesktop/NetworkManager/ActiveConnection/99",
            {},
        )

    action_request = request()
    with unittest.mock.patch.object(
        module.dbus, "SystemBus", return_value=fake_bus
    ), unittest.mock.patch.object(
        module, "name_owner", side_effect=[":1.9", ":1.9"]
    ), unittest.mock.patch.object(
        module, "device_path", side_effect=["/device/7", "/device/7"]
    ), unittest.mock.patch.object(
        module, "access_point_path", return_value="/accesspoint/8"
    ), unittest.mock.patch.object(
        module, "ap_snapshot", return_value=(b"Corp", 0, 0x200, 75)
    ), unittest.mock.patch.object(
        module, "dbus_method", return_value=method
    ), unittest.mock.patch.object(
        module, "wait_for_activation", return_value={"status": "connected"}
    ), unittest.mock.patch.object(module, "call", side_effect=fake_call):
        completion = module.dispatch(action_request, 10**9)
    check(completion == {"status": "connected"},
          "activation completion was not returned")
    check(fake_bus.closed, "private system bus was not closed")
    check(action_request["password"] == "",
          "parsed password was retained after D-Bus dispatch")
    check(len(calls) == 1 and calls[0][0] is method,
          "activation method was not called exactly once")
    options = plain(calls[0][-1])
    check(options == {"persist": "volatile"},
          "Enterprise credentials can persist in NetworkManager")

    replaced_bus = FakeBus()
    with unittest.mock.patch.object(
        module.dbus, "SystemBus", return_value=replaced_bus
    ), unittest.mock.patch.object(
        module, "name_owner", side_effect=[":1.9", ":1.10"]
    ), unittest.mock.patch.object(
        module, "device_path", return_value="/device/7"
    ), unittest.mock.patch.object(
        module, "access_point_path", return_value="/accesspoint/8"
    ):
        try:
            module.dispatch(request(), 10**9)
        except module.EnterpriseError:
            pass
        else:
            raise AssertionError("NetworkManager owner replacement was accepted")
    check(replaced_bus.closed, "replacement-race bus was not closed")

    hardware_bus = FakeBus()
    with unittest.mock.patch.object(
        module.dbus, "SystemBus", return_value=hardware_bus
    ), unittest.mock.patch.object(
        module, "name_owner", side_effect=[":1.9", ":1.9"]
    ), unittest.mock.patch.object(
        module, "device_path", side_effect=[
            "/device/7", module.EnterpriseError("device hardware changed")
        ]
    ), unittest.mock.patch.object(
        module, "access_point_path", return_value="/accesspoint/8"
    ):
        try:
            module.dispatch(request(), 10**9)
        except module.EnterpriseError:
            pass
        else:
            raise AssertionError("replacement hardware was accepted")
    check(hardware_bus.closed, "hardware-race bus was not closed")

    check("GetSecrets" not in source and "nmcli" not in source
          and "subprocess" not in source and "shell=True" not in source,
          "helper crossed the fixed direct D-Bus boundary")
    check("system-ca-certs" in source and "domain-suffix-match" in source,
          "server certificate validation is not mandatory")
    check('"persist": dbus.String("volatile")' in source,
          "Enterprise profile is not volatile")
    check("print(" not in source and "logging" not in source,
          "helper can log credential-bearing data")

    with tempfile.TemporaryDirectory(prefix="shibumi-enterprise-site-") as temp:
        site = Path(temp)
        marker = site / "shadow-imported"
        (site / "dbus.py").write_text(
            f"from pathlib import Path\nPath({str(marker)!r}).write_text('bad')\n"
            "raise RuntimeError('shadow dbus imported')\n",
            encoding="utf-8",
        )
        isolated = subprocess.run(
            ["/usr/bin/python3", "-I", str(HELPER)],
            input=b'{"bad":1}\n',
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env={"PYTHONPATH": str(site), "PATH": "/usr/bin"},
            timeout=3,
            check=False,
        )
        check(isolated.returncode == 2 and not marker.exists(),
              "isolated helper imported a shadowing dbus module")

    process = subprocess.run(
        [str(HELPER)],
        input=b'{"bad":1}\n',
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=3,
        check=False,
    )
    check(process.returncode == 2 and process.stdout == b""
          and process.stderr == b"",
          "invalid stdin did not fail silently and closed")

    print("network enterprise helper regression passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
