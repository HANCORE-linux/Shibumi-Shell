#!/usr/bin/python3
"""Deterministic source-only fixture for NetworkSpeedTest QML tests."""

from __future__ import annotations

import json
import os
import signal
import sys
import time
from pathlib import Path


def next_invocation(path: Path) -> int:
    try:
        value = int(path.read_text(encoding="ascii").strip()) + 1
    except (FileNotFoundError, ValueError):
        value = 1
    temporary = path.with_suffix(".tmp")
    temporary.write_text(f"{value}\n", encoding="ascii")
    os.replace(temporary, path)
    return value


def parse_arguments(
    arguments: list[str],
) -> tuple[str, str, str, int, str, str]:
    if len(arguments) != 12 or arguments[0] != "--direction" \
            or arguments[2] != "--interface" \
            or arguments[4] != "--source-address" \
            or arguments[6] != "--duration-ms" \
            or arguments[8] != "--run-token" \
            or arguments[10] != "--expected-interface-index":
        raise ValueError("invalid fixture arguments")
    return (
        arguments[1], arguments[3], arguments[5], int(arguments[7]),
        arguments[9], arguments[11],
    )


def emit(
    direction: str,
    interface_name: str,
    source_address: str,
    invocation: int,
    sample_monotonic_ms: int | None = None,
    interface_index: int = 7,
    run_token: str | None = None,
) -> None:
    transferred = 12_500_000 if direction == "down" else 6_250_000
    record = {
        "schemaVersion": 1,
        "event": "result",
        "sequence": 1,
        "snapshot": {
            "schemaVersion": 1,
            "direction": direction,
            "endpoint": "speed.cloudflare.com",
            "interfaceIndex": interface_index,
            "interfaceName": interface_name,
            "runToken": RUN_TOKEN if run_token is None else run_token,
            "sourceAddress": source_address,
            "bytesTransferred": transferred,
            "elapsedMs": 1000,
            "sampleMonotonicMs": invocation * 1000
            if sample_monotonic_ms is None else sample_monotonic_ms,
        },
    }
    print(
        json.dumps(record, ensure_ascii=False, separators=(",", ":"), sort_keys=True),
        flush=True,
    )


def main() -> int:
    global RUN_TOKEN
    if len(sys.argv) < 14:
        return 2
    counter = Path(sys.argv[1])
    arguments = sys.argv[2:]
    mode = "sequence"
    if arguments and not arguments[0].startswith("--"):
        mode = arguments.pop(0)
    try:
        (
            direction, interface_name, source_address, _duration,
            RUN_TOKEN, _expected_interface_index,
        ) = parse_arguments(arguments)
    except (ValueError, IndexError):
        return 2
    invocation = next_invocation(counter)

    if mode == "malformed":
        print('{"bad":1}', flush=True)
        return 0
    if mode == "empty":
        return 0
    if mode == "fail":
        return 7
    if mode == "flood-stdout":
        counter.with_name(counter.name + ".flood.pid").write_text(
            f"{os.getpid()}\n", encoding="ascii"
        )
        os.write(1, b"A" * (1024 * 1024))
        time.sleep(30)
        return 0
    if mode == "flood-stderr":
        os.write(2, b"E" * (1024 * 1024))
        emit(direction, interface_name, source_address, invocation)
        return 0
    if mode == "slow":
        counter.with_name(counter.name + ".pid").write_text(
            f"{os.getpid()}\n", encoding="ascii"
        )
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
        emit(direction, interface_name, source_address, invocation)
        time.sleep(30)
        return 0
    if mode == "delayed":
        counter.with_name(counter.name + ".pid").write_text(
            f"{os.getpid()}\n", encoding="ascii"
        )
        time.sleep(0.4)
        emit(direction, interface_name, source_address, invocation)
        return 0
    if mode == "replay-up" and direction == "up":
        emit(
            direction, interface_name, source_address, invocation,
            sample_monotonic_ms=max(0, (invocation - 1) * 1000),
        )
        return 0
    if mode == "changed-index-up" and direction == "up":
        emit(
            direction, interface_name, source_address, invocation,
            interface_index=8,
        )
        return 0
    if mode == "stale-token":
        emit(
            direction, interface_name, source_address, invocation,
            run_token="9:9:9",
        )
        return 0

    emit(direction, interface_name, source_address, invocation)
    return 0


RUN_TOKEN = ""

if __name__ == "__main__":
    raise SystemExit(main())
