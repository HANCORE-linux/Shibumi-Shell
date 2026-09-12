"""Resource probe run only by the maintained pinned-native Bubblewrap fixture.

This measures the actual production catalog owner and actual native listPlugins
IPC. It is isolated fixture evidence, not desktop or real-consumer acceptance.
"""
import json
import os
from pathlib import Path
import resource
import shutil
import signal
import statistics
import subprocess
import time

from lib.isolated_files import read_regular
from lib.isolated_process import finish_owned_group, run_bounded

BASE = Path("/fixture")
LIMIT = 1024 * 1024
DEADLINE = time.monotonic() + 38
NO_DEMAND_SETTLE_SECONDS = 2.5
NO_DEMAND_SECONDS = 1.0
NO_DEMAND_CPU_CEILING_SECONDS = 0.20
SLOW_FIRST_SECONDS = 5.35
# The production interval is 5s. A 0.5s observation allowance avoids a tiny
# scheduler threshold; the old timer queues during the controlled 5.35s read
# and therefore starts near drain rather than approaching this floor.
POST_DRAIN_FLOOR_SECONDS = 4.5
RELEASE_QUIET_SECONDS = 5.2
WARM_CYCLES = 3
# Calibrated positives retained 40/72 KiB over the pre-cycle baseline. A 512 KiB
# allowance covers allocator/QML jitter while rejecting a touched 2 MiB/cycle.
PSS_GROWTH_CEILING_KIB = 512
# Warm acquisitions include the host and every observed acquisition descendant.
# The allowance leaves headroom over calibrated positives but rejects a 1s burn
# in either QML or the launcher/custodian/IPC tree.
CYCLE_CPU_CEILING_SECONDS = 0.35
QUIET_CPU_WINDOW_SECONDS = 2.0
QUIET_CPU_CEILING_SECONDS = 0.75
MAX_PROCESSES = 128
MAX_PROC_FILE = 16384
MAX_CATALOG_PROCESSES = 3
CATALOG_LAUNCHER_PREFIX = ("/usr/bin/python3", "-I", "-S",
                           "/fixture/home/.config/omarchy/plugins/"
                           "hancore.shibumi.control-center/manager/shibumi-native-catalog",
                           "--shell", "/fixture/omarchy/shell", "--pid")
CATALOG_IPC_PREFIX = ("/usr/bin/quickshell", "ipc", "--pid")
CATALOG_IPC_SUFFIX = ("call", "--", "shell", "listPlugins")
TOPOLOGY_MEASUREMENTS = {"maximumCatalogProcesses": 0,
                         "maximumCatalogAcquisitionTrees": 0,
                         "completeTopologyChecks": 0,
                         "cleanupChecks": 0}
OBSERVED_CATALOG_DESCENDANTS = set()
OBSERVED_CUSTODIANS = set()
OBSERVED_IPCS = set()
CATALOG_CPU_TICKS = {}

shutil.copytree("/input", BASE, dirs_exist_ok=True, symlinks=True)
resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
resource.setrlimit(resource.RLIMIT_FSIZE, (16 * LIMIT, 16 * LIMIT))


def check(value, message):
    if not value:
        raise RuntimeError(message)


def bounded_at(directory, name, maximum=MAX_PROC_FILE):
    descriptor = os.open(name, os.O_RDONLY | os.O_CLOEXEC | os.O_NOFOLLOW,
                         dir_fd=directory)
    try:
        chunks = []
        total = 0
        while True:
            chunk = os.read(descriptor, min(4096, maximum - total + 1))
            if not chunk:
                return b"".join(chunks)
            chunks.append(chunk)
            total += len(chunk)
            check(total <= maximum, "proc identity field exceeded bound")
    finally:
        os.close(descriptor)


def parse_stat(raw):
    close = raw.rfind(b") ")
    check(close > 0, "malformed proc stat")
    fields = raw[close + 2:].split()
    check(len(fields) >= 20, "short proc stat")
    return {
        "state": fields[0].decode("ascii"),
        "ppid": int(fields[1]),
        "pgrp": int(fields[2]),
        "session": int(fields[3]),
        # Count only this process. cutime/cstime would duplicate child CPU when
        # every PID/starttime identity in the acquisition tree is summed.
        "cpuTicks": sum(int(fields[index]) for index in (11, 12)),
        "starttime": int(fields[19]),
    }


def process_record(pid):
    """Read one PID through a no-follow directory and rebind after cmdline."""
    try:
        directory = os.open("/proc/" + str(pid), os.O_RDONLY | os.O_DIRECTORY
                            | os.O_CLOEXEC | os.O_NOFOLLOW)
    except (FileNotFoundError, ProcessLookupError):
        return None
    try:
        before = parse_stat(bounded_at(directory, "stat", 4096))
        cmdline = tuple(part.decode("utf-8", errors="strict")
                        for part in bounded_at(directory, "cmdline").split(b"\0") if part)
        after = parse_stat(bounded_at(directory, "stat", 4096))
        check(after["starttime"] == before["starttime"],
              "proc identity changed during cmdline read")
        after.update({"pid": pid, "cmdline": cmdline})
        return after
    except (FileNotFoundError, ProcessLookupError):
        return None
    finally:
        os.close(directory)


def process_snapshot():
    names = [name for name in os.listdir("/proc") if name.isdigit()]
    check(len(names) <= MAX_PROCESSES, "process inventory exceeded fixture bound")
    records = {}
    for name in names:
        record = process_record(int(name))
        if record is not None:
            records[record["pid"]] = record
    # /proc is not an atomic inventory. Rebind every retained PID after the
    # first pass so an exited/pre-exec record cannot be combined with its later
    # tree state and mistaken for a simultaneously live fourth process.
    for pid, previous in tuple(records.items()):
        rebound = process_record(pid)
        if rebound is None or rebound["starttime"] != previous["starttime"]:
            records.pop(pid)
        else:
            records[pid] = rebound
    return records


def descendants(records, root_pid):
    selected = set()
    frontier = {root_pid}
    for _ in range(16):
        found = {pid for pid, row in records.items()
                 if row["ppid"] in frontier and pid not in selected and pid != root_pid}
        if not found:
            break
        selected.update(found)
        frontier = found
    else:
        raise RuntimeError("process ancestry depth exceeded fixture bound")
    return selected


def is_helper(row, host_pid):
    return row["cmdline"] == CATALOG_LAUNCHER_PREFIX + (str(host_pid),)


def is_catalog_ipc(row, host_pid):
    return row["cmdline"] == (CATALOG_IPC_PREFIX + (str(host_pid),)
                               + CATALOG_IPC_SUFFIX)


def catalog_topology(host_pid):
    """Prove one exact launcher -> setsid custodian -> exact IPC prefix.

    Every descendant under an observed launcher is tracked before classification;
    status IPC clients are probe siblings and cannot enter this host-owned tree.
    """
    records = process_snapshot()
    host_descendants = descendants(records, host_pid)
    launchers = {pid for pid in host_descendants
                 if records[pid]["ppid"] == host_pid
                 and (is_helper(records[pid], host_pid)
                      or (pid, records[pid]["starttime"])
                      in OBSERVED_CATALOG_DESCENDANTS)}
    matching = {pid for pid, row in records.items()
                if is_helper(row, host_pid) or is_catalog_ipc(row, host_pid)}
    current = set()
    custodians = set()
    ipcs = set()
    for launcher in launchers:
        tree = descendants(records, launcher)
        current.update(tree | {launcher})
        for pid in tree | {launcher}:
            OBSERVED_CATALOG_DESCENDANTS.add((pid, records[pid]["starttime"]))
        direct = {pid for pid in tree if records[pid]["ppid"] == launcher}
        if TOPOLOGY_MEASUREMENTS["completeTopologyChecks"] == 0:
            check(not any(is_catalog_ipc(records[pid], host_pid) for pid in direct),
                  "catalog IPC bypassed setsid custodian")
        candidate_custodians = {pid for pid in direct
                                if is_helper(records[pid], host_pid)
                                or (pid, records[pid]["starttime"]) in OBSERVED_CUSTODIANS
                                or (not records[pid]["cmdline"]
                                    and records[pid]["pgrp"] == pid
                                    and records[pid]["session"] == pid)}
        if not candidate_custodians and tree:
            if TOPOLOGY_MEASUREMENTS["completeTopologyChecks"] == 0:
                check(not any(is_catalog_ipc(records[pid], host_pid) for pid in tree),
                      "catalog IPC bypassed setsid custodian")
            continue
        check(len(candidate_custodians) <= 1,
              "catalog acquisition tree contained unclassified descendant")
        if not candidate_custodians:
            continue
        custodian = next(iter(candidate_custodians))
        custodians.add(custodian)
        custodian_tree = descendants(records, custodian)
        if (custodian_tree
                and TOPOLOGY_MEASUREMENTS["completeTopologyChecks"] == 0):
            check(records[custodian]["pgrp"] == custodian
                  and records[custodian]["session"] == custodian,
                  "catalog custodian did not create an owned session")
        candidate_ipcs = {pid for pid in custodian_tree
                          if is_catalog_ipc(records[pid], host_pid)
                          or (pid, records[pid]["starttime"]) in OBSERVED_IPCS}
        for pid in candidate_ipcs:
            if is_catalog_ipc(records[pid], host_pid):
                OBSERVED_IPCS.add((pid, records[pid]["starttime"]))
        # Popen briefly exposes its not-yet-execed child with the inherited
        # helper argv. It must become the one exact IPC before the proof passes.
        initializing = {pid for pid in custodian_tree
                        if is_helper(records[pid], host_pid)
                        and records[pid]["ppid"] == custodian
                        and records[pid]["pgrp"] == custodian
                        and records[pid]["session"] == custodian}
        if candidate_ipcs or initializing or records[custodian]["state"] == "Z":
            OBSERVED_CUSTODIANS.add((custodian, records[custodian]["starttime"]))
        unclassified = custodian_tree - candidate_ipcs - initializing
        for pid in candidate_ipcs:
            check(records[pid]["ppid"] == custodian
                  and records[pid]["pgrp"] == custodian
                  and records[pid]["session"] == custodian,
                  "catalog IPC bypassed setsid custodian")
        ipcs.update(candidate_ipcs)
        # All tree members, including transitional/unclassified observations,
        # remain in current and the pre-cgroup cleanup identity set.

    tracked_alive = {pid for pid, row in records.items()
                     if (pid, row["starttime"]) in OBSERVED_CATALOG_DESCENDANTS}
    check(not matching - current,
          "catalog acquisition identity escaped native host ancestry")
    draining_zombies = tracked_alive - current
    check(all(records[pid]["state"] == "Z" for pid in draining_zombies),
          "catalog observed descendant escaped acquisition tree")
    current.update(draining_zombies)
    for pid in current:
        row = records[pid]
        identity = (pid, row["starttime"])
        CATALOG_CPU_TICKS[identity] = max(
            row["cpuTicks"], CATALOG_CPU_TICKS.get(identity, 0))
    check(len(launchers) <= 1, "overlapping catalog acquisition trees")
    check(len(current) <= MAX_CATALOG_PROCESSES,
          "catalog acquisition exceeded three processes")
    TOPOLOGY_MEASUREMENTS["maximumCatalogProcesses"] = max(
        TOPOLOGY_MEASUREMENTS["maximumCatalogProcesses"], len(current))
    TOPOLOGY_MEASUREMENTS["maximumCatalogAcquisitionTrees"] = max(
        TOPOLOGY_MEASUREMENTS["maximumCatalogAcquisitionTrees"], len(launchers))
    return records, current, launchers, custodians, ipcs


def same_process(pid, starttime):
    current = process_record(pid)
    return current is not None and current["starttime"] == starttime


def pss_kib(pid, starttime):
    directory = os.open("/proc/" + str(pid), os.O_RDONLY | os.O_DIRECTORY
                        | os.O_CLOEXEC | os.O_NOFOLLOW)
    try:
        before = parse_stat(bounded_at(directory, "stat", 4096))
        check(before["starttime"] == starttime,
              "native host identity changed before PSS read")
        text = bounded_at(directory, "smaps_rollup", 65536).decode("ascii")
        after = parse_stat(bounded_at(directory, "stat", 4096))
        check(after["starttime"] == starttime,
              "native host identity changed during PSS read")
    finally:
        os.close(directory)
    values = [line.split() for line in text.splitlines() if line.startswith("Pss:")]
    check(len(values) == 1 and len(values[0]) == 3 and values[0][2] == "kB",
          "native host PSS shape changed")
    value = int(values[0][1])
    check(0 < value <= 512 * 1024, "native host PSS outside fixture cgroup ceiling")
    return value


def median_pss(pid, starttime):
    samples = []
    for _ in range(3):
        samples.append(pss_kib(pid, starttime))
        time.sleep(.05)
    return int(statistics.median(samples))


def cpu_seconds(pid, starttime):
    row = process_record(pid)
    check(row is not None and row["starttime"] == starttime,
          "native host identity changed before CPU read")
    return row["cpuTicks"] / float(os.sysconf("SC_CLK_TCK"))


def catalog_cpu_seconds():
    return sum(CATALOG_CPU_TICKS.values()) / float(os.sysconf("SC_CLK_TCK"))


def ipc(target, method, *args):
    remaining = DEADLINE - time.monotonic()
    check(remaining > 0, "catalog resource fixture deadline")
    result = run_bounded([
        "/usr/bin/quickshell", "ipc", "-p", "/fixture/omarchy/shell",
        "call", "--", target, method, *args,
    ], timeout=min(3, remaining), maximum=65536)
    return result.returncode, result.stdout.decode("utf-8", errors="strict").strip()


def status():
    code, text = ipc("native-catalog-probe", "status")
    check(code == 0 and text.startswith("{"), "catalog status unavailable")
    value = json.loads(text)
    check(isinstance(value, dict), "catalog status shape changed")
    return value


def wait_status(predicate, timeout=6):
    end = min(DEADLINE, time.monotonic() + timeout)
    while time.monotonic() < end:
        ended = os.waitid(os.P_PID, process.pid,
                          os.WEXITED | os.WNOHANG | os.WNOWAIT)
        check(ended is None, "native host exited during resource probe")
        catalog_topology(process.pid)
        code, text = ipc("native-catalog-probe", "status")
        catalog_topology(process.pid)
        if code == 0 and text.startswith("{"):
            value = json.loads(text)
            if isinstance(value, dict) and predicate(value):
                return value
        time.sleep(.03)
    raise RuntimeError("catalog resource status deadline")


def wait_no_catalog_processes(timeout=2):
    end = min(DEADLINE, time.monotonic() + timeout)
    while time.monotonic() < end:
        _, current, _, _, _ = catalog_topology(process.pid)
        if not current:
            TOPOLOGY_MEASUREMENTS["cleanupChecks"] += 1
            return
        time.sleep(.01)
    raise RuntimeError("catalog descendants remained after release")


def open_pidfd_exact(row):
    current = process_record(row["pid"])
    check(current is not None and current["starttime"] == row["starttime"],
          "catalog process identity changed before pidfd open")
    descriptor = os.pidfd_open(row["pid"], 0)
    rebound = process_record(row["pid"])
    if rebound is None or rebound["starttime"] != row["starttime"]:
        os.close(descriptor)
        raise RuntimeError("catalog process identity changed during pidfd open")
    return descriptor


def signal_pidfd(descriptor, signum):
    signal.pidfd_send_signal(descriptor, signum, None, 0)


def stop_pidfd(descriptor, pid, starttime):
    signal_pidfd(descriptor, signal.SIGSTOP)
    end = time.monotonic() + .05
    while time.monotonic() < end:
        stopped = process_record(pid)
        if (stopped is not None and stopped["starttime"] == starttime
                and stopped["state"] in ("T", "t")):
            return
        time.sleep(.001)
    raise RuntimeError("catalog helper could not be held for cadence control")


def continue_pidfd(descriptor):
    try:
        signal_pidfd(descriptor, signal.SIGCONT)
    except ProcessLookupError:
        pass


def stop_first_helper():
    end = min(DEADLINE, time.monotonic() + 2)
    while time.monotonic() < end:
        records, _, launchers, _, _ = catalog_topology(process.pid)
        if not launchers:
            time.sleep(.002)
            continue
        row = records[next(iter(launchers))]
        pid, starttime = row["pid"], row["starttime"]
        launcher_fd = open_pidfd_exact(row)
        custodian_fd = None
        ipc_fd = None
        success = False
        try:
            stop_pidfd(launcher_fd, pid, starttime)
            custodian_row = None
            # The child waits for the launcher's start ACK. Step the launcher in
            # short pidfd-controlled slices and hold both sides of the handshake.
            for _ in range(500):
                continue_pidfd(launcher_fd)
                time.sleep(.0002)
                stop_pidfd(launcher_fd, pid, starttime)
                records, _, _, custodians, ipcs = catalog_topology(process.pid)
                if custodians:
                    candidate = records[next(iter(custodians))]
                    if candidate["pgrp"] != candidate["pid"]:
                        continue
                    time.sleep(.003)
                    rebound = process_record(candidate["pid"])
                    if (rebound is None or rebound["starttime"] != candidate["starttime"]
                            or not is_helper(rebound, process.pid)):
                        catalog_topology(process.pid)
                        continue
                    custodian_row = rebound
                    OBSERVED_CUSTODIANS.add((candidate["pid"], candidate["starttime"]))
                    custodian_fd = open_pidfd_exact(custodian_row)
                    stop_pidfd(custodian_fd, custodian_row["pid"],
                               custodian_row["starttime"])
                    if ipcs:
                        ipc_fd = open_pidfd_exact(records[next(iter(ipcs))])
                    break
            check(custodian_row is not None, "catalog helper child tree was not observed")

            # Let the launcher send its ACK, then step only the custodian until
            # the exact IPC child is visible and can be identity-bound by pidfd.
            continue_pidfd(launcher_fd)
            for _ in range(500):
                if ipc_fd is None:
                    continue_pidfd(custodian_fd)
                    time.sleep(.0002)
                    stop_pidfd(custodian_fd, custodian_row["pid"],
                               custodian_row["starttime"])
                    records, _, _, _, ipcs = catalog_topology(process.pid)
                    if ipcs:
                        ipc_fd = open_pidfd_exact(records[next(iter(ipcs))])
                if ipc_fd is not None:
                    ipc_row = process_record(records[next(iter(ipcs))]["pid"])
                    check(ipc_row is not None, "catalog IPC disappeared before topology proof")
                    stop_pidfd(ipc_fd, ipc_row["pid"], ipc_row["starttime"])
                    records, current, launchers, custodians, ipcs = catalog_topology(process.pid)
                    check(len(current) == MAX_CATALOG_PROCESSES
                          and len(launchers) == len(custodians) == len(ipcs) == 1,
                          "catalog acquisition did not expose exact three-process topology")
                    TOPOLOGY_MEASUREMENTS["completeTopologyChecks"] += 1
                    stop_pidfd(launcher_fd, pid, starttime)
                    continue_pidfd(ipc_fd)
                    continue_pidfd(custodian_fd)
                    success = True
                    return pid, starttime, launcher_fd
            raise RuntimeError("exact catalog IPC child was not observed")
        finally:
            if not success:
                for descriptor in (ipc_fd, custodian_fd, launcher_fd):
                    if descriptor is not None:
                        continue_pidfd(descriptor)
            for descriptor in (ipc_fd, custodian_fd):
                if descriptor is not None:
                    os.close(descriptor)
            if not success:
                os.close(launcher_fd)
    raise RuntimeError("catalog helper was not observed")


def continue_exact(descriptor):
    continue_pidfd(descriptor)
    os.close(descriptor)


def verify_observed_descendants_drained(timeout=1.5):
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        alive = [(pid, starttime) for pid, starttime in OBSERVED_CATALOG_DESCENDANTS
                 if same_process(pid, starttime)]
        if not alive:
            TOPOLOGY_MEASUREMENTS["cleanupChecks"] += 1
            return
        time.sleep(.01)
    raise RuntimeError("observed catalog descendant survived inner cleanup")


def run_cadence(host_starttime):
    initial = status()
    check(initial["admitted"] and not initial["ready"]
          and not initial["nativeConstructed"] and not initial["refreshing"]
          and initial["requestSerial"] == 0,
          "undemanded catalog was not silent")
    settle_end = time.monotonic() + NO_DEMAND_SETTLE_SECONDS
    while time.monotonic() < settle_end:
        _, current, _, _, _ = catalog_topology(process.pid)
        check(not current, "catalog helper existed without demand")
        time.sleep(.02)
    idle_cpu = cpu_seconds(process.pid, host_starttime)
    idle_end = time.monotonic() + NO_DEMAND_SECONDS
    while time.monotonic() < idle_end:
        _, current, _, _, _ = catalog_topology(process.pid)
        check(not current, "catalog helper existed without demand")
        time.sleep(.02)
    no_demand_cpu = cpu_seconds(process.pid, host_starttime) - idle_cpu
    check(no_demand_cpu <= NO_DEMAND_CPU_CEILING_SECONDS,
          "undemanded native host exceeded CPU ceiling")
    quiet_initial = status()
    check(quiet_initial["requestSerial"] == 0
          and not quiet_initial["nativeConstructed"],
          "undemanded catalog started a request")

    check(ipc("native-catalog-probe", "acquire") == (0, "requested"),
          "catalog demand refused")
    held_pid, held_starttime, held_pidfd = stop_first_helper()
    held_until = time.monotonic() + SLOW_FIRST_SECONDS
    try:
        while time.monotonic() < held_until:
            _, _, launchers, _, _ = catalog_topology(process.pid)
            check(len(launchers) == 1, "held acquisition tree was not unique")
            time.sleep(.02)
    finally:
        continue_exact(held_pidfd)

    end = min(DEADLINE, time.monotonic() + 3)
    while same_process(held_pid, held_starttime) and time.monotonic() < end:
        catalog_topology(process.pid)
        time.sleep(.005)
    check(not same_process(held_pid, held_starttime),
          "cancelled first catalog helper did not drain")
    drain_observed_at = time.monotonic()

    second_started_at = None
    second = None
    end = min(DEADLINE, drain_observed_at + 6.2)
    while time.monotonic() < end:
        current = status()
        check(current["requestSerial"] <= 2,
              "catalog exceeded initial plus one post-drain request")
        catalog_topology(process.pid)
        if current["requestSerial"] == 2 and second_started_at is None:
            second_started_at = time.monotonic()
            check(second_started_at - drain_observed_at >= POST_DRAIN_FLOOR_SECONDS,
                  "catalog request started before five-second post-drain cadence")
        if (second_started_at is not None and current["ready"]
                and not current["refreshing"] and current["readSerial"] == 2):
            second = current
            break
        time.sleep(.04)
    check(second is not None, "post-drain catalog request did not settle")
    cadence_seconds = second_started_at - drain_observed_at

    check(ipc("native-catalog-probe", "release") == (0, "released"),
          "catalog release refused")
    released = wait_status(lambda value: not value["ready"]
                           and not value["refreshing"]
                           and not value["nativeConstructed"]
                           and value["snapshot"] is None)
    wait_no_catalog_processes()
    release_serial = released["requestSerial"]
    release_end = time.monotonic() + RELEASE_QUIET_SECONDS
    while time.monotonic() < release_end:
        _, current, _, _, _ = catalog_topology(process.pid)
        check(not current, "catalog descendant appeared after final release")
        time.sleep(.04)
    after_release = status()
    check(after_release["requestSerial"] == release_serial
          and not after_release["nativeConstructed"],
          "released catalog retained cadence work")
    return {
        "noDemandSettleSeconds": NO_DEMAND_SETTLE_SECONDS,
        "noDemandSeconds": NO_DEMAND_SECONDS,
        "noDemandCpuSeconds": round(no_demand_cpu, 4),
        "heldFirstRequestSeconds": SLOW_FIRST_SECONDS,
        "postDrainSecondRequestSeconds": round(cadence_seconds, 4),
        "requestSerialAfterRelease": release_serial,
        "releaseQuietSeconds": RELEASE_QUIET_SECONDS,
    }


def run_warm_cycles(host_starttime):
    pss = []
    cpu = []
    serials = []
    previous = status()["requestSerial"]
    baseline_pss = median_pss(process.pid, host_starttime)
    for _ in range(WARM_CYCLES):
        catalog_topology(process.pid)
        before_host_cpu = cpu_seconds(process.pid, host_starttime)
        before_catalog_cpu = catalog_cpu_seconds()
        check(ipc("native-catalog-probe", "acquire") == (0, "requested"),
              "warm catalog demand refused")
        ready = wait_status(lambda value: value["ready"] and not value["refreshing"]
                            and value["readSerial"] == previous + 1)
        check(ready["requestSerial"] == previous + 1,
              "warm cycle launched overlapping catalog requests")
        catalog_topology(process.pid)
        check(ipc("native-catalog-probe", "release") == (0, "released"),
              "warm catalog release refused")
        released = wait_status(lambda value: not value["ready"]
                               and not value["refreshing"]
                               and not value["nativeConstructed"])
        check(released["requestSerial"] == previous + 1,
              "warm release changed catalog cadence")
        wait_no_catalog_processes()
        time.sleep(.15)
        cycle_cpu = (cpu_seconds(process.pid, host_starttime) - before_host_cpu
                     + catalog_cpu_seconds() - before_catalog_cpu)
        check(cycle_cpu <= CYCLE_CPU_CEILING_SECONDS,
              "warm catalog cycle exceeded CPU ceiling")
        cpu.append(round(cycle_cpu, 4))
        pss.append(median_pss(process.pid, host_starttime))
        previous = released["requestSerial"]
        serials.append(previous)

    growth = max(0, max(pss) - baseline_pss)
    check(growth <= PSS_GROWTH_CEILING_KIB,
          "warm catalog cycles exceeded retained PSS ceiling: "
          f"baseline={baseline_pss} KiB samples={pss} growth={growth} KiB")
    quiet_before = cpu_seconds(process.pid, host_starttime)
    time.sleep(QUIET_CPU_WINDOW_SECONDS)
    quiet_cpu = cpu_seconds(process.pid, host_starttime) - quiet_before
    check(quiet_cpu <= QUIET_CPU_CEILING_SECONDS,
          "released native host consumed continuous CPU")
    wait_no_catalog_processes()
    return {
        "cycles": WARM_CYCLES,
        "requestSerials": serials,
        "baselinePssKiB": baseline_pss,
        "pssKiB": pss,
        "maximumPssOverBaselineKiB": growth,
        "cycleCpuSeconds": cpu,
        "releasedQuietWindowSeconds": QUIET_CPU_WINDOW_SECONDS,
        "releasedQuietCpuSeconds": round(quiet_cpu, 4),
    }


with (BASE / "native.log").open("xb") as log:
    process = subprocess.Popen([
        "/usr/bin/quickshell", "-p", "/fixture/omarchy/shell", "--no-color",
    ], stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
    try:
        wait_status(lambda value: value["admitted"], timeout=12)
        host = process_record(process.pid)
        check(host is not None
              and host["cmdline"] == ("/usr/bin/quickshell", "-p",
                                      "/fixture/omarchy/shell", "--no-color"),
              "native host process identity mismatch")
        cadence = run_cadence(host["starttime"])
        warm = run_warm_cycles(host["starttime"])
        measurements = {
            "cadence": cadence,
            "warm": warm,
            "processTopology": dict(TOPOLOGY_MEASUREMENTS),
            "ceilings": {
                "maximumCatalogProcesses": MAX_CATALOG_PROCESSES,
                "maximumCatalogAcquisitionTrees": 1,
                "postDrainCadenceFloorSeconds": POST_DRAIN_FLOOR_SECONDS,
                "noDemandCpuSeconds": NO_DEMAND_CPU_CEILING_SECONDS,
                "warmPssOverBaselineKiB": PSS_GROWTH_CEILING_KIB,
                "warmCycleCpuSeconds": CYCLE_CPU_CEILING_SECONDS,
                "releasedQuietCpuSeconds": QUIET_CPU_CEILING_SECONDS,
            },
        }
        print("NATIVE_CATALOG_RESOURCE_MEASUREMENTS "
              + json.dumps(measurements, sort_keys=True), flush=True)
        print("PINNED NATIVE CATALOG RESOURCE POSITIVE PASSED", flush=True)
    finally:
        finish_owned_group(process)
        log.flush()
        runtime_log = read_regular(BASE / "native.log", LIMIT).decode("utf-8", errors="replace")
        print("NATIVE_LOG_BEGIN\n" + runtime_log[-24000:] + "\nNATIVE_LOG_END", flush=True)
        check(not any(token in runtime_log for token in (
            "ERROR", "TypeError", "ReferenceError", "Binding loop", "Cannot assign",
            "Unable to assign", "Internal error")),
            "unexpected native/QML runtime failure")
        verify_observed_descendants_drained()
        print("PINNED NATIVE CATALOG RESOURCE INNER CLEANUP/LOG PASSED", flush=True)
