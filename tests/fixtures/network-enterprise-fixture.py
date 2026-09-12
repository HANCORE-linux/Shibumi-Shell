#!/usr/bin/python3
"""Deterministic stdin-only fixture for Enterprise dispatcher tests."""

from __future__ import annotations

import json
import os
import signal
import sys
import time
from pathlib import Path


def main() -> int:
    if len(sys.argv) not in {2, 3}:
        return 2
    output = Path(sys.argv[1])
    mode = sys.argv[2] if len(sys.argv) == 3 else "success"
    data = sys.stdin.buffer.read(8193)
    if len(data) > 8192 or data.count(b"\n") != 1 or not data.endswith(b"\n"):
        return 2
    try:
        request = json.loads(data[:-1].decode("utf-8", errors="strict"))
    except (UnicodeDecodeError, json.JSONDecodeError):
        return 2
    expected = {
        "deviceId", "entityId", "generation", "hardwareAddress", "identity", "interfaceName",
        "method", "password", "requestToken", "schemaVersion", "security",
        "serverDomain", "ssidHex",
    }
    if not isinstance(request, dict) or set(request) != expected:
        return 2
    sanitized = {
        "deviceId": request["deviceId"],
        "entityId": request["entityId"],
        "generation": request["generation"],
        "hardwareAddress": request["hardwareAddress"],
        "hasIdentity": bool(request["identity"]),
        "hasPassword": bool(request["password"]),
        "interfaceName": request["interfaceName"],
        "method": request["method"],
        "requestToken": request["requestToken"],
        "schemaVersion": request["schemaVersion"],
        "security": request["security"],
        "ssidHex": request["ssidHex"],
    }
    temporary = output.with_suffix(".tmp")
    temporary.write_text(
        json.dumps(sanitized, separators=(",", ":"), sort_keys=True) + "\n",
        encoding="utf-8",
    )
    os.replace(temporary, output)
    output.with_suffix(".pid").write_text(f"{os.getpid()}\n", encoding="ascii")
    if mode in {"success", "slow"}:
        record = {
            "event": "completion",
            "schemaVersion": 1,
            "sequence": 1,
            "snapshot": {
                "deviceId": request["deviceId"],
                "entityId": request["entityId"],
                "generation": request["generation"],
                "hardwareAddress": request["hardwareAddress"],
                "interfaceName": request["interfaceName"],
                "requestToken": request["requestToken"],
                "sampleMonotonicMs": int(time.monotonic() * 1000),
                "schemaVersion": 1,
                "security": request["security"],
                "ssidHex": request["ssidHex"],
                "status": "connected",
            },
        }
        print(json.dumps(record, separators=(",", ":"), sort_keys=True), flush=True)
    if mode == "slow":
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
        time.sleep(30)
    return 7 if mode == "fail" else 0


if __name__ == "__main__":
    raise SystemExit(main())
