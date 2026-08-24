#!/usr/bin/python3

from __future__ import annotations

import json
from pathlib import Path
import signal
import sys
import time


def snapshot(invocation: int, connected: bool = True) -> dict[str, object]:
    if not connected:
        return {
            "schemaVersion": 1,
            "connected": False,
            "connectionUuid": "",
            "connectionName": "",
            "kind": "none",
            "interfaceName": "",
            "hardwareAddress": "",
            "metered": "unknown",
            "addresses": [],
            "gateways": [],
            "dnsServers": [],
            "dnsDomains": [],
            "rxBytes": 0,
            "txBytes": 0,
            "sampleMonotonicMs": invocation * 1000,
            "wifi": {
                "ssid": "", "ssidHex": "", "signal": 0,
                "frequencyMhz": 0, "bitrateKbps": 0,
            },
            "wired": {"speedMbps": 0, "carrier": False},
        }
    counters = {
        1: (1000, 2000, 1000),
        2: (3000, 5000, 2000),
        6: (4000, 7000, 3000),
        8: (5000, 9000, 4000),
    }
    rx_bytes, tx_bytes, sample_ms = counters.get(
        invocation, (invocation * 1000, invocation * 2000, invocation * 1000)
    )
    return {
        "schemaVersion": 1,
        "connected": True,
        "connectionUuid": "11111111-2222-4333-8444-555555555555",
        "connectionName": "Wired Café 🚀",
        "kind": "wired",
        "interfaceName": "eth0",
        "hardwareAddress": "02:00:00:00:00:07",
        "metered": "no",
        "addresses": [
            {"family": "ipv4", "address": "192.0.2.10", "prefix": 24},
            {"family": "ipv6", "address": "2001:db8::10", "prefix": 64},
        ],
        "gateways": [
            {"family": "ipv4", "address": "192.0.2.1"},
            {"family": "ipv6", "address": "2001:db8::1"},
        ],
        "dnsServers": [
            {"family": "ipv4", "address": "192.0.2.53"},
            {"family": "ipv6", "address": "2001:db8::53"},
        ],
        "dnsDomains": ["example.invalid"],
        "rxBytes": rx_bytes,
        "txBytes": tx_bytes,
        "sampleMonotonicMs": sample_ms,
        "wifi": {
            "ssid": "", "ssidHex": "", "signal": 0,
            "frequencyMhz": 0, "bitrateKbps": 0,
        },
        "wired": {"speedMbps": 1000, "carrier": True},
    }


def emit(value: dict[str, object]) -> None:
    print(json.dumps(value, ensure_ascii=False, separators=(",", ":")), flush=True)


def next_invocation(path: Path) -> int:
    try:
        value = int(path.read_text()) + 1
    except (FileNotFoundError, ValueError):
        value = 1
    path.write_text(str(value))
    return value


def main() -> int:
    if len(sys.argv) not in {2, 3}:
        return 3
    invocation = next_invocation(Path(sys.argv[1]))
    mode = sys.argv[2] if len(sys.argv) == 3 else "sequence"
    if mode == "delayed-exit":
        def delayed_exit(_signum: int, _frame: object) -> None:
            time.sleep(0.35)
            raise SystemExit(0)
        signal.signal(signal.SIGTERM, delayed_exit)
        emit({
            "schemaVersion": 1, "event": "snapshot", "sequence": 1,
            "snapshot": snapshot(invocation),
        })
        time.sleep(30)
        return 0
    if mode == "rate-boundary":
        value = snapshot(invocation)
        samples = {
            1: (0, 1000),
            2: (9007199254740991, 2000),
            3: (0, 3000),
            4: (9007199254740991, 3001),
        }
        value["rxBytes"], value["sampleMonotonicMs"] = samples.get(
            invocation, (0, invocation * 1000)
        )
        value["txBytes"] = 0
        emit({
            "schemaVersion": 1, "event": "snapshot", "sequence": 1,
            "snapshot": value,
        })
        return 0
    if invocation == 3:
        value = snapshot(invocation)
        value["backendPath"] = "/forbidden"
        emit({
            "schemaVersion": 1, "event": "snapshot", "sequence": 1,
            "snapshot": value,
        })
        return 0
    if invocation == 4:
        value = snapshot(invocation, connected=False)
    elif invocation == 5:
        emit({
            "schemaVersion": 1, "event": "snapshot", "sequence": 1,
            "snapshot": snapshot(invocation),
        })
        time.sleep(30)
        return 0
    elif invocation == 7:
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
        emit({
            "schemaVersion": 1, "event": "snapshot", "sequence": 1,
            "snapshot": snapshot(invocation),
        })
        time.sleep(30)
        return 0
    else:
        value = snapshot(invocation)
    emit({
        "schemaVersion": 1,
        "event": "snapshot",
        "sequence": 1,
        "snapshot": value,
    })
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
