#!/usr/bin/python3

from __future__ import annotations

import json
import os
from pathlib import Path
import signal
import sys
import time


def main() -> int:
    mode = sys.argv[1] if len(sys.argv) > 1 else "complete"
    line = sys.stdin.buffer.readline(4097)
    try:
        request = json.loads(line.decode("utf-8", errors="strict"))
    except (UnicodeDecodeError, json.JSONDecodeError):
        return 2
    if mode == "fail":
        return 7
    if mode == "slow":
        if len(sys.argv) > 2:
            Path(sys.argv[2]).write_text(f"{os.getpid()}\n", encoding="ascii")
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
        time.sleep(30)
        return 0
    completion = {
        "schemaVersion": 1,
        "status": "completed",
        "action": request["action"],
        "requestToken": request["requestToken"],
        "uuid": request["uuid"],
        "deviceId": request["deviceId"],
        "interfaceName": request["interfaceName"],
        "hardwareAddress": request["hardwareAddress"],
        "generation": request["generation"],
    }
    print(json.dumps(completion, separators=(",", ":")), flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
