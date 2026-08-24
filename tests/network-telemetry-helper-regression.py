#!/usr/bin/python3
"""Regression coverage for the bounded native network telemetry helper."""

from __future__ import annotations

import io
import json
import os
from pathlib import Path
import runpy
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT / "hancore.shibumi.network/scripts/network-telemetry-snapshot"


def variant(type_name: str, data: object) -> dict[str, object]:
    return {"type": type_name, "data": data}


def expect_error(error_type: type[BaseException], callback: object) -> None:
    try:
        callback()
    except error_type:
        return
    raise AssertionError(f"expected {error_type.__name__}")


def main() -> int:
    module = runpy.run_path(str(HELPER))
    telemetry_error = module["TelemetryError"]
    parse_json = module["parse_json"]
    get_properties = module["get_properties"]
    parse_addresses = module["parse_addresses"]
    parse_ipv6_nameservers = module["parse_ipv6_nameservers"]
    ssid_fields = module["ssid_fields"]
    collect_snapshot = module["collect_snapshot"]
    disconnected_snapshot = module["disconnected_snapshot"]
    emit_snapshot = module["emit_snapshot"]
    bounded_command = module["bounded_command"]

    property_calls: list[list[str]] = []
    property_globals = get_properties.__globals__
    original_bounded = property_globals["bounded_command"]

    def fake_property_command(
        arguments: list[str], _limit: int, _deadline: float
    ) -> bytes:
        property_calls.append(arguments)
        return b'{"type":"s","data":"eth0"}\n{"type":"u","data":100}\n'

    property_globals["bounded_command"] = fake_property_command
    try:
        result = get_properties(
            "/org/freedesktop/NetworkManager/Devices/7",
            module["DEVICE_INTERFACE"],
            [("Interface", "s"), ("State", "u")],
            time.monotonic() + 1,
        )
    finally:
        property_globals["bounded_command"] = original_bounded
    if result != {"Interface": "eth0", "State": 100}:
        raise AssertionError("typed property projection changed")
    expected_call = [
        module["BUSCTL"], "--system", "--json=short", "get-property",
        module["SERVICE"], "/org/freedesktop/NetworkManager/Devices/7",
        module["DEVICE_INTERFACE"], "Interface", "State",
    ]
    if property_calls != [expected_call]:
        raise AssertionError(f"property boundary changed: {property_calls!r}")

    addresses = parse_addresses([
        {"address": variant("s", "192.0.2.10"), "prefix": variant("u", 24)},
        {"address": variant("s", "2001:db8::1"), "prefix": variant("u", 64)},
    ][:1], 4)
    if addresses != [{"family": "ipv4", "address": "192.0.2.10", "prefix": 24}]:
        raise AssertionError("IPv4 address projection changed")
    expect_error(telemetry_error, lambda: parse_addresses([
        {"address": variant("s", "192.0.2.10"), "prefix": variant("u", 24)},
        {"address": variant("s", "192.0.2.10"), "prefix": variant("u", 24)},
    ], 4))
    expect_error(telemetry_error, lambda: parse_addresses([
        {"address": variant("s", "192.0.2.999"), "prefix": variant("u", 24)}
    ], 4))
    ipv6_dns = parse_ipv6_nameservers([list(bytes.fromhex(
        "20010db8000000000000000000000053"
    ))])
    if ipv6_dns != [{"family": "ipv6", "address": "2001:db8::53"}]:
        raise AssertionError("IPv6 DNS byte projection changed")
    if ssid_fields(list("Café".encode("utf-8"))) != ("Café", "436166C3A9"):
        raise AssertionError("UTF-8 SSID identity changed")
    if ssid_fields([0xFF, 0x00, 0x7F]) != ("", "FF007F"):
        raise AssertionError("binary SSID identity was not retained")

    collect_globals = collect_snapshot.__globals__
    originals = {
        name: collect_globals[name]
        for name in ["get_name_owner", "get_properties", "ip_snapshot", "read_counter"]
    }
    primary = "/org/freedesktop/NetworkManager/ActiveConnection/7"
    device_path = "/org/freedesktop/NetworkManager/Devices/7"
    ip4_path = "/org/freedesktop/NetworkManager/IP4Config/7"
    ip6_path = "/org/freedesktop/NetworkManager/IP6Config/7"
    active = {
        "Id": "Wired Café",
        "Uuid": "11111111-2222-4333-8444-555555555555",
        "Type": "802-3-ethernet",
        "Devices": [device_path],
        "State": 2,
        "Ip4Config": ip4_path,
        "Ip6Config": ip6_path,
        "SpecificObject": "/",
    }
    device = {
        "Interface": "eth0",
        "IpInterface": "eth0",
        "DeviceType": 1,
        "State": 100,
        "HwAddress": "02:00:00:00:00:07",
        "Metered": 2,
        "ActiveConnection": primary,
    }
    ip4 = (
        [{"family": "ipv4", "address": "192.0.2.10", "prefix": 24}],
        [{"family": "ipv4", "address": "192.0.2.53"}],
        ["example.invalid"],
        "192.0.2.1",
    )
    ip6 = (
        [{"family": "ipv6", "address": "2001:db8::10", "prefix": 64}],
        [{"family": "ipv6", "address": "2001:db8::53"}],
        [],
        "2001:db8::1",
    )
    property_count = 0
    ip_count = 0
    destinations: list[str] = []

    def fake_owner(_deadline: float) -> str:
        return ":1.7"

    def fake_properties(
        path: str, interface: str, _properties: list[tuple[str, str]],
        _deadline: float, _destination: str = "",
    ) -> dict[str, object]:
        nonlocal property_count
        property_count += 1
        destinations.append(_destination)
        if path == module["ROOT_PATH"]:
            return {"PrimaryConnection": primary}
        if path == primary:
            return dict(active)
        if path == device_path and interface == module["DEVICE_INTERFACE"]:
            return dict(device)
        if path == device_path and interface == module["WIRED_INTERFACE"]:
            return {"Speed": 1000, "Carrier": True}
        raise AssertionError(f"unexpected property request: {path} {interface}")

    def fake_ip(
        path: str, family: int, _deadline: float, _destination: str = ""
    ) -> object:
        nonlocal ip_count
        ip_count += 1
        destinations.append(_destination)
        return ip4 if path == ip4_path and family == 4 else ip6

    def fake_counter(_iface: str, counter: str) -> int:
        return 123456 if counter == "rx_bytes" else 654321

    collect_globals["get_name_owner"] = fake_owner
    collect_globals["get_properties"] = fake_properties
    collect_globals["ip_snapshot"] = fake_ip
    collect_globals["read_counter"] = fake_counter
    try:
        snapshot = collect_snapshot()
    finally:
        collect_globals.update(originals)
    if property_count != 7 or ip_count != 4 \
            or set(destinations) != {":1.7"}:
        raise AssertionError(
            f"full snapshot skipped final race checks: properties={property_count} ip={ip_count}"
        )
    if snapshot["connectionUuid"] != active["Uuid"] \
            or snapshot["connectionName"] != "Wired Café" \
            or snapshot["kind"] != "wired" \
            or snapshot["addresses"] != ip4[0] + ip6[0] \
            or snapshot["dnsServers"] != ip4[1] + ip6[1] \
            or snapshot["gateways"] != [
                {"family": "ipv4", "address": "192.0.2.1"},
                {"family": "ipv6", "address": "2001:db8::1"},
            ] \
            or snapshot["rxBytes"] != 123456 \
            or snapshot["txBytes"] != 654321 \
            or snapshot["wired"] != {"speedMbps": 1000, "carrier": True}:
        raise AssertionError(f"primitive telemetry projection changed: {snapshot!r}")
    forbidden = {"path", "activePath", "devicePath", "settings", "secrets"}
    if forbidden.intersection(snapshot):
        raise AssertionError("private backend identity escaped telemetry")

    owner_calls = 0
    collect_globals.update(originals)
    collect_globals["get_properties"] = fake_properties
    collect_globals["ip_snapshot"] = fake_ip
    collect_globals["read_counter"] = fake_counter

    def changing_owner(_deadline: float) -> str:
        nonlocal owner_calls
        owner_calls += 1
        return ":1.7" if owner_calls == 1 else ":1.8"

    collect_globals["get_name_owner"] = changing_owner
    try:
        expect_error(telemetry_error, collect_snapshot)
    finally:
        collect_globals.update(originals)
    if owner_calls != 2:
        raise AssertionError("owner replacement was not revalidated")

    final_active_seen = False
    active_calls = 0
    def late_primary_change(
        path: str, interface: str, properties: list[tuple[str, str]],
        deadline: float, destination: str = "",
    ) -> dict[str, object]:
        nonlocal active_calls, final_active_seen
        if path == primary:
            active_calls += 1
            if active_calls > 1:
                final_active_seen = True
            return dict(active)
        if path == module["ROOT_PATH"]:
            return {"PrimaryConnection":
                "/org/freedesktop/NetworkManager/ActiveConnection/8"
                if final_active_seen else primary}
        return fake_properties(path, interface, properties, deadline, destination)

    collect_globals["get_name_owner"] = fake_owner
    collect_globals["get_properties"] = late_primary_change
    collect_globals["ip_snapshot"] = fake_ip
    collect_globals["read_counter"] = fake_counter
    try:
        expect_error(telemetry_error, collect_snapshot)
    finally:
        collect_globals.update(originals)
    if not final_active_seen or active_calls != 2:
        raise AssertionError("late primary change did not reach final parent check")

    ip_calls = 0
    collect_globals["get_name_owner"] = fake_owner
    collect_globals["get_properties"] = fake_properties
    collect_globals["read_counter"] = fake_counter

    def changing_ip(
        path: str, family: int, _deadline: float, _destination: str = ""
    ) -> object:
        nonlocal ip_calls
        ip_calls += 1
        if path == ip4_path and family == 4 and ip_calls >= 3:
            return ([], [], [], "")
        return ip4 if family == 4 else ip6

    collect_globals["ip_snapshot"] = changing_ip
    try:
        expect_error(telemetry_error, collect_snapshot)
    finally:
        collect_globals.update(originals)
    if ip_calls != 4:
        raise AssertionError("IP/DNS in-place race was not revalidated")

    disconnected_calls = 0

    def disconnected_properties(
        _path: str, _interface: str, _properties: list[tuple[str, str]],
        _deadline: float, _destination: str = "",
    ) -> dict[str, object]:
        nonlocal disconnected_calls
        disconnected_calls += 1
        return {"PrimaryConnection": "/"}

    collect_globals["get_name_owner"] = fake_owner
    collect_globals["get_properties"] = disconnected_properties
    try:
        disconnected = collect_snapshot()
    finally:
        collect_globals.update(originals)
    if disconnected != disconnected_snapshot(disconnected["sampleMonotonicMs"]) \
            or disconnected_calls != 2:
        raise AssertionError("disconnected state was not revalidated atomically")

    output = io.BytesIO()
    emit_globals = emit_snapshot.__globals__
    original_stdout = emit_globals["sys"].stdout

    class BinaryStdout:
        def __init__(self, buffer: io.BytesIO) -> None:
            self.buffer = buffer

    emit_globals["sys"].stdout = BinaryStdout(output)
    try:
        emit_snapshot(snapshot)
    finally:
        emit_globals["sys"].stdout = original_stdout
    line = output.getvalue().decode("utf-8", errors="strict").strip()
    record = json.loads(line)
    if len(line.encode("utf-8")) > module["MAX_PROTOCOL_LINE"] \
            or record["event"] != "snapshot" or record["snapshot"] != snapshot:
        raise AssertionError("telemetry protocol changed")

    expect_error(
        telemetry_error,
        lambda: parse_json(b'{"type":"u","data":1,"data":2}'),
    )
    for size, accepted in ((63, True), (64, True), (65, False)):
        command = [
            sys.executable, "-c",
            f"import sys; sys.stdout.buffer.write(b'x'*{size})",
        ]
        if accepted:
            if len(bounded_command(command, 64, time.monotonic() + 3)) != size:
                raise AssertionError("bounded reader truncated output")
        else:
            expect_error(
                telemetry_error,
                lambda command=command: bounded_command(
                    command, 64, time.monotonic() + 3
                ),
            )

    source = HELPER.read_text()
    for forbidden_token in ("nmcli", "GetSecrets", "omarchy-"):
        if forbidden_token in source:
            raise AssertionError(f"forbidden helper dependency: {forbidden_token}")

    if os.environ.get("SHIBUMI_RUN_HOST_NETWORK_TELEMETRY") == "1":
        completed = subprocess.run(
            [sys.executable, str(HELPER)],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=20,
            check=False,
        )
        if completed.returncode != 0:
            raise AssertionError(
                "read-only host telemetry failed: "
                + completed.stderr.decode(errors="replace")
            )
        host_line = completed.stdout.decode("utf-8", errors="strict").strip()
        host_record = json.loads(host_line)
        if set(host_record) != {"schemaVersion", "event", "sequence", "snapshot"} \
                or host_record["event"] != "snapshot":
            raise AssertionError("host telemetry protocol changed")

    print("network telemetry helper regression passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
