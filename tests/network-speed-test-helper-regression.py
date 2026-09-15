#!/usr/bin/python3
"""Regression checks for the bounded native speed-test worker."""

from __future__ import annotations

import importlib.machinery
import importlib.util
import io
import json
import subprocess
import sys
import time
import types
import unittest.mock
from pathlib import Path

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT / "hancore.shibumi.network/scripts/network-speed-test"


def load_helper() -> types.ModuleType:
    loader = importlib.machinery.SourceFileLoader("network_speed_test", str(HELPER))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    assert spec is not None
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


def check(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


class FakeResponse:
    status = 200

    def __init__(self, body: bytes) -> None:
        self.body = body
        self.offset = 0

    def read(self, amount: int) -> bytes:
        value = self.body[self.offset:self.offset + amount]
        self.offset += len(value)
        return value


class FakeBoundSocket:
    def __init__(self, source_address: str, interface_name: str) -> None:
        self.source_address = source_address
        self.interface_name = interface_name
        self.timeout = 0.0
        self.bound: tuple[str, int] | None = None
        self.destination: tuple[str, int] | None = None
        self.device_option = b""
        self.closed = False

    def settimeout(self, value: float) -> None:
        self.timeout = value

    def setsockopt(self, level: int, option: int, value: bytes) -> None:
        del level, option
        self.device_option = value

    def bind(self, value: tuple[str, int]) -> None:
        self.bound = value

    def connect(self, value: tuple[str, int]) -> None:
        self.destination = value

    def getsockopt(self, level: int, option: int, size: int) -> bytes:
        del level, option, size
        return self.interface_name.encode("ascii") + b"\0"

    def getsockname(self) -> tuple[str, int]:
        return self.source_address, 12345

    def close(self) -> None:
        self.closed = True


class FakeConnection:
    def __init__(self, response: FakeResponse) -> None:
        self.response = response
        self.sent = 0
        self.requests: list[tuple[str, str]] = []
        self.headers: list[tuple[str, str]] = []

    def request(self, method: str, path: str, headers: object) -> None:
        del headers
        self.requests.append((method, path))

    def getresponse(self) -> FakeResponse:
        return self.response

    def putrequest(self, method: str, path: str, **_kwargs: object) -> None:
        self.requests.append((method, path))

    def putheader(self, name: str, value: str) -> None:
        self.headers.append((name, value))

    def endheaders(self) -> None:
        return

    def send(self, value: bytes) -> None:
        self.sent += len(value)

    def close(self) -> None:
        return


def capture_emit(module: types.ModuleType) -> bytes:
    raw = io.BytesIO()
    stream = io.TextIOWrapper(raw, encoding="utf-8")
    original = sys.stdout
    try:
        sys.stdout = stream
        module.emit(
            "down", "eth0", 7, "192.0.2.10", "1:7:9", 125000, 1000
        )
        stream.flush()
        return raw.getvalue()
    finally:
        sys.stdout = original


def main() -> int:
    module = load_helper()
    source = HELPER.read_text(encoding="utf-8")

    check(module.HOST == "speed.cloudflare.com", "endpoint host is not fixed")
    check(module.PORT == 443, "endpoint port is not fixed TLS")
    check(module.DOWNLOAD_PATH == "/__down?bytes=8388608",
          "download path is not fixed and bounded")
    check(module.UPLOAD_PATH == "/__up", "upload path is not fixed")
    check(module.WORKERS == 4, "worker count changed")
    check(module.DOWNLOAD_LIMIT_BYTES == 1024 * 1024 * 1024,
          "download traffic budget changed")
    check(module.UPLOAD_LIMIT_BYTES == 512 * 1024 * 1024,
          "upload traffic budget changed")
    check("import subprocess" not in source and "urllib" not in source
          and "import requests" not in source and "curl" not in source,
          "worker gained an ambient command, redirect, or proxy backend")
    check("PR_SET_PDEATHSIG" in source and "signal.SIGKILL" in source,
          "worker lost parent-death supervision")
    check("socket.SO_BINDTODEVICE" in source
          and "interface_index(INTERFACE_NAME) != INTERFACE_INDEX" in source,
          "worker does not bind and revalidate the requested interface")
    check(module.interface_index("lo") > 0,
          "kernel loopback interface has no stable ifindex")

    valid_arguments = [
        "--direction", "down", "--interface", "eth0",
        "--source-address", "192.0.2.10", "--duration-ms", "4000",
        "--run-token", "1:7:9", "--expected-interface-index", "any",
    ]
    with unittest.mock.patch.object(Path, "is_dir", return_value=True):
        parsed = module.parse_arguments(valid_arguments)
        check(parsed == (
            "down", "eth0", "192.0.2.10", 4000, "1:7:9", None
        ),
              "valid arguments were not preserved")
        valid_v6 = valid_arguments.copy()
        valid_v6[5] = "2001:db8::10"
        check(module.parse_arguments(valid_v6)[2] == "2001:db8::10",
              "canonical IPv6 source was rejected")
        for reserved_v6 in (
            "100::1", "64:ff9b:1::1", "::ffff:201",
            "::ffff:0:c000:201"
        ):
            valid_v6[5] = reserved_v6
            check(module.parse_arguments(valid_v6)[2] == reserved_v6,
                  "reserved IPv6 source policy diverged")
        expected_index = valid_arguments.copy()
        expected_index[11] = "7"
        check(module.parse_arguments(expected_index)[5] == 7,
              "expected interface identity was rejected")
        invalid = [
            valid_arguments[:-1],
            [*valid_arguments[:1], "side", *valid_arguments[2:]],
            [*valid_arguments[:3], "../../lo", *valid_arguments[4:]],
            [*valid_arguments[:5], "127.0.0.1", *valid_arguments[6:]],
            [*valid_arguments[:5], "fe80::1", *valid_arguments[6:]],
            [*valid_arguments[:5], "::ffff:c000:201", *valid_arguments[6:]],
            [*valid_arguments[:5], "2001:4860:4860::8888%eth0",
             *valid_arguments[6:]],
            [*valid_arguments[:7], "0999", *valid_arguments[8:]],
            [*valid_arguments[:7], "9000", *valid_arguments[8:]],
            [*valid_arguments[:9], "stale", *valid_arguments[10:]],
            [*valid_arguments[:11], "0"],
            [*valid_arguments[:11], "2147483648"],
        ]
        for index, arguments in enumerate(invalid):
            try:
                module.parse_arguments(arguments)
            except module.SpeedTestError:
                continue
            raise AssertionError(f"invalid argument case accepted: {index}")

    expected_index = valid_arguments.copy()
    expected_index[11] = "7"
    with unittest.mock.patch.object(Path, "is_dir", return_value=True), \
            unittest.mock.patch.object(module, "interface_index", return_value=8), \
            unittest.mock.patch.object(module, "run_phase") as run_phase:
        check(module.run(expected_index) == 2,
              "inter-phase interface replacement did not fail closed")
        run_phase.assert_not_called()

    budget = module.TrafficBudget(100)
    check(budget.reserve(60) == 60 and budget.reserve(60) == 40
          and budget.reserve(1) == 0 and budget.exhausted(),
          "traffic budget can over-reserve")
    budget.commit(40)
    budget.refund(10)
    check(budget.successful() == 40 and budget.reserve(20) == 10,
          "traffic budget accounting is inconsistent")

    module.INTERFACE_NAME = "eth0"
    module.INTERFACE_INDEX = 7
    module.SOURCE_ADDRESS = "192.0.2.10"
    bound_socket = FakeBoundSocket("192.0.2.10", "eth0")
    with unittest.mock.patch.object(module, "interface_index", return_value=7), \
            unittest.mock.patch.object(module.socket, "getaddrinfo", return_value=[
                (module.socket.AF_INET, module.socket.SOCK_STREAM,
                 module.socket.IPPROTO_TCP, "", ("1.1.1.1", 443))
            ]), unittest.mock.patch.object(
                module.socket, "socket", return_value=bound_socket
            ):
        created = module.create_bound_socket()
    check(created is bound_socket
          and bound_socket.device_option == b"eth0\0"
          and bound_socket.bound == ("192.0.2.10", 0)
          and bound_socket.destination == ("1.1.1.1", 443),
          "TLS socket was not pinned to interface, source, and endpoint")

    replaced_socket = FakeBoundSocket("192.0.2.10", "eth0")
    with unittest.mock.patch.object(
        module, "interface_index", side_effect=[7, 8]
    ), unittest.mock.patch.object(module.socket, "getaddrinfo", return_value=[
        (module.socket.AF_INET, module.socket.SOCK_STREAM,
         module.socket.IPPROTO_TCP, "", ("1.1.1.1", 443))
    ]), unittest.mock.patch.object(
        module.socket, "socket", return_value=replaced_socket
    ):
        try:
            module.create_bound_socket()
        except module.SpeedTestError:
            pass
        else:
            raise AssertionError("recreated interface identity was accepted")
    check(replaced_socket.closed,
          "recreated-interface socket was not closed")

    module.STOP.clear()
    download_budget = module.TrafficBudget(100_000)
    download_connection = FakeConnection(FakeResponse(b"D" * 100_000))
    with unittest.mock.patch.object(
        module, "connection", return_value=download_connection
    ):
        module.download_worker(download_budget, time.monotonic() + 1, object())
    check(download_budget.successful() == 100_000,
          "download worker exceeded or lost its byte budget")
    check(download_connection.requests == [
        ("GET", "/__down?bytes=8388608")
    ], "download worker used a non-fixed request")

    module.STOP.clear()
    upload_budget = module.TrafficBudget(module.UPLOAD_OBJECT_BYTES)
    upload_connection = FakeConnection(FakeResponse(b"ok"))
    with unittest.mock.patch.object(
        module, "connection", return_value=upload_connection
    ):
        module.upload_worker(upload_budget, time.monotonic() + 1, object())
    check(upload_budget.successful() == module.UPLOAD_OBJECT_BYTES
          and upload_connection.sent == module.UPLOAD_OBJECT_BYTES,
          "upload worker did not enforce its reserved body bound")
    check(upload_connection.requests == [("POST", "/__up")],
          "upload worker used a non-fixed request")

    encoded = capture_emit(module)
    check(encoded.endswith(b"\n") and encoded.count(b"\n") == 1
          and len(encoded) <= module.MAX_PROTOCOL_BYTES + 1,
          "protocol emission is not one bounded line")
    line = encoded[:-1]
    parsed_record = json.loads(line)
    check(json.dumps(
        parsed_record, ensure_ascii=False, separators=(",", ":"), sort_keys=True
    ).encode() == line, "protocol emission is not canonical JSON")
    check(parsed_record["snapshot"]["endpoint"] == "speed.cloudflare.com"
          and parsed_record["snapshot"]["interfaceIndex"] == 7
          and parsed_record["snapshot"]["runToken"] == "1:7:9"
          and parsed_record["snapshot"]["bytesTransferred"] == 125000,
          "protocol emission changed measurement identity")

    result = subprocess.run(
        [str(HELPER), "--direction", "down", "--interface", "../../lo",
         "--source-address", "127.0.0.1", "--duration-ms", "4000",
         "--run-token", "1:7:9", "--expected-interface-index", "any"],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=3,
        check=False,
    )
    check(result.returncode == 2 and result.stdout == b"" and result.stderr == b"",
          "invalid CLI input did not fail closed without output")

    print("network speed-test helper regression passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
