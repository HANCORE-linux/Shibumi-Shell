#!/usr/bin/python3
"""Deterministic source-only fixture for NetworkReachability QML tests."""

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


def endpoint(status: str, latency: float | None) -> dict[str, object]:
    return {"status": status, "latencyMs": latency}


def parse_route(arguments: list[str]) -> tuple[str, str]:
    if len(arguments) != 4 or arguments[0] != "--interface" \
            or arguments[2] != "--gateway":
        raise ValueError("invalid fixture arguments")
    return arguments[1], "" if arguments[3] == "none" else arguments[3]


def emit(
    interface_name: str,
    gateway: str,
    invocation: int,
    router: dict[str, object],
    internet: dict[str, object],
    sample_monotonic_ms: int | None = None,
) -> None:
    record = {
        "schemaVersion": 1,
        "event": "snapshot",
        "sequence": 1,
        "snapshot": {
            "schemaVersion": 1,
            "interfaceName": interface_name,
            "gateway": gateway,
            "internetTarget": "1.1.1.1",
            "sampleMonotonicMs": invocation * 1000
            if sample_monotonic_ms is None else sample_monotonic_ms,
            "router": router,
            "internet": internet,
        },
    }
    print(
        json.dumps(record, ensure_ascii=False, separators=(",", ":"), sort_keys=True),
        flush=True,
    )


def main() -> int:
    if len(sys.argv) < 6:
        return 2
    counter = Path(sys.argv[1])
    arguments = sys.argv[2:]
    mode = "sequence"
    if arguments and not arguments[0].startswith("--"):
        mode = arguments.pop(0)
    try:
        interface_name, gateway = parse_route(arguments)
    except ValueError:
        return 2
    invocation = next_invocation(counter)

    if mode == "slow":
        counter.with_name(counter.name + ".pid").write_text(
            f"{os.getpid()}\n", encoding="ascii"
        )
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
        emit(
            interface_name, gateway, invocation,
            endpoint("reply", 1), endpoint("reply", 2),
        )
        time.sleep(30)
        return 0
    if mode == "flood-stdout":
        os.write(1, b"A" * (1024 * 1024))
        time.sleep(30)
        return 0
    if mode.startswith("stdout-"):
        os.write(1, b"A" * int(mode.removeprefix("stdout-")))
        return 0
    if mode == "malformed-slow":
        counter.with_name(counter.name + ".pid").write_text(
            f"{os.getpid()}\n", encoding="ascii"
        )
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
        print('{"bad":1}', flush=True)
        time.sleep(30)
        return 0
    if mode == "replay":
        emit(
            interface_name, gateway, invocation,
            endpoint("reply", 6) if gateway else endpoint("skipped", None),
            endpoint("reply", 7),
            sample_monotonic_ms=(invocation - 1) * 1000,
        )
        return 0
    if mode == "flood-stderr":
        os.write(2, b"E" * (1024 * 1024))
        emit(
            interface_name, gateway, invocation,
            endpoint("reply", 3) if gateway else endpoint("skipped", None),
            endpoint("reply", 4),
        )
        return 0

    if invocation == 1:
        emit(
            interface_name, gateway, invocation,
            endpoint("reply", 10) if gateway else endpoint("skipped", None),
            endpoint("reply", 20),
        )
    elif invocation == 2:
        emit(
            interface_name, gateway, invocation,
            endpoint("timeout", None) if gateway else endpoint("skipped", None),
            endpoint("reply", 30),
        )
    elif invocation == 3:
        emit(
            interface_name, gateway, invocation,
            endpoint("reply", 20) if gateway else endpoint("skipped", None),
            endpoint("timeout", None),
        )
    elif invocation == 5:
        print('{"bad":1}', flush=True)
    else:
        base = invocation * 10
        emit(
            interface_name, gateway, invocation,
            endpoint("reply", base) if gateway else endpoint("skipped", None),
            endpoint("reply", base + 10),
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
