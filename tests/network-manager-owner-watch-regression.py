#!/usr/bin/python3
"""Exercise the owner watcher against an isolated, disposable D-Bus daemon."""

from __future__ import annotations

import json
import os
from pathlib import Path
import runpy
import select
import subprocess
import sys
import time

import dbus

ROOT = Path(__file__).resolve().parents[1]
WATCHER = ROOT / "hancore.shibumi.network/scripts/network-manager-owner-watch"
SERVICE = "org.freedesktop.NetworkManager"
TIMEOUT = 5.0


def read_line(stream: object, label: str) -> str:
    ready, _, _ = select.select([stream], [], [], TIMEOUT)
    if not ready:
        raise AssertionError(f"timed out waiting for {label}")
    line = stream.readline()
    if not line:
        raise AssertionError(f"{label} closed unexpectedly")
    return line.rstrip("\n")


def child_pids(parent_pid: int) -> list[int]:
    path = Path(f"/proc/{parent_pid}/task/{parent_pid}/children")
    try:
        return [int(value) for value in path.read_text().split()]
    except (FileNotFoundError, ProcessLookupError):
        return []


def record(stream: object, expected_event: str, sequence: int) -> dict[str, object]:
    line = read_line(stream, "watcher protocol")
    if len(line) > 256 or line.strip() != line:
        raise AssertionError(f"unbounded or non-canonical protocol line: {line!r}")
    value = json.loads(line)
    if value.get("schemaVersion") != 1 or value.get("event") != expected_event:
        raise AssertionError(f"unexpected watcher event: {value!r}")
    if value.get("sequence") != sequence:
        raise AssertionError(f"unexpected watcher sequence: {value!r}")
    expected_keys = {"schemaVersion", "event", "sequence", "present"}
    if expected_event == "owner":
        expected_keys.add("replacement")
    if set(value) != expected_keys:
        raise AssertionError(f"unexpected watcher fields: {value!r}")
    return value


def main() -> int:
    namespace = runpy.run_path(str(WATCHER))
    protocol = namespace["OwnerProtocol"]()
    if protocol.ingest(namespace["INTRO"]) is not None:
        raise AssertionError("monitor intro emitted a protocol record")
    initial_direct = protocol.ingest(
        namespace["OWNED_PREFIX"] + ":1.100"
    )
    replacement_direct = protocol.ingest(
        namespace["OWNED_PREFIX"] + ":1.101"
    )
    if (initial_direct is None or initial_direct["event"] != "snapshot"
            or replacement_direct is None
            or replacement_direct["event"] != "owner"
            or replacement_direct["present"] is not True
            or replacement_direct["replacement"] is not True):
        raise AssertionError("direct owner replacement was not explicit")

    daemon = subprocess.Popen(
        ["dbus-daemon", "--session", "--nofork", "--print-address=1"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        bufsize=1,
    )
    watcher: subprocess.Popen[str] | None = None
    abrupt_watcher: subprocess.Popen[str] | None = None
    first: dbus.bus.BusConnection | None = None
    second: dbus.bus.BusConnection | None = None
    try:
        assert daemon.stdout is not None
        address = read_line(daemon.stdout, "private bus address")
        environment = dict(os.environ)
        environment["DBUS_SYSTEM_BUS_ADDRESS"] = address
        watcher = subprocess.Popen(
            [sys.executable, str(WATCHER)],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            bufsize=1,
            env=environment,
        )
        assert watcher.stdout is not None

        initial = record(watcher.stdout, "snapshot", 1)
        if initial["present"] is not False:
            raise AssertionError(f"initial absent owner was actionable: {initial!r}")

        first = dbus.bus.BusConnection(address)
        first.request_name(
            SERVICE,
            dbus.bus.NAME_FLAG_ALLOW_REPLACEMENT
            | dbus.bus.NAME_FLAG_DO_NOT_QUEUE,
        )
        acquired = record(watcher.stdout, "owner", 2)
        if acquired["present"] is not True or acquired["replacement"] is not False:
            raise AssertionError(f"acquisition was misclassified: {acquired!r}")

        first.release_name(SERVICE)
        first_loss = record(watcher.stdout, "owner", 3)
        if first_loss["present"] is not False or first_loss["replacement"] is not False:
            raise AssertionError(f"first loss was misclassified: {first_loss!r}")

        second = dbus.bus.BusConnection(address)
        second.request_name(SERVICE, dbus.bus.NAME_FLAG_DO_NOT_QUEUE)
        second_acquire = record(watcher.stdout, "owner", 4)
        if (second_acquire["present"] is not True
                or second_acquire["replacement"] is not False):
            raise AssertionError(f"second acquisition was misclassified: {second_acquire!r}")

        second.release_name(SERVICE)
        lost = record(watcher.stdout, "owner", 5)
        if lost["present"] is not False or lost["replacement"] is not False:
            raise AssertionError(f"loss was misclassified: {lost!r}")

        first.request_name(
            SERVICE,
            dbus.bus.NAME_FLAG_ALLOW_REPLACEMENT
            | dbus.bus.NAME_FLAG_DO_NOT_QUEUE,
        )
        reacquired = record(watcher.stdout, "owner", 6)
        if reacquired["present"] is not True or reacquired["replacement"] is not False:
            raise AssertionError(f"reacquisition was misclassified: {reacquired!r}")

        abrupt_watcher = subprocess.Popen(
            [sys.executable, str(WATCHER)],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            bufsize=1,
            env=environment,
        )
        assert abrupt_watcher.stdout is not None
        abrupt_initial = record(abrupt_watcher.stdout, "snapshot", 1)
        if abrupt_initial["present"] is not True:
            raise AssertionError("abrupt watcher did not observe current owner")
        child_deadline = time.monotonic() + TIMEOUT
        children: list[int] = []
        while time.monotonic() < child_deadline:
            children = child_pids(abrupt_watcher.pid)
            if children:
                break
            time.sleep(0.02)
        if len(children) != 1:
            raise AssertionError(f"watcher child inventory was not singular: {children!r}")
        monitor_pid = children[0]
        abrupt_watcher.kill()
        abrupt_watcher.wait(timeout=TIMEOUT)
        exit_deadline = time.monotonic() + 2.0
        while Path(f"/proc/{monitor_pid}").exists() and time.monotonic() < exit_deadline:
            time.sleep(0.02)
        if Path(f"/proc/{monitor_pid}").exists():
            raise AssertionError("SIGKILL left the gdbus monitor orphaned")

        daemon.terminate()
        daemon.wait(timeout=TIMEOUT)
        watcher.wait(timeout=TIMEOUT)
        if watcher.returncode == 0:
            raise AssertionError("system-bus disconnect was reported as success")

        print("network manager owner watcher regression passed")
        return 0
    finally:
        for connection in (second, first):
            if connection is not None:
                try:
                    connection.close()
                except Exception:
                    pass
        if abrupt_watcher is not None and abrupt_watcher.poll() is None:
            abrupt_watcher.kill()
            abrupt_watcher.wait(timeout=TIMEOUT)
        if watcher is not None and watcher.poll() is None:
            watcher.terminate()
            try:
                watcher.wait(timeout=TIMEOUT)
            except subprocess.TimeoutExpired:
                watcher.kill()
                watcher.wait(timeout=TIMEOUT)
        if daemon.poll() is None:
            daemon.terminate()
            try:
                daemon.wait(timeout=TIMEOUT)
            except subprocess.TimeoutExpired:
                daemon.kill()
                daemon.wait(timeout=TIMEOUT)


if __name__ == "__main__":
    raise SystemExit(main())
