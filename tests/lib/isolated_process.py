"""Bounded capture and cleanup of a subprocess owned by an isolated fixture."""
import math
import os
import selectors
import signal
import subprocess
import time


def observe_owned_exit(process, deadline):
    """Observe an exclusively owned leader without releasing its PID/PGID."""
    if process.returncode is not None:
        raise RuntimeError("owned process leader was already reaped")
    while True:
        result = os.waitid(os.P_PID, process.pid,
            os.WEXITED | os.WNOHANG | os.WNOWAIT)
        if result is not None:
            return result.si_status if result.si_code == os.CLD_EXITED else -result.si_status
        if time.monotonic() >= deadline:
            raise RuntimeError("owned process deadline")
        time.sleep(.01)


def finish_owned_group(process):
    """Kill the reserved group, then reap. Requires start_new_session=True.

    The caller must retain exclusive wait ownership; an already reaped leader
    refuses before any signal rather than trusting a reusable numeric PGID.
    """
    if process.returncode is not None:
        raise RuntimeError("owned process leader was already reaped")
    os.waitid(os.P_PID, process.pid, os.WEXITED | os.WNOHANG | os.WNOWAIT)
    if os.getpgid(process.pid) != process.pid:
        raise RuntimeError("owned process is not its group leader")
    try:
        os.killpg(process.pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    process.wait(timeout=1)


def run_bounded(command, *, env=None, cwd=None, timeout=4, maximum=65536, pass_fds=()):
    if (type(timeout) not in (int, float) or not math.isfinite(timeout)
            or not 0 < timeout <= 120 or type(maximum) is not int
            or not 0 <= maximum <= 4 * 1024 * 1024):
        raise ValueError("invalid owned-process bounds")
    process = subprocess.Popen(command, env=env, cwd=cwd, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, start_new_session=True, pass_fds=pass_fds)
    selector = selectors.DefaultSelector()
    output = {"stdout": bytearray(), "stderr": bytearray()}
    deadline = time.monotonic() + timeout
    size = 0
    try:
        selector.register(process.stdout, selectors.EVENT_READ, "stdout")
        selector.register(process.stderr, selectors.EVENT_READ, "stderr")
        while selector.get_map():
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise RuntimeError("owned process deadline: " + str(command[0]))
            for key, _ in selector.select(min(.1, remaining)):
                data = os.read(key.fd, min(65536, maximum - size + 1))
                if not data:
                    selector.unregister(key.fileobj)
                    continue
                size += len(data)
                if size > maximum:
                    raise RuntimeError("owned process output limit: " + str(command[0]))
                output[key.data].extend(data)
        # Observe exit without reaping. Keeping the owned leader's PID reserved
        # prevents process-group ID reuse before descendant cleanup below.
        observe_owned_exit(process, deadline)
    finally:
        selector.close()
        process.stdout.close()
        process.stderr.close()
        finish_owned_group(process)
    return subprocess.CompletedProcess(command, process.returncode,
        bytes(output["stdout"]), bytes(output["stderr"]))
