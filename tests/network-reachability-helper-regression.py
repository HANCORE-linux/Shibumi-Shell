#!/usr/bin/python3
"""Regression checks for the bounded native reachability probe helper."""

from __future__ import annotations

import importlib.machinery
import importlib.util
import io
import json
import os
import signal
import subprocess
import sys
import tempfile
import textwrap
import time
from pathlib import Path
from types import ModuleType

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT / "hancore.shibumi.network/scripts/network-reachability-probe"


def load_helper() -> ModuleType:
    loader = importlib.machinery.SourceFileLoader(
        "network_reachability_probe", str(HELPER)
    )
    spec = importlib.util.spec_from_loader(loader.name, loader)
    if spec is None:
        raise AssertionError("unable to load reachability helper")
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


def expect_probe_error(module: ModuleType, arguments: list[str]) -> None:
    try:
        module.parse_arguments(arguments)
    except module.ProbeError:
        return
    raise AssertionError(f"arguments unexpectedly accepted: {arguments!r}")


def executable(path: Path, source: str) -> Path:
    path.write_text(textwrap.dedent(source).lstrip(), encoding="utf-8")
    path.chmod(0o755)
    return path


def process_gone(pid: int) -> bool:
    stat = Path(f"/proc/{pid}/stat")
    if not stat.exists():
        return True
    try:
        fields = stat.read_text(encoding="ascii").split()
    except OSError:
        return True
    return len(fields) > 2 and fields[2] == "Z"


def wait_gone(pid: int, timeout: float = 3.0) -> bool:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if process_gone(pid):
            return True
        time.sleep(0.025)
    return process_gone(pid)


def main() -> int:
    module = load_helper()

    assert module.parse_arguments(
        ["--interface", "eth0", "--gateway", "192.0.2.1"]
    ) == ("eth0", "192.0.2.1")
    assert module.parse_arguments(
        ["--interface", "wlan0", "--gateway", "none"]
    ) == ("wlan0", "")
    assert module.parse_arguments(
        ["--interface", "enp5s0", "--gateway", "2001:db8::1"]
    ) == ("enp5s0", "2001:db8::1")
    for invalid in (
        [],
        ["--interface", "eth0", "--gateway"],
        ["--interface", "-I", "--gateway", "192.0.2.1"],
        ["--interface", "abcdefghijklmnop", "--gateway", "192.0.2.1"],
        ["--interface", "eth 0", "--gateway", "192.0.2.1"],
        ["--interface", "éth0", "--gateway", "192.0.2.1"],
        ["--interface", "eth0", "--gateway", "192.0.2.01"],
        ["--interface", "eth0", "--gateway", "2001:0db8::1"],
        ["--gateway", "192.0.2.1", "--interface", "eth0"],
        ["--interface", "eth0", "--gateway", "192.0.2.1", "extra"],
    ):
        expect_probe_error(module, invalid)

    with tempfile.TemporaryDirectory(prefix="shibumi-reachability-helper-") as raw:
        temporary = Path(raw)
        good_ping = executable(
            temporary / "ping-good",
            r"""
            #!/usr/bin/python3
            import os
            import sys
            if set(os.environ) - {"LANG", "LC_ALL", "PATH"}:
                raise SystemExit(2)
            target = sys.argv[-1]
            if target == "1.1.1.1":
                raise SystemExit(1)
            print("PING target (192.0.2.1) 56(84) bytes of data.")
            print("64 bytes: icmp_seq=1 ttl=64 time=4.250 ms")
            print("\n--- target ping statistics ---")
            print("1 packets transmitted, 1 received, 0% packet loss, time 0ms")
            print("rtt min/avg/max/mdev = 4.250/4.250/4.250/0.000 ms")
            """,
        )
        module.PING = str(good_ping)
        snapshot = module.build_snapshot("eth0", "192.0.2.1")
        assert snapshot["router"] == {"status": "reply", "latencyMs": 4.25}
        assert snapshot["internet"] == {"status": "timeout", "latencyMs": None}
        assert snapshot["interfaceName"] == "eth0"
        assert snapshot["gateway"] == "192.0.2.1"
        assert snapshot["internetTarget"] == "1.1.1.1"
        assert isinstance(snapshot["sampleMonotonicMs"], int)

        captured = io.BytesIO()

        class Output:
            buffer = captured

        original_stdout = module.sys.stdout
        module.sys.stdout = Output()
        try:
            module.emit(snapshot)
        finally:
            module.sys.stdout = original_stdout
        line = captured.getvalue()
        assert line.endswith(b"\n") and line.count(b"\n") == 1
        assert len(line) <= module.MAX_PROTOCOL_BYTES + 1
        record = json.loads(line.decode("utf-8"))
        assert record == {
            "schemaVersion": 1,
            "event": "snapshot",
            "sequence": 1,
            "snapshot": snapshot,
        }
        assert line[:-1] == json.dumps(
            record, ensure_ascii=False, separators=(",", ":"), sort_keys=True
        ).encode("utf-8")

        no_gateway = module.build_snapshot("wlan0", "")
        assert no_gateway["router"] == {"status": "skipped", "latencyMs": None}

        malformed_ping = executable(
            temporary / "ping-malformed",
            """
            #!/usr/bin/python3
            print("success without a canonical summary")
            """,
        )
        module.PING = str(malformed_ping)
        assert module.probe_target(
            "eth0", "192.0.2.1", time.monotonic() + 1
        ) == {"status": "error", "latencyMs": None}

        oversized_ping = executable(
            temporary / "ping-oversized",
            """
            #!/usr/bin/python3
            import os
            os.write(1, b"A" * 9000)
            """,
        )
        module.PING = str(oversized_ping)
        assert module.probe_target(
            "eth0", "192.0.2.1", time.monotonic() + 1
        ) == {"status": "error", "latencyMs": None}

        slow_ping = executable(
            temporary / "ping-slow",
            """
            #!/usr/bin/python3
            import time
            time.sleep(30)
            """,
        )
        module.PING = str(slow_ping)
        original_timeout = module.PROBE_TIMEOUT_SECONDS
        module.PROBE_TIMEOUT_SECONDS = 0.1
        try:
            started = time.monotonic()
            assert module.probe_target(
                "eth0", "192.0.2.1", time.monotonic() + 1
            ) == {"status": "error", "latencyMs": None}
            assert time.monotonic() - started < 1
        finally:
            module.PROBE_TIMEOUT_SECONDS = original_timeout

        module.PING = str(temporary / "missing-ping")
        assert module.probe_target(
            "eth0", "192.0.2.1", time.monotonic() + 1
        ) == {"status": "error", "latencyMs": None}

        pid_path = temporary / "resistant.pid"
        resistant_ping = executable(
            temporary / "ping-resistant",
            f"""
            #!/usr/bin/python3
            import os
            import signal
            import time
            open({str(pid_path)!r}, "w", encoding="ascii").write(str(os.getpid()))
            signal.signal(signal.SIGTERM, signal.SIG_IGN)
            time.sleep(30)
            """,
        )
        runner = temporary / "runner.py"
        runner.write_text(
            textwrap.dedent(
                f"""
                import importlib.machinery
                import importlib.util
                import sys
                import time
                sys.dont_write_bytecode = True
                loader = importlib.machinery.SourceFileLoader("probe", {str(HELPER)!r})
                spec = importlib.util.spec_from_loader(loader.name, loader)
                module = importlib.util.module_from_spec(spec)
                loader.exec_module(module)
                module.PING = {str(resistant_ping)!r}
                module.PROBE_TIMEOUT_SECONDS = 30
                module.probe_target("eth0", "192.0.2.1", time.monotonic() + 30)
                """
            ),
            encoding="utf-8",
        )
        supervisor = subprocess.Popen(
            [sys.executable, str(runner)],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        child_pid: int | None = None
        try:
            deadline = time.monotonic() + 3
            while not pid_path.exists() and time.monotonic() < deadline:
                time.sleep(0.025)
            assert pid_path.exists(), "resistant ping did not start"
            child_pid = int(pid_path.read_text(encoding="ascii"))
            os.kill(supervisor.pid, signal.SIGKILL)
            supervisor.wait(timeout=2)
            assert wait_gone(child_pid), "ping child survived supervisor SIGKILL"
        finally:
            if supervisor.poll() is None:
                supervisor.kill()
                supervisor.wait(timeout=2)
            if child_pid is not None and not process_gone(child_pid):
                try:
                    os.kill(child_pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                assert wait_gone(child_pid), "fixture cleanup could not kill ping child"

    print("network reachability helper regression passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
