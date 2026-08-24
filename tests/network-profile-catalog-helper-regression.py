#!/usr/bin/python3
"""Regression coverage for the bounded saved-profile catalog helper."""

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
HELPER = ROOT / "hancore.shibumi.network/scripts/network-profile-catalog"


def variant(type_name: str, data: object) -> dict[str, object]:
    return {"type": type_name, "data": data}


def wifi_settings() -> dict[str, object]:
    return {
        "connection": {
            "id": variant("s", "Enterprise fixture"),
            "uuid": variant("s", "11111111-2222-4333-8444-555555555555"),
            "type": variant("s", "802-11-wireless"),
            "autoconnect": variant("b", True),
            "timestamp": variant("t", 1234),
        },
        "802-11-wireless": {
            "ssid": variant("ay", list("Café".encode("utf-8"))),
            "hidden": variant("b", False),
        },
        "802-11-wireless-security": {
            "key-mgmt": variant("s", "wpa-eap"),
        },
        "802-1x": {
            "identity": variant("s", "must-not-leak@example.invalid"),
            "password": variant("s", "must-not-leak-secret"),
            "ca-cert": variant("ay", [1, 2, 3, 4]),
        },
    }


def expect_error(error_type: type[BaseException], callback: object) -> None:
    try:
        callback()
    except error_type:
        return
    raise AssertionError(f"expected {error_type.__name__}")


def main() -> int:
    module = runpy.run_path(str(HELPER))
    catalog_error = module["CatalogError"]
    profile_from_settings = module["profile_from_settings"]
    emit_catalog = module["emit_catalog"]
    parse_json = module["parse_json"]
    bounded_command = module["bounded_command"]
    property_state = module["property_state"]
    transient_unsaved = module["transient_unsaved"]
    revalidate_states = module["revalidate_states"]
    collect_profiles = module["collect_profiles"]

    property_calls: list[list[str]] = []
    property_globals = property_state.__globals__
    original_bounded_command = property_globals["bounded_command"]
    def fake_property_command(arguments: list[str], _limit: int, _deadline: float) -> bytes:
        property_calls.append(arguments)
        return b'{"type":"b","data":true}\n{"type":"t","data":7}\n{"type":"u","data":15}\n'
    property_globals["bounded_command"] = fake_property_command
    try:
        if property_state(
            "/org/freedesktop/NetworkManager/Settings/7",
            time.monotonic() + 1,
        ) != (True, 7, 15):
            raise AssertionError("per-connection property state changed")
    finally:
        property_globals["bounded_command"] = original_bounded_command
    expected_property_call = [
        module["BUSCTL"], "--system", "--json=short", "get-property",
        module["SERVICE"], "/org/freedesktop/NetworkManager/Settings/7",
        module["CONNECTION_INTERFACE"], "Unsaved", "VersionId", "Flags",
    ]
    if property_calls != [expected_property_call]:
        raise AssertionError(f"wrong per-connection property boundary: {property_calls!r}")
    if not transient_unsaved(15) or transient_unsaved(1):
        raise AssertionError("dirty persisted profile was classified as transient")
    revalidate_globals = revalidate_states.__globals__
    original_property_state = revalidate_globals["property_state"]
    revalidate_globals["property_state"] = lambda _path, _deadline: (False, 8, 0)
    try:
        expect_error(
            catalog_error,
            lambda: revalidate_states(
                ["/org/freedesktop/NetworkManager/Settings/7"],
                {"/org/freedesktop/NetworkManager/Settings/7": (True, 7, 15)},
                time.monotonic() + 1,
            ),
        )
    finally:
        revalidate_globals["property_state"] = original_property_state

    collect_globals = collect_profiles.__globals__
    original_list_connections = collect_globals["list_connections"]
    original_collect_property_state = collect_globals["property_state"]
    topology_calls = 0
    state_calls = 0
    test_path = "/org/freedesktop/NetworkManager/Settings/9"
    def fake_list_connections(_deadline: float) -> list[str]:
        nonlocal topology_calls
        topology_calls += 1
        return [test_path]
    def changing_property_state(_path: str, _deadline: float) -> tuple[bool, int, int]:
        nonlocal state_calls
        state_calls += 1
        return (True, 1, 15) if state_calls < 3 else (False, 2, 0)
    collect_globals["list_connections"] = fake_list_connections
    collect_globals["property_state"] = changing_property_state
    try:
        expect_error(catalog_error, collect_profiles)
    finally:
        collect_globals["list_connections"] = original_list_connections
        collect_globals["property_state"] = original_collect_property_state
    if topology_calls != 2 or state_calls != 3:
        raise AssertionError(
            f"collect snapshot skipped final state revalidation: "
            f"topology={topology_calls} state={state_calls}"
        )

    profile = profile_from_settings(wifi_settings())
    if profile != {
        "schemaVersion": 1,
        "uuid": "11111111-2222-4333-8444-555555555555",
        "name": "Enterprise fixture",
        "profileType": "wifi",
        "ssid": "Café",
        "ssidHex": "436166C3A9",
        "security": "wpa-eap",
        "enterprise": True,
        "hidden": False,
        "autoconnect": True,
        "timestamp": 1234,
    }:
        raise AssertionError(f"unexpected primitive projection: {profile!r}")

    wpa2 = wifi_settings()
    wpa2["802-11-wireless-security"] = {
        "key-mgmt": variant("s", "wpa-psk"),
        "proto": variant("as", ["rsn"]),
    }
    if profile_from_settings(wpa2)["security"] != "wpa2-psk":
        raise AssertionError("RSN-only PSK was not classified as WPA2")
    mixed = wifi_settings()
    mixed["802-11-wireless-security"] = {
        "key-mgmt": variant("s", "wpa-psk"),
        "proto": variant("as", ["wpa", "rsn"]),
    }
    if profile_from_settings(mixed)["security"] != "wpa-psk":
        raise AssertionError("mixed WPA profile lost generic security identity")
    leap = wifi_settings()
    leap["802-11-wireless-security"] = {
        "key-mgmt": variant("s", "ieee8021x"),
        "auth-alg": variant("s", "leap"),
    }
    if profile_from_settings(leap)["security"] != "leap":
        raise AssertionError("LEAP profile was conflated with dynamic WEP")

    non_utf8 = wifi_settings()
    non_utf8["802-11-wireless"]["ssid"] = variant("ay", [0xFF, 0x00, 0x7F])
    projected_non_utf8 = profile_from_settings(non_utf8)
    if projected_non_utf8["ssid"] != "" \
            or projected_non_utf8["ssidHex"] != "FF007F":
        raise AssertionError("non-UTF8 SSID did not retain bounded byte identity")

    output = io.BytesIO()
    emit_catalog([profile], output)
    lines = output.getvalue().decode("utf-8", errors="strict").splitlines()
    if len(lines) != 3 or any(len(line) > 2048 for line in lines):
        raise AssertionError("catalog protocol was not bounded")
    decoded = [json.loads(line) for line in lines]
    if decoded[0]["event"] != "begin" or decoded[1]["event"] != "profile" \
            or decoded[2]["event"] != "end":
        raise AssertionError("catalog protocol ordering changed")
    serialized_profile = decoded[1]["profile"]
    forbidden = {"identity", "password", "ca-cert", "settings", "path", "filename"}
    if forbidden.intersection(serialized_profile):
        raise AssertionError("sensitive settings escaped the helper boundary")

    duplicate_json = b'{"type":"b","data":false,"data":true}'
    expect_error(catalog_error, lambda: parse_json(duplicate_json))

    malformed_cases: list[dict[str, object]] = []
    invalid_uuid = wifi_settings()
    invalid_uuid["connection"]["uuid"] = variant("s", "{bad-uuid}")
    malformed_cases.append(invalid_uuid)
    oversized_name = wifi_settings()
    oversized_name["connection"]["id"] = variant("s", "x" * 257)
    malformed_cases.append(oversized_name)
    malformed_ssid = wifi_settings()
    malformed_ssid["802-11-wireless"]["ssid"] = variant("ay", [True])
    malformed_cases.append(malformed_ssid)
    malformed_security = wifi_settings()
    malformed_security["802-11-wireless-security"]["key-mgmt"] = variant(
        "s", ["wpa-eap"]
    )
    malformed_cases.append(malformed_security)
    oversized_timestamp = wifi_settings()
    oversized_timestamp["connection"]["timestamp"] = variant(
        "t", 9007199254740992
    )
    malformed_cases.append(oversized_timestamp)
    for settings in malformed_cases:
        expect_error(catalog_error, lambda settings=settings: profile_from_settings(settings))

    for size, accepted in ((63, True), (64, True), (65, False)):
        command = [
            sys.executable,
            "-c",
            f"import sys; sys.stdout.buffer.write(b'x'*{size})",
        ]
        if accepted:
            value = bounded_command(command, 64, time.monotonic() + 3)
            if len(value) != size:
                raise AssertionError("bounded reader truncated accepted output")
        else:
            expect_error(
                catalog_error,
                lambda command=command: bounded_command(
                    command, 64, time.monotonic() + 3
                ),
            )

    hostile_environment = dict(os.environ)
    hostile_environment.update({
        "PYTHONIOENCODING": "ascii",
        "SHIBUMI_PROFILE_HELPER": str(HELPER),
        "SHIBUMI_PROFILE_FIXTURE": json.dumps(profile, ensure_ascii=True),
    })
    hostile = subprocess.run(
        [
            sys.executable,
            "-c",
            "import json,os,runpy; m=runpy.run_path(os.environ['SHIBUMI_PROFILE_HELPER']); "
            "m['emit_catalog']([json.loads(os.environ['SHIBUMI_PROFILE_FIXTURE'])])",
        ],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
        check=False,
        env=hostile_environment,
    )
    if hostile.returncode != 0 or "Café" not in hostile.stdout.decode("utf-8"):
        raise AssertionError("hostile stdout encoding changed UTF-8 protocol")

    if os.environ.get("SHIBUMI_RUN_HOST_NETWORK_PROFILE_CATALOG") == "1":
        completed = subprocess.run(
            [sys.executable, str(HELPER)],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
            check=False,
        )
        if completed.returncode != 0:
            raise AssertionError(
                "read-only host catalog failed: "
                + completed.stderr.decode(errors="replace")
            )
        host_lines = completed.stdout.decode("utf-8", errors="strict").splitlines()
        if len(host_lines) < 2:
            raise AssertionError("host catalog omitted protocol boundaries")
        host_records = [json.loads(line) for line in host_lines]
        if host_records[0].get("event") != "begin" \
                or host_records[-1].get("event") != "end" \
                or host_records[0].get("count") != len(host_records) - 2 \
                or host_records[-1].get("count") != len(host_records) - 2:
            raise AssertionError("host catalog was not atomic")
        for record in host_records[1:-1]:
            if set(record) != {
                "schemaVersion", "event", "sequence", "index", "profile"
            }:
                raise AssertionError("host catalog exposed an undeclared field")
            if set(record["profile"]) != set(profile):
                raise AssertionError("host profile escaped the primitive schema")

    print("network profile catalog helper regression passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
