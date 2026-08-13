#!/usr/bin/env python3
"""Run one Omarchy speed-test phase with crash-safe group cleanup."""

from __future__ import annotations

import os
import select
import signal
import subprocess
import sys
import time


def group_exists(process_group: int) -> bool:
    try:
        os.killpg(process_group, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    return True


def terminate_group(
    process_group: int,
    leader: subprocess.Popen[bytes] | None = None,
    grace_seconds: float = 2.0,
) -> None:
    if not group_exists(process_group):
        return
    try:
        os.killpg(process_group, signal.SIGTERM)
    except ProcessLookupError:
        return

    deadline = time.monotonic() + grace_seconds
    while time.monotonic() < deadline:
        if leader is not None:
            leader.poll()
        if not group_exists(process_group):
            return
        time.sleep(0.05)

    try:
        os.killpg(process_group, signal.SIGKILL)
    except ProcessLookupError:
        return

    kill_deadline = time.monotonic() + 1.0
    while time.monotonic() < kill_deadline:
        if leader is not None:
            leader.poll()
        if not group_exists(process_group):
            return
        time.sleep(0.02)


def supervise_worker(
    executable: str,
    phase: str,
    control_fd: int,
    status_fd: int,
) -> None:
    worker: subprocess.Popen[bytes] | None = None
    exit_code = 127
    try:
        try:
            worker = subprocess.Popen(
                [executable, phase],
                start_new_session=True,
                close_fds=True,
            )
        except OSError as error:
            print(f"Unable to start network speed test: {error}", file=sys.stderr)
            return

        while True:
            if worker.poll() is not None:
                exit_code = worker.returncode
                terminate_group(worker.pid, worker)
                return
            readable, _, _ = select.select([control_fd], [], [], 0.1)
            if readable and os.read(control_fd, 1) == b"":
                terminate_group(worker.pid, worker)
                try:
                    exit_code = worker.wait(timeout=1.0)
                except subprocess.TimeoutExpired:
                    exit_code = -signal.SIGKILL
                return
    finally:
        if worker is not None:
            terminate_group(worker.pid, worker)
            if worker.poll() is None:
                worker.kill()
            try:
                worker.wait(timeout=1.0)
            except subprocess.TimeoutExpired:
                pass
        try:
            os.write(status_fd, f"{exit_code}\n".encode())
        except BrokenPipeError:
            pass
        os.close(control_fd)
        os.close(status_fd)


def main() -> int:
    if len(sys.argv) != 3 or sys.argv[2] not in {"down", "up"}:
        print("Usage: InlineSpeedTestRunner.py COMMAND [down|up]", file=sys.stderr)
        return 2

    control_read, control_write = os.pipe()
    status_read, status_write = os.pipe()
    supervisor_pid = os.fork()
    if supervisor_pid == 0:
        os.close(control_write)
        os.close(status_read)
        os.setsid()
        try:
            supervise_worker(sys.argv[1], sys.argv[2], control_read, status_write)
        finally:
            os._exit(0)

    os.close(control_read)
    os.close(status_write)
    stopping = False

    def request_stop(_signum: int, _frame: object) -> None:
        nonlocal stopping, control_write
        stopping = True
        if control_write >= 0:
            os.close(control_write)
            control_write = -1

    signal.signal(signal.SIGTERM, request_stop)
    signal.signal(signal.SIGINT, request_stop)

    status = b""
    try:
        while b"\n" not in status:
            chunk = os.read(status_read, 64)
            if not chunk:
                break
            status += chunk
    finally:
        if control_write >= 0:
            os.close(control_write)
        os.close(status_read)
        try:
            os.waitpid(supervisor_pid, 0)
        except ChildProcessError:
            pass

    try:
        exit_code = int(status.splitlines()[0])
    except (IndexError, ValueError):
        return 1
    if stopping and exit_code < 0:
        return 0
    return exit_code if exit_code >= 0 else 128 + abs(exit_code)


if __name__ == "__main__":
    raise SystemExit(main())
