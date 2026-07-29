import QtQuick
import Quickshell
import Quickshell.Io

Scope {
  id: root

  property int consumers: 0
  property string backend: ""
  property int utilization: 0
  property int temperatureC: 0
  property int memoryUsedMiB: 0
  property int memoryTotalMiB: 0
  readonly property bool available: backend !== ""
  readonly property int intervalMs: 1500

  function acquire() {
    consumers++
    if (consumers === 1) refresh()
  }

  function release() {
    consumers = Math.max(0, consumers - 1)
    if (consumers === 0) probe.running = false
  }

  function refresh() {
    if (consumers <= 0 || probe.running) return
    probe.running = true
  }

  function parse(line) {
    const fields = String(line || "").trim().split("|")
    if (fields.length < 5 || fields[0] === "none") {
      backend = ""
      utilization = 0
      temperatureC = 0
      memoryUsedMiB = 0
      memoryTotalMiB = 0
      return
    }

    backend = fields[0]
    utilization = Math.max(0, Math.min(100, parseInt(fields[1]) || 0))
    temperatureC = Math.max(0, parseInt(fields[2]) || 0)
    memoryUsedMiB = Math.max(0, parseInt(fields[3]) || 0)
    memoryTotalMiB = Math.max(0, parseInt(fields[4]) || 0)
  }

  Process {
    id: probe
    command: [
      "bash", "-c",
      "if command -v nvidia-smi >/dev/null 2>&1; then "
        + "IFS=, read -r util temp used total < <(nvidia-smi --query-gpu=utilization.gpu,temperature.gpu,memory.used,memory.total --format=csv,noheader,nounits 2>/dev/null | head -n1); "
        + "if [[ $util =~ ^[[:space:]]*[0-9]+[[:space:]]*$ && $temp =~ ^[[:space:]]*[0-9]+[[:space:]]*$ && $used =~ ^[[:space:]]*[0-9]+[[:space:]]*$ && $total =~ ^[[:space:]]*[0-9]+[[:space:]]*$ ]]; then "
        + "printf 'nvidia|%s|%s|%s|%s\\n' \"$util\" \"$temp\" \"$used\" \"$total\"; exit 0; fi; "
        + "fi; "
        + "for busy in /sys/class/drm/card*/device/gpu_busy_percent; do "
        + "[[ -r $busy ]] || continue; read -r util < \"$busy\"; temp=0; "
        + "for sensor in \"${busy%/gpu_busy_percent}\"/hwmon/hwmon*/temp1_input; do "
        + "[[ -r $sensor ]] || continue; read -r raw < \"$sensor\"; temp=$((raw / 1000)); break; done; "
        + "printf 'sysfs|%s|%s|0|0\\n' \"$util\" \"$temp\"; exit 0; done; "
        + "printf 'none|0|0|0|0\\n'"
    ]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.parse(text)
    }
  }

  Timer {
    interval: root.intervalMs
    running: root.consumers > 0
    repeat: true
    onTriggered: root.refresh()
  }
}
