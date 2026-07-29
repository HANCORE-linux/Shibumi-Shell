pragma ComponentBehavior: Bound

import QtQuick
import "../menu" as Menu

Item {
  id: root

  property var bar: null

  visible: false
  width: 0
  height: 0

  function componentFor(moduleName) {
    if (moduleName === "hancore.shibumi.bar") return menuWidget
    if (moduleName === "omarchy.workspaces"
        || moduleName === "hancore.shibumi.workspaces") return workspaceWidget
    if (moduleName === "hancore.shibumi.memory") return memoryWidget
    if (moduleName === "hancore.shibumi.cpu") return cpuWidget
    if (moduleName === "hancore.shibumi.audio") return audioWidget
    if (moduleName === "hancore.shibumi.ai") return aiUsageWidget
    if (moduleName === "hancore.shibumi.status") return statusWidget
    if (moduleName === "hancore.shibumi.media") return mediaWidget
    if (moduleName === "hancore.shibumi.quick-access") return quickAccessWidget
    if (moduleName === "hancore.shibumi.network") return networkWidget
    if (moduleName === "hancore.shibumi.brightness") return brightnessWidget
    if (moduleName === "hancore.shibumi.battery") return batteryWidget
    if (moduleName === "hancore.shibumi.power-profile") return powerProfileWidget
    if (moduleName === "hancore.shibumi.bluetooth") return bluetoothWidget
    if (moduleName === "hancore.shibumi.center") return centerWidget
    if (moduleName === "omarchy.clock") return clockWidget
    return null
  }

  Component {
    id: menuWidget

    Menu.BarWidget { bar: root.bar }
  }

  Component {
    id: workspaceWidget

    WorkspaceWidget { bar: root.bar }
  }

  Component {
    id: memoryWidget

    MemoryWidget { bar: root.bar }
  }

  Component {
    id: cpuWidget

    CpuWidget { bar: root.bar }
  }

  Component {
    id: statusWidget

    StatusWidget { bar: root.bar }
  }

  Component {
    id: audioWidget

    AudioWidget { bar: root.bar }
  }

  Component {
    id: aiUsageWidget

    AiUsageWidget { bar: root.bar }
  }

  Component {
    id: mediaWidget

    MediaWidget { bar: root.bar }
  }

  Component {
    id: quickAccessWidget

    QuickAccessWidget { bar: root.bar }
  }

  Component {
    id: networkWidget

    NetworkWidget { bar: root.bar }
  }

  Component {
    id: brightnessWidget

    BrightnessWidget { bar: root.bar }
  }

  Component {
    id: batteryWidget

    BatteryWidget { bar: root.bar }
  }

  Component {
    id: powerProfileWidget

    PowerProfileWidget { bar: root.bar }
  }

  Component {
    id: bluetoothWidget

    BluetoothWidget { bar: root.bar }
  }

  Component {
    id: centerWidget

    CenterWidget { bar: root.bar }
  }

  Component {
    id: clockWidget

    ClockWidget { bar: root.bar }
  }
}
