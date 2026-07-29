import QtQuick
import Quickshell
import Quickshell.Io

Scope {
  id: root

  property int consumers: 0
  property var gpuTelemetry: null
  property var acquiredGpuTelemetry: null
  property int cpuTemperatureC: 0
  property int cpuCoreMaxTemperatureC: 0
  property int cpuTemperatureMaxC: 0
  property int cpuTemperatureCriticalC: 0
  property int nvmeTemperatureC: 0
  property int nvmeTemperatureMaxC: 0
  property int nvmeTemperatureCriticalC: 0
  property int memoryTemperatureC: 0
  readonly property int gpuTemperatureC: gpuTelemetry
    ? Number(gpuTelemetry.temperatureC || 0) : 0
  readonly property var temperatures: {
    const rows = []
    if (cpuTemperatureC > 0)
      rows.push({ id: "cpu", label: "CPU package",
        temperatureC: cpuTemperatureC, maximum: cpuTemperatureMaxC,
        critical: cpuTemperatureCriticalC })
    if (cpuCoreMaxTemperatureC > 0)
      rows.push({ id: "core", label: "Hottest CPU core",
        temperatureC: cpuCoreMaxTemperatureC, maximum: cpuTemperatureMaxC,
        critical: cpuTemperatureCriticalC })
    if (gpuTemperatureC > 0)
      rows.push({ id: "gpu", label: "GPU", temperatureC: gpuTemperatureC,
        maximum: 0, critical: 0 })
    if (nvmeTemperatureC > 0)
      rows.push({ id: "nvme", label: "NVMe composite",
        temperatureC: nvmeTemperatureC, maximum: nvmeTemperatureMaxC,
        critical: nvmeTemperatureCriticalC })
    if (memoryTemperatureC > 0)
      rows.push({ id: "memory", label: "Memory sensor",
        temperatureC: memoryTemperatureC, maximum: 0, critical: 0 })
    return rows
  }
  readonly property int maxTemperatureC: Math.max(cpuTemperatureC,
    cpuCoreMaxTemperatureC, gpuTemperatureC, nvmeTemperatureC,
    memoryTemperatureC)
  readonly property string temperatureSource:
    temperatures.length > 0 ? temperatures[0].label : ""

  function acquire() {
    consumers++
    if (consumers === 1) {
      syncGpuLease()
      refresh()
    }
  }

  function release() {
    consumers = Math.max(0, consumers - 1)
    syncGpuLease()
  }

  function refresh() {
    if (consumers > 0 && !probe.running) probe.running = true
  }

  function validTemperature(value) {
    const candidate = Math.round(Number(value))
    return Number.isFinite(candidate) && candidate > 0 && candidate <= 150
      ? candidate : 0
  }

  function parseDetailed(text) {
    const fields = String(text || "").trim().split("|")
    if (fields.length < 8) return false
    cpuTemperatureC = validTemperature(fields[0])
    cpuCoreMaxTemperatureC = validTemperature(fields[1])
    cpuTemperatureMaxC = validTemperature(fields[2])
    cpuTemperatureCriticalC = validTemperature(fields[3])
    nvmeTemperatureC = validTemperature(fields[4])
    nvmeTemperatureMaxC = validTemperature(fields[5])
    nvmeTemperatureCriticalC = validTemperature(fields[6])
    memoryTemperatureC = validTemperature(fields[7])
    return true
  }

  function parse(text) {
    const lines = String(text || "").trim().split("\n")
    let cpu = 0
    let core = 0
    let nvme = 0
    let memory = 0
    for (let index = 0; index < lines.length; index++) {
      const fields = lines[index].split("|")
      if (fields.length < 2) continue
      const value = validTemperature(fields[1])
      if (value <= 0) continue
      const label = String(fields[0] || "").toLowerCase()
      if (/core/.test(label)) core = Math.max(core, value)
      else if (/nvme|composite/.test(label)) nvme = Math.max(nvme, value)
      else if (/memory|dimm|jc42/.test(label)) memory = Math.max(memory, value)
      else if (/cpu|package|tctl|tdie|k10temp|coretemp/.test(label))
        cpu = Math.max(cpu, value)
      else cpu = Math.max(cpu, value)
    }
    cpuTemperatureC = cpu
    cpuCoreMaxTemperatureC = core
    nvmeTemperatureC = nvme
    memoryTemperatureC = memory
  }

  function sourceValid(source) {
    return ["cpu", "core", "gpu", "nvme", "memory"].indexOf(
      String(source || "")) >= 0
  }

  function temperatureFor(source) {
    const id = sourceValid(source) ? String(source) : "cpu"
    if (id === "core") return cpuCoreMaxTemperatureC
    if (id === "gpu") return gpuTemperatureC
    if (id === "nvme") return nvmeTemperatureC
    if (id === "memory") return memoryTemperatureC
    return cpuTemperatureC
  }

  function sourceLabel(source) {
    const id = sourceValid(source) ? String(source) : "cpu"
    if (id === "core") return "Hottest CPU core"
    if (id === "gpu") return "GPU"
    if (id === "nvme") return "NVMe"
    if (id === "memory") return "Memory"
    return "CPU package"
  }

  function sourceAvailable(source) {
    return temperatureFor(source) > 0
  }

  function syncGpuLease() {
    const wanted = consumers > 0 ? gpuTelemetry : null
    if (acquiredGpuTelemetry === wanted) return
    if (acquiredGpuTelemetry
        && typeof acquiredGpuTelemetry.release === "function")
      acquiredGpuTelemetry.release()
    acquiredGpuTelemetry = wanted
    if (acquiredGpuTelemetry
        && typeof acquiredGpuTelemetry.acquire === "function")
      acquiredGpuTelemetry.acquire()
  }

  Process {
    id: probe
    command: [
      "bash", "-c",
      "cpu=0; core=0; cpu_max=0; cpu_crit=0; "
        + "nvme=0; nvme_max=0; nvme_crit=0; dimm=0; "
        + "for d in /sys/class/hwmon/hwmon*; do "
        + "[[ -r $d/name ]] || continue; IFS= read -r name < \"$d/name\"; "
        + "case $name in coretemp|k10temp|zenpower|cpu_thermal) "
        + "for input in \"$d\"/temp*_input; do [[ -r $input ]] || continue; "
        + "IFS= read -r raw < \"$input\"; [[ $raw =~ ^[0-9]+$ ]] || continue; "
        + "label_file=${input%_input}_label; label=''; "
        + "[[ -r $label_file ]] && IFS= read -r label < \"$label_file\"; "
        + "value=$((raw / 1000)); case $label in "
        + "'Package id 0'|Tctl|Tdie|'CPU Package'|CPU) cpu=$value; "
        + "max_file=${input%_input}_max; crit_file=${input%_input}_crit; "
        + "[[ -r $max_file ]] && { IFS= read -r v < \"$max_file\"; "
        + "[[ $v =~ ^[0-9]+$ ]] && cpu_max=$((v / 1000)); }; "
        + "[[ -r $crit_file ]] && { IFS= read -r v < \"$crit_file\"; "
        + "[[ $v =~ ^[0-9]+$ ]] && cpu_crit=$((v / 1000)); };; "
        + "Core*) (( value > core )) && core=$value;; esac; "
        + "(( cpu == 0 )) && cpu=$value; done;; "
        + "nvme) for label_file in \"$d\"/temp*_label; do "
        + "[[ -r $label_file ]] || continue; IFS= read -r label < \"$label_file\"; "
        + "[[ $label == Composite ]] || continue; "
        + "input=${label_file%_label}_input; [[ -r $input ]] || continue; "
        + "IFS= read -r raw < \"$input\"; [[ $raw =~ ^[0-9]+$ ]] || continue; "
        + "nvme=$((raw / 1000)); max_file=${input%_input}_max; "
        + "crit_file=${input%_input}_crit; "
        + "[[ -r $max_file ]] && { IFS= read -r v < \"$max_file\"; "
        + "[[ $v =~ ^[0-9]+$ ]] && nvme_max=$((v / 1000)); }; "
        + "[[ -r $crit_file ]] && { IFS= read -r v < \"$crit_file\"; "
        + "[[ $v =~ ^[0-9]+$ ]] && nvme_crit=$((v / 1000)); }; break; done;; "
        + "jc42) for input in \"$d\"/temp*_input; do [[ -r $input ]] || continue; "
        + "IFS= read -r raw < \"$input\"; [[ $raw =~ ^[0-9]+$ ]] || continue; "
        + "value=$((raw / 1000)); (( value > dimm )) && dimm=$value; done;; "
        + "esac; done; "
        + "if (( cpu == 0 )); then for zone in /sys/class/thermal/thermal_zone*; do "
        + "[[ -r $zone/type && -r $zone/temp ]] || continue; "
        + "IFS= read -r type < \"$zone/type\"; "
        + "case $type in x86_pkg_temp|cpu-thermal|cpu_thermal) "
        + "IFS= read -r raw < \"$zone/temp\"; "
        + "[[ $raw =~ ^[0-9]+$ ]] && { cpu=$((raw / 1000)); break; };; esac; "
        + "done; fi; "
        + "printf '%s|%s|%s|%s|%s|%s|%s|%s\\n' "
        + "\"$cpu\" \"$core\" \"$cpu_max\" \"$cpu_crit\" "
        + "\"$nvme\" \"$nvme_max\" \"$nvme_crit\" \"$dimm\""
    ]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.parseDetailed(text)
    }
  }

  onGpuTelemetryChanged: syncGpuLease()
  Component.onDestruction: {
    consumers = 0
    syncGpuLease()
  }

  Timer {
    interval: 5000
    running: root.consumers > 0
    repeat: true
    onTriggered: root.refresh()
  }
}
