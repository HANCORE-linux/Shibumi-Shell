pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "state" as State
import "menu" as Menu

ShellRoot {
  id: root

  property int attempts: 0

  function fail(message) {
    console.error("menu-plugin-smoke:", message)
    Qt.exit(1)
  }

  QtObject {
    id: fakeBackground
    property string displayedBackground: "/tmp/shibumi-menu-wallpaper.png"
    property int backgroundVersion: 3
  }

  QtObject {
    id: fakeBar
    property string position: "top"
    property int barSize: 28
    property var visualTokens: ({
      panelBackground: "#202020",
      panelBorder: "#404040",
      panelBorderWidth: 1,
      panelRadius: 12,
      shadowEnabled: false,
      pillShadow: "#000000"
    })
  }

  QtObject {
    id: fakeShell
    property int writes: 0
    property var bar: fakeBar
    property var shellConfig: ({ version: 1, bar: { shibumi: { version: 1 } } })

    function mutateShellConfig(mutator) {
      const next = JSON.parse(JSON.stringify(shellConfig))
      mutator(next)
      shellConfig = next
      writes++
    }

    function serviceFor(pluginId) {
      if (pluginId === "hancore.shibumi.state") return stateService
      if (pluginId === "hancore.shibumi.menu") return menuService
      return null
    }

    function firstPartyServiceFor(pluginId) {
      return pluginId === "omarchy.background" ? fakeBackground : null
    }

    function hide(_pluginId) {}
  }

  State.Service {
    id: stateService
    shell: fakeShell
  }

  Menu.AppMenuService {
    id: menuService
    omarchyPath: Quickshell.env("OMARCHY_PATH")
    shell: fakeShell
    manifest: ({ id: "hancore.shibumi.menu" })
    desktopEntrySource: []
  }

  Menu.Menu {
    id: menuController
    shell: fakeShell
    manifest: ({ id: "hancore.shibumi.menu" })
    service: menuService
    surfaceSource: ""
  }

  Menu.MenuSettings {
    id: menuSettings
    width: 420
    controller: menuController
  }

  Timer {
    interval: 20
    running: true
    repeat: true
    onTriggered: {
      root.attempts++
      if (root.attempts > 150) return root.fail("service did not become ready")
      if (!stateService.ready || !menuService.ready || !menuService.menuReady
          || !menuSettings.ready) return

      if (typeof menuController.setGroupSetting === "function"
          || typeof menuController.setBarPosition === "function"
          || typeof menuController.setReactorMode === "function")
        return root.fail("menu still exposes bar settings")

      if (menuController.open('{"menu":"root"}') !== "ok"
          || !menuController.opened || !menuService.menuOpen)
        return root.fail("menu lifecycle did not open")
      menuController.openSettings()
      if (!menuController.settingsOpen)
        return root.fail("menu settings did not open")

      if (!menuController.setPresentation("selectionStyle", "glide")
          || !menuController.setPresentation("scale", 80)
          || !menuController.setLauncher("mode", "icon")
          || stateService.config.menu.presentation.selectionStyle !== "glide"
          || stateService.config.menu.presentation.scale !== 80
          || stateService.config.menu.launcher.mode !== "icon"
          || fakeShell.writes !== 3)
        return root.fail("menu state persistence changed")

      menuController.close()
      if (menuController.opened || menuService.menuOpen)
        return root.fail("menu lifecycle did not close")

      stop()
      console.log("menu plugin smoke passed")
      Qt.quit()
    }
  }
}
