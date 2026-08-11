pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "storage" as Storage

ShellRoot {
  id: root

  property int ticks: 0
  property bool selectionChecked: false
  property bool compactChecked: false
  property bool infoGeometryChecked: false
  property real storageDefaultWidth: 0
  property var fixture: ({
    blockdevices: [
      {
        name: "sda", path: "/dev/sda", type: "disk",
        size: 500107862016, model: "Internal SSD", tran: "sata",
        rota: false, rm: false, hotplug: false, children: [
          {
            name: "sda1", path: "/dev/sda1", type: "part",
            size: 1073741824, fstype: "vfat", fsused: 100,
            fsavail: 900, "fsuse%": "10%", mountpoints: ["/boot"]
          },
          {
            name: "sda2", path: "/dev/sda2", type: "part",
            size: 499000000000, fstype: "btrfs", fsused: 400,
            fsavail: 600, "fsuse%": "40%", mountpoints: ["/"]
          }
        ]
      },
      {
        name: "zram0", path: "/dev/zram0", type: "disk",
        size: 8000000000, fstype: "swap", mountpoints: ["[SWAP]"],
        rota: false, rm: false, hotplug: false
      },
      {
        name: "nvme0n1", path: "/dev/nvme0n1", type: "disk",
        size: 1000000000000, model: "Fast NVMe", tran: "nvme",
        rota: false, rm: false, hotplug: false, children: [{
          name: "nvme0n1p1", path: "/dev/nvme0n1p1", type: "part",
          size: 999000000000, fstype: "ext4", fsused: 750,
          fsavail: 250, "fsuse%": "75%", mountpoints: ["/data"]
        }]
      },
      {
        name: "sdc", path: "/dev/sdc", type: "disk",
        size: 64000000000, model: "USB Stick", tran: "usb",
        rota: false, rm: true, hotplug: true, fstype: "iso9660",
        label: "OMARCHY_202512", children: [
          {
            name: "sdc1", path: "/dev/sdc1", type: "part",
            size: 60000000000, fstype: "exfat", fsused: null,
            fsavail: null, "fsuse%": null, mountpoints: [],
            parttype: "0x0", label: "OMARCHY_202512"
          },
          {
            name: "sdc2", path: "/dev/sdc2", type: "part",
            size: 25000000, fstype: "vfat", fsused: null,
            fsavail: null, "fsuse%": null, mountpoints: [],
            parttype: "0xef", label: "ARCHISO_EFI"
          }
        ]
      }
    ]
  })

  Storage.StorageTelemetry {
    id: storage
    runtimeProbesEnabled: false
  }

  property var storageObject: storage

  Item { id: anchorItem; width: 20; height: 20 }

  QtObject {
    id: fakeBar
    property string position: "top"
    property string fontFamily: "monospace"
    property color foreground: "#eeeeee"
    property color barForeground: foreground
    property color urgent: "#88bbee"
    property int barSize: 35
    property bool vertical: false
    property var activePopout: null
    property var shell: fakeShell
    function requestPopout(owner) { activePopout = owner }
    function releasePopout(owner) { if (activePopout === owner) activePopout = null }
    function switchPanelFrom(_owner, _direction) { return true }
    function showTooltip(_target, _text) {}
    function hideTooltip(_target) {}
  }

  QtObject {
    id: fakeState
    property var config: ({})
    property string lastGroup: ""
    property string lastKey: ""
    property string lastValue: ""
    function setGroupSetting(group, key, value) {
      lastGroup = String(group)
      lastKey = String(key)
      lastValue = String(value)
      return true
    }
    function paletteColor(name) {
      return name === "color03" ? "#c080ff"
        : name === "color04" ? "#55aacc" : "#d75f5f"
    }
  }

  QtObject {
    id: fakeStorageService
    property var storage: root.storageObject
  }

  QtObject {
    id: fakeShell
    function serviceFor(id) {
      if (id === "hancore.shibumi.storage") return fakeStorageService
      if (id === "hancore.shibumi.state") return fakeState
      return null
    }
  }

  Item {
    id: fakeOwner
    property bool opened: true
    property string selectedSource: "root"
    property var stateService: fakeState
    function close() { opened = false }
    function switchPanel(_direction) { return true }
    function setStorageSource(source) {
      selectedSource = String(source)
      return true
    }
  }

  Component {
    id: storageWidgetComponent
    Storage.BarWidget {
      bar: fakeBar
      hostGroupId: "G:hancore.shibumi.storage"
      settings: ({ displayMode: "full", source: "/dev/nvme0n1" })
    }
  }

  Loader {
    id: storageWidgetLoader
    active: false
    sourceComponent: storageWidgetComponent
  }

  Storage.StoragePanel {
    id: storagePanel
    anchorItem: anchorItem
    bar: fakeBar
    ownerWidget: fakeOwner
    storage: storage
  }

  function fail(message) {
    console.error("storage-plugin-smoke:", message)
    Qt.exit(1)
  }

  Component.onCompleted: {
    storage.parseUsage("Filesystem 1B-blocks Used Available Use%\n"
      + "/dev/mapper/root 1000 400 600 40%\n")
    if (!storage.available || storage.totalBytes !== 1000
        || storage.usedBytes !== 400 || storage.freeBytes !== 600
        || storage.percent !== 40 || storage.rootDevice !== "/dev/mapper/root")
      return fail("root usage parsing")
    if (!storage.parseInventory(JSON.stringify(fixture)))
      return fail("inventory fixture rejected")
    if (storagePanel.freeSummary(75, 268435456000, 1073741824000)
        !== "25% FREE · 250.0/1000.0 GiB")
      return fail("free percentage summary")
    if (String(storagePanel.controlAccent).toLowerCase() !== "#d75f5f")
      return fail("storage standard control accent")
    if (!storage.inventoryAvailable || storage.drives.length !== 3)
      return fail("physical drive filtering")

    const internal = storage.drives[0]
    const nvme = storage.drives[1]
    const usb = storage.drives[2]
    if (internal.driveType !== "ssd" || internal.media !== "SSD"
        || internal.mountSummary !== "/ +1")
      return fail("internal drive inventory")
    if (nvme.driveType !== "nvme" || nvme.media !== "NVME SSD"
        || nvme.percent !== 75 || nvme.mountSummary !== "/data")
      return fail("NVMe classification and usage")
    if (!usb.removable || usb.driveType !== "usb"
        || usb.volumes.length !== 3
        || usb.volumes[0].path !== "/dev/sdc"
        || usb.volumes[1].path !== "/dev/sdc1"
        || usb.volumes[2].path !== "/dev/sdc2")
      return fail("hybrid USB read-only inventory")
  }

  Timer {
    interval: 40
    running: true
    repeat: true
    onTriggered: {
      root.ticks++
      if (storagePanel.contentWidth <= 0 || storagePanel.contentHeight <= 0
          || storagePanel.contentHeight > 500) {
        if (root.ticks < 25) return
        return root.fail("compact storage panel geometry: "
          + storagePanel.contentWidth + "x" + storagePanel.contentHeight)
      }
      if (!storageWidgetLoader.active) {
        storageWidgetLoader.active = true
        return
      }
      const storageWidget = storageWidgetLoader.item
      if (!storageWidget) return
      if (!root.selectionChecked) {
        if (storageWidget.selectedSource !== "/dev/nvme0n1"
            || storageWidget.selectedPercent !== 75
            || storageWidget.selectedLabel !== "Fast NVMe"
            || storageWidget.iconSlotSize !== 14
            || storageWidget.compactIconOpticalOffset !== 0)
          return root.fail("selected bar percentage")
        if (!storageWidget.setStorageSource("/dev/sda")
            || fakeState.lastGroup !== "G:hancore.shibumi.storage"
            || fakeState.lastKey !== "source"
            || fakeState.lastValue !== "/dev/sda")
          return root.fail("selected storage persistence")
        root.storageDefaultWidth = storageWidget.implicitWidth
        storageWidget.settings = ({
          displayMode: "icon", source: "/dev/nvme0n1"
        })
        root.selectionChecked = true
        return
      }
      if (!root.compactChecked) {
        if (!storageWidget.compact || storageWidget.valueVisible
            || storageWidget.compactIconOpticalOffset >= 0
            || storageWidget.implicitWidth >= root.storageDefaultWidth)
          return root.fail("V1 Storage compact is not icon-only"
            + " mode=" + storageWidget.displayMode
            + " compact=" + storageWidget.compact
            + " value=" + storageWidget.valueVisible
            + " width=" + storageWidget.implicitWidth
            + " defaultWidth=" + root.storageDefaultWidth)
        storageWidget.settings = ({
          displayMode: "full", source: "/dev/nvme0n1"
        })
        storagePanel.showInfo("/dev/nvme0n1")
        if (storagePanel.activeView !== "info"
            || !storagePanel.detailDrive
            || storagePanel.detailDrive.path !== "/dev/nvme0n1"
            || storagePanel.detailRows().length < 7)
          return root.fail("lsblk info view")
        root.compactChecked = true
        return
      }
      if (!root.infoGeometryChecked) {
        if (storagePanel.activeView !== "info"
            || storagePanel.contentHeight <= 0
            || storagePanel.contentHeight > 500)
          return root.fail("lsblk info geometry: "
            + storagePanel.contentWidth + "x" + storagePanel.contentHeight)
        root.infoGeometryChecked = true
        storagePanel.activeView = "drives"
        return
      }
      stop()
      console.log("storage plugin smoke passed")
      Qt.quit()
    }
  }
}
