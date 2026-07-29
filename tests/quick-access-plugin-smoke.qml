pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "quickaccess" as QuickAccess

ShellRoot {
  id: root

  property int phase: 0
  property int ticks: 0
  property var quickSettings: ({ displayMode: "full" })

  function fail(message) {
    console.error("quick-access-plugin-smoke:", message)
    Qt.exit(1)
  }

  QtObject { id: firstScreen; property string name: "DP-1" }
  QtObject { id: secondScreen; property string name: "HDMI-A-1" }

  QtObject {
    id: fakeState
    property bool ready: true
    property int revision: 0
    property var config: ({
      picker: {
        style: "tanzaku",
        imageStyle: "tanzaku",
        mediaStyle: "tanzaku"
      }
    })
    function setPickerStyle(value) {
      const style = String(value || "")
      config = ({ picker: {
        style: style,
        imageStyle: style,
        mediaStyle: style
      } })
      revision++
      return true
    }
    function setImagePickerStyle(value) {
      const style = String(value || "")
      config = ({ picker: {
        style: config.picker.mediaStyle,
        imageStyle: style,
        mediaStyle: config.picker.mediaStyle
      } })
      revision++
      return true
    }
    function setMediaPickerStyle(value) {
      const style = String(value || "")
      config = ({ picker: {
        style: style,
        imageStyle: config.picker.imageStyle,
        mediaStyle: style
      } })
      revision++
      return true
    }
  }

  QtObject {
    id: fakeShell
    property var bar: fakeBar
    function serviceFor(pluginId) {
      if (pluginId === "hancore.shibumi.state") return fakeState
      if (pluginId === "hancore.shibumi.quick-access") return quickAccessService
      return null
    }
  }

  QtObject {
    id: fakePickerController
    property bool opened: false
    property int requestSerial: 0
    property string mode: "wallpaper"
    property string currentSelection: "/tmp/current.jpg"
    property int selectedIndex: 0
    property bool videoMode: false
    property var filteredEntries: []
    readonly property var selectedEntry: filteredEntries.length > 0
      ? filteredEntries[Math.max(0, Math.min(selectedIndex,
          filteredEntries.length - 1))] : null
    property string title: "Wallpapers"
    property string emptyText: "No wallpapers found"
    function thumbnailUrl(_entry) { return "" }
    function activateSelected() { return true }
    function selectIndex(index) { selectedIndex = Number(index); return true }
  }

  Item {
    id: fakeBar
    visible: false
    width: 0
    height: 0
    property bool vertical: false
    property int barSize: 35
    property string position: "top"
    property string fontFamily: "monospace"
    property color foreground: "#eeeeee"
    property color background: "#111111"
    property color urgent: "#dd7788"
    property var shell: fakeShell
    property var activePopout: null
    property var visualTokens: ({
      slotHeight: 28,
      pillHeight: 24,
      pillRadius: 12,
      pillPaddingX: 9,
      pill: "#332f2f",
      paper: "#111111",
      mutedInk: "#999999",
      pillBorder: "#555050",
      pillBorderWidth: 1,
      pillShadow: "#000000",
      shadowEnabled: false,
      iconSize: 18
    })
    function showTooltip(_target, _text) {}
    function hideTooltip(_target) {}
    function requestPopout(owner) { activePopout = owner }
    function releasePopout(owner) { if (activePopout === owner) activePopout = null }
    function screenForName(name) {
      return name === firstScreen.name ? firstScreen
        : name === secondScreen.name ? secondScreen : null
    }
  }

  QuickAccess.HearthstonePickerView {
    id: hearthstoneProbe
    visible: false
    width: 1920
    height: 1080
    bar: fakeBar
    controller: fakePickerController
  }

  QuickAccess.TanzakuPickerView {
    id: tanzakuProbe
    visible: false
    width: 1920
    height: 1080
    bar: fakeBar
    controller: fakePickerController
  }

  QuickAccess.Service {
    id: quickAccessService
    shell: fakeShell
    omarchyPath: "/tmp/shibumi-test-omarchy"
    runtimeWorkersEnabled: false
    presentationEnabled: false
  }

  Loader {
    id: firstLoader
    active: true
    sourceComponent: Component {
      QuickAccess.BarWidget {
        bar: fakeBar
        settings: root.quickSettings
        targetScreenOverride: firstScreen
      }
    }
  }

  Loader {
    id: secondLoader
    active: true
    sourceComponent: Component {
      QuickAccess.BarWidget {
        bar: fakeBar
        targetScreenOverride: secondScreen
      }
    }
  }

  Timer {
    id: watchdog
    interval: 6000
    running: true
    onTriggered: root.fail("timeout in phase " + root.phase)
  }

  Timer {
    interval: 70
    repeat: true
    running: true
    onTriggered: {
      root.ticks++
      const first = firstLoader.item
      const second = secondLoader.item
      if (!first || (root.phase < 4 && !second)) {
        if (root.ticks >= 12) root.fail("widget loaders did not resolve")
        return
      }
      if (root.ticks < 3) return

      if (root.phase === 0) {
        if (!quickAccessService.available || first.picker !== quickAccessService
            || second.picker !== quickAccessService
            || quickAccessService.pickerStyle !== "tanzaku")
          return root.fail("shared service readiness")
        if (hearthstoneProbe.dealStarted || hearthstoneProbe.dealProgress !== 0)
          return root.fail("Hearthstone deal ran before scan results")
        if (tanzakuProbe.navigationAnimationsEnabled)
          return root.fail("Tanzaku navigation animated before scan results")
        fakePickerController.requestSerial++
        fakePickerController.opened = true
        fakePickerController.filteredEntries = [
          { label: "left", sourcePath: "/tmp/left.jpg", thumbnailReady: false },
          { label: "current", sourcePath: "/tmp/current.jpg", thumbnailReady: false },
          { label: "right", sourcePath: "/tmp/right.jpg", thumbnailReady: false }
        ]
        fakePickerController.selectedIndex = 1
        if (tanzakuProbe.navigationAnimationsEnabled)
          return root.fail("Tanzaku initial layout enabled navigation animations")
        root.phase++
        root.ticks = 0
      } else if (root.phase === 1) {
        if (!tanzakuProbe.navigationAnimationsEnabled)
          return root.fail("Tanzaku navigation animations did not arm after layout")
        if (hearthstoneProbe.maxVisible !== 5
            || hearthstoneProbe.focusScale !== 1.24
            || hearthstoneProbe.spreadDegrees !== 6
            || hearthstoneProbe.dealProgress < 0.99)
          return root.fail("Hearthstone V1 presentation contract")
        if (!first.toggleIdleInhibitor() || !first.idleInhibited
            || !second.idleInhibited)
          return root.fail("shared idle-inhibitor state")
        first.openMode("wallpaper")
        root.phase++
        root.ticks = 0
      } else if (root.phase === 2) {
        if (!first.opened || second.opened
            || quickAccessService.activeScreenName !== firstScreen.name
            || quickAccessService.mode !== "wallpaper"
            || fakeBar.activePopout !== first)
          return root.fail("first-screen picker routing")
        quickAccessService.cycleStyle(1)
        second.openMode("videos")
        quickAccessService.cycleStyle(1)
        root.phase++
        root.ticks = 0
      } else if (root.phase === 3) {
        if (quickAccessService.pickerStyle !== "hearthstone"
            || quickAccessService.imagePickerStyle !== "hearthstone"
            || quickAccessService.mediaPickerStyle !== "hearthstone"
            || fakeState.revision !== 2 || first.opened || !second.opened
            || quickAccessService.activeScreenName !== secondScreen.name
            || quickAccessService.mode !== "videos"
            || fakeBar.activePopout !== second)
          return root.fail("style persistence or second-screen routing")
        second.close()
        root.phase++
        root.ticks = 0
      } else if (root.phase === 4) {
        if (quickAccessService.opened || fakeBar.activePopout !== null
            || quickAccessService.loading)
          return root.fail("picker close lifecycle")
        secondLoader.active = false
        root.quickSettings = ({ displayMode: "text" })
        root.phase++
        root.ticks = 0
      } else if (root.phase === 5) {
        if (secondLoader.item !== null || !first.idleInhibited
            || !first.textMode || first.compact
            || first.displayMode !== "text")
          return root.fail("widget teardown or shared state retention")
        root.quickSettings = ({ displayMode: "icon" })
        root.phase++
        root.ticks = 0
      } else if (root.phase === 6) {
        if (!first.compact || first.textMode
            || first.displayMode !== "icon")
          return root.fail("quick-access display modes")
        if (!quickAccessService.startSelectionAction("wallpaper", "broken.jpg",
            ["bash", "-c", "printf 'denied by fixture\\n' >&2; exit 7"]))
          return root.fail("failed wallpaper action did not start")
        root.phase++
        root.ticks = 0
      } else {
        if (quickAccessService.actionRunning) return
        if (root.phase === 7) {
          if (quickAccessService.lastActionFailure
              !== "Could not apply broken.jpg. denied by fixture")
            return root.fail("failed wallpaper action was not reported")
          if (!quickAccessService.startSelectionAction("theme", "broken-theme",
              ["bash", "-c", "printf 'theme denied by fixture\\n' >&2; exit 8"]))
            return root.fail("failed theme action did not start")
          root.phase++
          root.ticks = 0
        } else {
          if (quickAccessService.lastActionFailure
              !== "Could not apply broken-theme. theme denied by fixture")
            return root.fail("failed theme action was not reported")
          stop()
          watchdog.stop()
          console.log("quick access plugin smoke passed")
          Qt.quit()
        }
      }
    }
  }
}
