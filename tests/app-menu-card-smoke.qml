import QtQuick
import Quickshell
import "menu" as AppMenu

ShellRoot {
  id: root

  QtObject {
    id: controller
    property int presentationScale: 100
    property bool settingsOpen: false
    property bool appEditMode: false
    property string activeRoute: "root"
    property string query: ""
    property bool appMode: false
    property string menuTitle: "Shibumi"
    property string emptyMessage: "Nothing here yet"
    property bool cursorActive: true
    property int selectedIndex: 0
    property bool showIcons: true
    property string selectionStyle: "default"
    property string backgroundMode: "off"
    property int reactorMode: 0
    property string barPosition: "top"
    property string pickerStyle: "tanzaku"
    property var workspaceConfig: ({ version: 1, mode: "10", style: "default" })
    property var barPresentation: ({
      border: true, shadow: false, frost: false,
      radius: "large", accent: "red"
    })
    property var groupConfig: ({
      G7: { enabled: false }, G14: { enabled: false }, G15: { enabled: false }
    })
    property string backgroundUrl: "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
    property var launcherConfig: ({ mode: "text", text: "omarchy", icon: "omarchy" })
    property var visibleRows: [
      {
        id: "style", isApp: false, kind: "menu", target: "style",
        label: "Style", icon: "S", iconFont: "monospace", detail: "",
        checkedState: false, section: ""
      },
      {
        id: "org.example.Editor", isApp: true, kind: "app", target: "",
        label: "Editor", icon: "", detail: "Text editor", favorite: true,
        hidden: false, checkedState: false, section: ""
      }
    ]
    function goBack() {
      if (!settingsOpen) return false
      settingsOpen = false
      return true
    }
    function dismiss() {}
    function setAppEditMode(value) { appEditMode = value }
    function openSettings() { settingsOpen = true }
    function setPresentation(name, value) {
      if (name === "selectionStyle") selectionStyle = String(value)
      else if (name === "background") backgroundMode = String(value)
      else if (name === "scale") presentationScale = Number(value)
      else if (name === "icons") showIcons = value === true
      else return false
      return true
    }
    function setLauncher(name, value) {
      const next = JSON.parse(JSON.stringify(launcherConfig))
      if (["mode", "text", "icon"].indexOf(name) < 0) return false
      next[name] = value
      launcherConfig = next
      return true
    }
    function setReactorMode(value) {
      reactorMode = Number(value)
      return reactorMode >= 0 && reactorMode <= 8
    }
    function groupSetting(group, key, fallback) {
      const value = groupConfig[String(group)] || ({})
      return Object.prototype.hasOwnProperty.call(value, String(key))
        ? value[String(key)] : fallback
    }
    function setGroupSetting(group, key, value) {
      const next = JSON.parse(JSON.stringify(groupConfig))
      if (!next[group]) next[group] = ({})
      next[group][key] = value
      groupConfig = next
      return true
    }
    function setBarPresentation(name, value) {
      const next = JSON.parse(JSON.stringify(barPresentation))
      next[name] = value
      barPresentation = next
      return true
    }
    function setWorkspacePreference(name, value) {
      const next = JSON.parse(JSON.stringify(workspaceConfig))
      next[name] = value
      workspaceConfig = next
      return true
    }
    function setPickerStyle(value) { pickerStyle = String(value); return true }
    function setBarPosition(value) { barPosition = String(value); return true }
    function setAllSplits(_value) { return true }
    function resetBarLayout() { return true }
    function accentColor(value) {
      return value === "color02" ? "#88aa77"
        : value === "color03" ? "#ddbb66"
        : value === "accent" ? "#7799cc" : "#cc7766"
    }
    function setQuery(value) { query = value }
    function select(delta) {
      selectedIndex = (selectedIndex + delta + visibleRows.length) % visibleRows.length
    }
    function selectIndex(index) { selectedIndex = index; cursorActive = true }
    function activateIndex(_index) { return true }
    function toggleFavorite(_id) { return true }
    function toggleHidden(_id) { return true }
  }

  AppMenu.MenuCard {
    id: card
    controller: controller
    availableWidth: 800
    availableHeight: 600
  }

  Timer {
    property int phase: 0
    interval: 60
    repeat: true
    running: true
    onTriggered: {
      if (phase === 0) {
        if (card.renderedRowCount !== 2 || card.width <= 0 || card.height <= 0) {
          console.error("app menu card smoke failed: initial card")
          Qt.exit(1)
          return
        }
        card.focusSearch()
        controller.selectionStyle = "gradient"
        controller.backgroundMode = "full"
      } else if (phase === 1) {
        if (!card.fullBackgroundRendered || card.searchBackgroundRendered) {
          console.error("app menu card smoke failed: full background")
          Qt.exit(1)
          return
        }
        controller.selectionStyle = "glide"
        controller.backgroundMode = "search"
      } else if (phase === 2) {
        if (card.fullBackgroundRendered || !card.searchBackgroundRendered) {
          console.error("app menu card smoke failed: search background")
          Qt.exit(1)
          return
        }
        controller.presentationScale = 60
        controller.openSettings()
      } else if (phase === 3) {
        if (!card.settingsRendered || !card.settingsReady || !card.settingsFitWidth
            || card.width < 240 || card.height <= 0) {
          console.error("app menu card smoke failed: settings")
          Qt.exit(1)
          return
        }
        if (!card.settingsScrollRequired || card.height > card.availableHeight) {
          console.error("app menu card smoke failed: settings viewport scroll="
            + card.settingsScrollRequired + " card=" + card.height
            + " available=" + card.availableHeight
            + " content=" + card.settingsContentHeight
            + " viewport=" + card.settingsViewportHeight)
          Qt.exit(1)
          return
        }
        controller.goBack()
      } else {
        if (card.settingsRendered || card.width < 150 || card.width > 170) {
          console.error("app menu card smoke failed: scaled menu restore")
          Qt.exit(1)
          return
        }
        stop()
        console.log("app menu card smoke passed")
        Qt.quit()
      }
      phase++
    }
  }
}
