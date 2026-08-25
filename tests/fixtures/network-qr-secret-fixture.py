#!/usr/bin/python3

from __future__ import annotations

import json
import sys
import time


def main() -> int:
    mode = sys.argv[1] if len(sys.argv) > 1 else "success"
    raw = sys.stdin.buffer.readline(4097)
    if len(raw) > 4096 or not raw.endswith(b"\n"):
        return 2
    request = json.loads(raw)
    if mode == "slow":
        time.sleep(30)
        return 0
    if mode == "fail":
        return 2
    result = {
        "schemaVersion": 1,
        "status": "completed",
        "requestToken": request["requestToken"],
        "networkId": request["networkId"],
        "profileUuid": request["profileUuid"],
        "deviceId": request["deviceId"],
        "interfaceName": request["interfaceName"],
        "hardwareAddress": request["hardwareAddress"],
        "ssidHex": request["ssidHex"],
        "security": request["security"],
        "generation": request["generation"],
        "psk": "correct horse",
    }
    line = json.dumps(result, separators=(",", ":"))
    if mode == "malformed":
        line += " trailing"
    if mode == "chunked":
        middle = len(line) // 2
        sys.stdout.write(line[:middle])
        sys.stdout.flush()
        time.sleep(0.05)
        sys.stdout.write(line[middle:] + "\n")
        sys.stdout.flush()
        return 0
    print(line, flush=True)
    if mode == "extra":
        print("{}", flush=True)
    if mode == "delayed-exit":
        time.sleep(0.3)
    return 2 if mode == "nonzero" else 0


if __name__ == "__main__":
    raise SystemExit(main())
