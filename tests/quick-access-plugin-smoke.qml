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
        style: "default",
        imageStyle: "tanzaku",
        mediaStyle: "default"
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
    function isThumbnailReady(entry) {
      return entry && entry.thumbnailReady === true
    }
    function activateSelected() { return true }
    function selectIndex(index) { selectedIndex = Number(index); return true }
  }

  QtObject {
    id: imageWindowController
    property bool opened: true
    property int requestSerial: 1
    property int imageSourceRevision: 1
    property int thumbnailRevision: 1
    property string mode: "screenshots"
    property string currentSelection: ""
    property int selectedIndex: 50
    property bool videoMode: false
    property var filteredEntries: {
      const rows = []
      for (let i = 0; i < 100; i++)
        rows.push({ label: "entry-" + i, sourcePath: "/tmp/source-" + i,
          thumbnailPath: "/tmp/thumb-" + i, thumbnailReady: true })
      return rows
    }
    readonly property var selectedEntry: filteredEntries[selectedIndex]
    property string title: "Screenshots"
    property string emptyText: "No screenshots found"
    function thumbnailUrl(_entry) {
      return "data:image/svg+xml,%3Csvg%20xmlns=%22http://www.w3.org/2000/svg%22"
        + "%20width=%221%22%20height=%221%22/%3E"
    }
    function isThumbnailReady(_entry) { return true }
    function shouldLoadImage(_entry, index) {
      return Math.abs(Number(index) - selectedIndex) <= 6
    }
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

  QuickAccess.TanzakuPickerView {
    id: imageWindowTanzaku
    visible: false
    width: 1920
    height: 1080
    bar: fakeBar
    controller: imageWindowController
  }

  QuickAccess.HearthstonePickerView {
    id: imageWindowHearthstone
    visible: false
    width: 1920
    height: 1080
    bar: fakeBar
    controller: imageWindowController
  }

  QuickAccess.CarouselPickerView {
    id: imageWindowCarousel
    visible: false
    width: 1920
    height: 1080
    bar: fakeBar
    controller: imageWindowController
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
        if (imageWindowTanzaku.activeImageSourceCount !== 13
            || imageWindowHearthstone.activeImageSourceCount !== 13
            || imageWindowCarousel.activeImageSourceCount !== 13)
          return root.fail("picker image sources exceeded the preload window")
        if (imageWindowCarousel.itemWidth(0)
              !== imageWindowCarousel.previewWidth
            || imageWindowCarousel.itemWidth(1)
              !== imageWindowCarousel.sliceWidth
            || imageWindowCarousel.itemHeight(1)
              >= imageWindowCarousel.itemHeight(0)
            || imageWindowCarousel.sliceGap >= 0
            || imageWindowCarousel.skewOffset <= 0)
          return root.fail("Carousel did not retain its skewed-slice geometry")
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
        const rows = []
        for (let i = 0; i < 100; i++)
          rows.push("/tmp/source-" + i + ".png\t/tmp/thumb-" + i
            + ".jpg\tentry-" + i + "\t/tmp\t0")
        quickAccessService.currentSelection = "/tmp/source-50.png"
        quickAccessService.loading = true
        quickAccessService.scanComplete = false
        quickAccessService.finishCacheLoad(
          rows.join("\n"), quickAccessService.requestSerial)
        const stableEntries = quickAccessService.entries
        const initialRevision = quickAccessService.thumbnailRevision
        for (let i = 0; i < 100; i++)
          quickAccessService.noteThumbnailReady(
            "/tmp/thumb-" + i + ".jpg", quickAccessService.requestSerial)
        if (!quickAccessService.refreshScanPending || quickAccessService.loading
            || quickAccessService.scanComplete
            || quickAccessService.entries !== stableEntries
            || quickAccessService.thumbnailRevision !== initialRevision + 100
            || !quickAccessService.isThumbnailReady(stableEntries[99]))
          return root.fail("thumbnail warmup replaced the picker model")
        let activeSources = 0
        for (let i = 0; i < stableEntries.length; i++)
          if (quickAccessService.shouldLoadImage(stableEntries[i], i)) activeSources++
        if (quickAccessService.selectedIndex !== 50 || activeSources !== 13
            || quickAccessService.shouldLoadImage(stableEntries[43], 43))
          return root.fail("initial picker image window is not bounded")
        quickAccessService.selectIndex(57)
        let maxActiveSources = 0
        const longNavigationIndexes = [0, 25, 50, 75, 99]
        for (let navigation = 0; navigation < longNavigationIndexes.length;
            navigation++) {
          quickAccessService.selectIndex(longNavigationIndexes[navigation])
          let navigationActiveSources = 0
          for (let entryIndex = 0; entryIndex < stableEntries.length;
              entryIndex++) {
            if (quickAccessService.shouldLoadImage(
                stableEntries[entryIndex], entryIndex)) navigationActiveSources++
          }
          maxActiveSources = Math.max(maxActiveSources, navigationActiveSources)
        }
        if (maxActiveSources !== 13
            || quickAccessService.shouldLoadImage(stableEntries[50], 50)
            || !quickAccessService.shouldLoadImage(stableEntries[99], 99))
          return root.fail("picker image window grew during long navigation")
        quickAccessService.cycleStyle(1)
        second.openMode("videos")
        if (quickAccessService.pickerStyle !== "carousel"
            || quickAccessService.normalizeMediaStyle("default") !== "carousel"
            || quickAccessService.normalizeMediaStyle("unknown") !== "carousel")
          return root.fail("media default did not route to Carousel")
        quickAccessService.cycleStyle(1)
        root.phase++
        root.ticks = 0
      } else if (root.phase === 3) {
        if (quickAccessService.pickerStyle !== "tanzaku"
            || quickAccessService.imagePickerStyle !== "hearthstone"
            || quickAccessService.mediaPickerStyle !== "tanzaku"
            || fakeState.revision !== 2 || first.opened || !second.opened
            || quickAccessService.activeScreenName !== secondScreen.name
            || quickAccessService.mode !== "videos"
            || fakeBar.activePopout !== second)
          return root.fail("style persistence or second-screen routing")
        second.close()
        quickAccessService.openMode("theme", firstScreen)
        const imageSerial = quickAccessService.requestSerial
        if (!quickAccessService.cycleStyle(1)
            || quickAccessService.imagePickerStyle !== "omarchy"
            || !quickAccessService.usingOfficialPicker
            || !quickAccessService.opened
            || quickAccessService.mode !== "theme"
            || quickAccessService.activeScreenName !== firstScreen.name
            || quickAccessService.requestSerial !== imageSerial + 2)
          return root.fail("live switch to official image picker")
        quickAccessService.close()
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
