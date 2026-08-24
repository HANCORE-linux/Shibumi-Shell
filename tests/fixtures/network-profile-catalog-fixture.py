#!/usr/bin/python3

from __future__ import annotations

import json
from pathlib import Path
import sys
import time


def emit(value: dict[str, object]) -> None:
    print(json.dumps(value, ensure_ascii=False, separators=(",", ":")), flush=True)


def profile(
    uuid: str,
    name: str,
    ssid: str,
    security: str,
    enterprise: bool,
    invocation: int,
) -> dict[str, object]:
    return {
        "schemaVersion": 1,
        "uuid": uuid,
        "name": name,
        "profileType": "wifi",
        "ssid": ssid,
        "ssidHex": ssid.encode("utf-8").hex().upper(),
        "security": security,
        "enterprise": enterprise,
        "hidden": False,
        "autoconnect": True,
        "timestamp": invocation,
    }


def normal(invocation: int) -> None:
    rows = [
        profile(
            "11111111-1111-4111-8111-111111111111",
            "Personal fixture",
            "Cafe",
            "wpa-psk",
            False,
            invocation,
        ),
        profile(
            "22222222-2222-4222-8222-222222222222",
            "Enterprise Café 🚀",
            "Office🚀",
            "wpa-eap",
            True,
            invocation,
        ),
    ]
    emit({"schemaVersion": 1, "event": "begin", "sequence": 1, "count": 2})
    for index, row in enumerate(rows):
        emit({
            "schemaVersion": 1,
            "event": "profile",
            "sequence": index + 2,
            "index": index,
            "profile": row,
        })
    emit({"schemaVersion": 1, "event": "end", "sequence": 4, "count": 2})


def malformed(invocation: int) -> None:
    emit({"schemaVersion": 1, "event": "begin", "sequence": 1, "count": 1})
    row = profile(
        "33333333-3333-4333-8333-333333333333",
        "Malformed fixture",
        "Bad",
        "open",
        False,
        invocation,
    )
    row["identity"] = "must-not-cross-boundary"
    emit({
        "schemaVersion": 1,
        "event": "profile",
        "sequence": 2,
        "index": 0,
        "profile": row,
    })
    emit({"schemaVersion": 1, "event": "end", "sequence": 3, "count": 1})


def next_invocation(path: Path | None) -> int:
    if path is None:
        return 1
    try:
        value = int(path.read_text()) + 1
    except (FileNotFoundError, ValueError):
        value = 1
    path.write_text(str(value))
    return value


def main() -> int:
    mode = sys.argv[1] if len(sys.argv) > 1 else "normal"
    counter_path = Path(sys.argv[2]) if len(sys.argv) > 2 else None
    invocation = next_invocation(counter_path)
    if mode == "sequence":
        mode = {
            1: "normal", 2: "malformed", 3: "normal", 4: "slow",
            5: "normal", 6: "slow", 7: "normal", 8: "failed",
            9: "normal", 10: "normal",
        }.get(invocation, "unexpected")
    if mode == "normal":
        normal(invocation)
        return 0
    if mode == "malformed":
        malformed(invocation)
        return 0
    if mode == "slow":
        time.sleep(30)
        normal(invocation)
        return 0
    if mode == "failed":
        return 2
    return 3


if __name__ == "__main__":
    raise SystemExit(main())
