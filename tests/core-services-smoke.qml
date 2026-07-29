pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "telemetry" as Telemetry
import "cpu" as Cpu
import "powerstate" as PowerState

ShellRoot {
  id: root

  function check(condition, message) {
    if (!condition) throw new Error(message)
  }

  Telemetry.Service {
    id: telemetry
    shell: fakeShell
  }

  Cpu.Service {
    id: cpu
  }

  QtObject {
    id: fakeShell
    function serviceFor(pluginId) {
      return pluginId === "hancore.shibumi.cpu" ? cpu : null
    }
  }

  PowerState.Service {
    id: power
  }

  Timer {
    interval: 0
    running: true
    onTriggered: {
      root.check(telemetry.contractVersion === 1 && telemetry.ready,
        "telemetry contract is not ready")
      root.check(telemetry.system !== null && cpu.gpu !== null,
        "telemetry owners are missing")

      telemetry.system.parseMemory(
        "MemTotal: 8192000 kB\nMemAvailable: 4096000 kB\n"
        + "MemFree: 1024000 kB\nBuffers: 512000 kB\nCached: 2048000 kB\n")
      root.check(telemetry.system.memTotalMiB === 8000,
        "memory total parsing changed")
      root.check(telemetry.system.memAvailableMiB === 4000,
        "memory available parsing changed")
      root.check(telemetry.system.memPercent === 50,
        "memory utilization parsing changed")

      telemetry.system.previousCpuIdle = -1
      telemetry.system.previousCpuTotal = -1
      telemetry.system.parseCpu("cpu 100 0 100 800 0 0 0 0\n")
      telemetry.system.parseCpu("cpu 150 0 150 900 0 0 0 0\n")
      root.check(telemetry.system.cpuPercent === 50,
        "CPU delta parsing changed")

      cpu.gpu.parse("sysfs|42|61|0|0")
      root.check(cpu.gpu.backend === "sysfs"
        && cpu.gpu.utilization === 42
        && cpu.gpu.temperatureC === 61,
        "GPU parsing changed")

      telemetry.thermal.parseDetailed("55|63|80|100|44|70|90|39")
      root.check(telemetry.thermal.temperatureFor("cpu") === 55
        && telemetry.thermal.temperatureFor("core") === 63
        && telemetry.thermal.temperatureFor("gpu") === 61
        && telemetry.thermal.temperatureFor("nvme") === 44
        && telemetry.thermal.temperatureFor("memory") === 39,
        "temperature source selection changed")
      root.check(telemetry.thermal.sourceLabel("core") === "Hottest CPU core"
        && telemetry.thermal.sourceAvailable("gpu")
        && !telemetry.thermal.sourceValid("unsafe"),
        "temperature source metadata changed")
      telemetry.thermal.acquire()
      root.check(cpu.gpu.consumers === 1,
        "thermal GPU lease did not start")
      telemetry.thermal.release()
      root.check(cpu.gpu.consumers === 0,
        "thermal GPU lease did not balance")

      telemetry.system.acquire("cpu")
      telemetry.system.release("cpu")
      root.check(telemetry.system.cpuConsumers === 0,
        "CPU lease did not balance")
      cpu.gpu.acquire()
      cpu.gpu.release()
      root.check(cpu.gpu.consumers === 0,
        "GPU lease did not balance")

      root.check(power.contractVersion === 1 && power.ready,
        "power-state contract is not ready")
      power.profiles = ["power-saver", "balanced", "performance"]
      power.profilesReady = true
      power.activeProfile = "balanced"
      root.check(power.profileAvailable
        && power.activeProfileLabel === "Balanced"
        && power.activeProfileShortName === "BAL",
        "power-profile state changed")
      root.check(!power.setProfile("invalid"),
        "power service accepted an unknown profile")

      console.log("core services smoke passed")
      Qt.quit()
    }
  }
}
