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

      cpu.gpu.parse("sysfs|42|61|0|0\nstatus|ok")
      root.check(cpu.gpu.backend === "sysfs"
        && cpu.gpu.utilization === 42
        && cpu.gpu.temperatureC === 61,
        "GPU parsing changed")

      cpu.gpu.parse([
        "nvidia|52|63|2048|8192",
        "meta|NVIDIA GeForce RTX 2080 SUPER|nvidia|610.43.03",
        "proc|11|17|120|renderer",
        "proc|12|-1|940|electron",
        "proc|13|31|80|compute",
        "proc|14|4|300|shell",
        "status|ok"
      ].join("\n"))
      root.check(cpu.gpu.name === "NVIDIA GeForce RTX 2080 SUPER"
        && cpu.gpu.driverName === "nvidia"
        && cpu.gpu.driverVersion === "610.43.03"
        && cpu.gpu.topProcesses.length === 3
        && cpu.gpu.topProcesses[0].name === "compute"
        && cpu.gpu.topProcesses[1].name === "renderer"
        && cpu.gpu.topProcesses[2].name === "shell",
        "NVIDIA model, driver, or top-process parsing changed")

      cpu.gpu.previousProcessCounters = ({ "21": 100000000 })
      cpu.gpu.previousProcessEpoch = Date.now() - 1000
      cpu.gpu.parse([
        "sysfs|38|54|0|0",
        "meta|AMD Radeon RX 7900 XTX|amdgpu|",
        "counter|21|600000000|512|game",
        "status|ok"
      ].join("\n"))
      root.check(cpu.gpu.name === "AMD Radeon RX 7900 XTX"
        && cpu.gpu.driverName === "amdgpu"
        && cpu.gpu.topProcesses.length === 1
        && cpu.gpu.topProcesses[0].percent >= 49
        && cpu.gpu.topProcesses[0].percent <= 50,
        "AMD DRM process-counter parsing changed")

      cpu.gpu.previousProcessCounters = ({ "31": 300000000 })
      cpu.gpu.previousProcessEpoch = Date.now() - 1000
      cpu.gpu.parse([
        "sysfs|29|48|0|0",
        "meta|Intel Arc A770|xe|",
        "counter|31|550000000|256|compositor",
        "status|ok"
      ].join("\n"))
      root.check(cpu.gpu.name === "Intel Arc A770"
        && cpu.gpu.driverName === "xe"
        && cpu.gpu.topProcesses.length === 1
        && cpu.gpu.topProcesses[0].percent >= 24
        && cpu.gpu.topProcesses[0].percent <= 25,
        "Intel DRM process-counter parsing changed")

      cpu.gpu.parse("sysfs|42|61|0|0\nstatus|ok")

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
      cpu.gpu.acquireDetails()
      root.check(cpu.gpu.detailsConsumers === 1 && !cpu.gpu.detailsReady,
        "GPU detail lease did not start cleanly")
      cpu.gpu.parse([
        "nvidia|12|45|256|8192",
        "meta|Fixture GPU|nvidia|1.0",
        "proc|41|8|64|fixture",
        "status|ok"
      ].join("\n"), true)
      root.check(cpu.gpu.detailsReady
        && cpu.gpu.topProcesses.length === 1,
        "GPU detail sample did not become ready")
      cpu.gpu.parse("", true)
      root.check(cpu.gpu.detailsFailed && cpu.gpu.probeFailed
        && cpu.gpu.topProcesses.length === 1,
        "failed GPU probe replaced the last complete detail sample")
      cpu.gpu.releaseDetails()
      root.check(cpu.gpu.detailsConsumers === 0
        && !cpu.gpu.detailsReady
        && cpu.gpu.topProcesses.length === 0,
        "GPU detail lease did not clear transient state")
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
