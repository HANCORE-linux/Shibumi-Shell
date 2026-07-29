import QtQuick
import Quickshell
import "menu" as AppMenu

ShellRoot {
  id: root

  function fail(message) {
    console.error("app menu contract smoke failed: " + message)
    Qt.exit(1)
  }

  QtObject {
    id: fakeBackground
    property string currentBackground: "/tmp/shibumi-current-wallpaper.png"
    property string displayedBackground: "/tmp/shibumi-displayed-wallpaper.png"
    property int backgroundVersion: 7
  }

  QtObject {
    id: fakeShell

    property int toggleCount: 0
    property int hideCount: 0
    property string toggledId: ""
    property string toggledPayload: ""
    property var bar: fakeBar
    property var shellConfig: ({
      bar: {
        position: "top",
        shibumi: {
          widgets: {},
          presentation: {
            border: true,
            shadow: false,
            frost: false,
            radius: "large",
            accent: "red"
          },
          workspace: { version: 1, mode: "10", style: "default" },
          picker: { style: "tanzaku" },
          reactor: { mode: 0 },
          menu: {
            version: 1,
            favorites: [],
            hidden: [],
            presentation: {
              icons: true,
              scale: 100,
              selectionStyle: "default",
              background: "off"
            }
          }
        }
      }
    })

    function toggle(id, payload) {
      toggleCount++
      toggledId = String(id || "")
      toggledPayload = String(payload || "")
    }

    function hide(_id) { hideCount++ }

    function mutateShellConfig(mutator) {
      const next = JSON.parse(JSON.stringify(shellConfig))
      mutator(next)
      shellConfig = next
    }

    function serviceFor(id) {
      return id === "hancore.shibumi.bar" ? appMenuService : null
    }

    function firstPartyServiceFor(id) {
      return id === "omarchy.background" ? fakeBackground : null
    }
  }

  QtObject {
    id: fakeDesktopEntry
    property string id: "org.example.Editor.desktop"
    property string name: "Example Editor"
    property string genericName: "Text editor"
    property string comment: "Fixture application"
    property string icon: "accessories-text-editor"
    property bool noDisplay: false
    property var keywords: ["editor", "text"]
    function execute() {}
  }

  QtObject {
    id: fakeScreen
    property string name: "DP-1"
  }

  QtObject {
    id: fakeWindow
    property var screen: fakeScreen
  }

  QtObject {
    id: fakeBar

    property var shell: fakeShell
    property bool vertical: false
    property int barSize: 28
    property string fontFamily: "monospace"
    property color barForeground: "#eeeeee"
    property color urgent: "#88aaff"
    property bool foregroundAnimationEnabled: false
    property var shibumiConfig: fakeShell.shellConfig.bar.shibumi
    property string position: fakeShell.shellConfig.bar.position
    property int reactorMode: Number(shibumiConfig.reactor.mode || 0)
    property int splitMutationCount: 0
    property int resetLayoutCount: 0
    property bool lastSplitValue: false
    property var themePalette: ({ color02: "#55aa77", color03: "#5577aa" })
    property var visualTokens: ({
      pillHeight: 24,
      pillRadius: 12,
      pill: "#332f2f",
      pillBorder: "#555050",
      pillBorderWidth: 1,
      pillShadow: "#000000",
      shadowEnabled: false
    })

    function showTooltip(_target, _text) {}
    function hideTooltip(_target) {}
    function registerClickTarget(_target) {}
    function unregisterClickTarget(_target) {}
    function targetWindow(_target) { return fakeWindow }

    function mutateShibumi(mutator) {
      fakeShell.mutateShellConfig(function(config) {
        mutator(config.bar.shibumi)
      })
      return true
    }

    function groupSetting(group, key, fallback) {
      const settings = shibumiConfig.widgets[group] || ({})
      return Object.prototype.hasOwnProperty.call(settings, key)
        ? settings[key] : fallback
    }

    function setGroupSetting(group, key, value) {
      return mutateShibumi(function(config) {
        const settings = config.widgets[group] || ({})
        settings[key] = value
        config.widgets[group] = settings
      })
    }

    function setPresentationSetting(key, value) {
      return mutateShibumi(function(config) { config.presentation[key] = value })
    }

    function setWorkspacePreference(key, value) {
      return mutateShibumi(function(config) { config.workspace[key] = value })
    }

    function setPickerStyle(value) {
      return mutateShibumi(function(config) { config.picker.style = value })
    }

    function setBarPosition(value) {
      fakeShell.mutateShellConfig(function(config) { config.bar.position = value })
      return true
    }

    function setAllSplits(value) {
      splitMutationCount++
      lastSplitValue = value
      return true
    }

    function resetBarLayout() {
      resetLayoutCount++
      return true
    }

    function setReactorMode(value) {
      return mutateShibumi(function(config) { config.reactor.mode = value })
    }
  }

  AppMenu.AppMenuService {
    id: appMenuService
    omarchyPath: Quickshell.env("OMARCHY_PATH")
    shell: fakeShell
    desktopEntrySource: [fakeDesktopEntry]
  }

  AppMenu.Menu {
    id: appMenu
    shell: fakeShell
    manifest: ({ id: "hancore.shibumi.bar" })
    service: appMenuService
    actionAdapter: fakeActions
    surfaceSource: ""
  }

  QtObject {
    id: fakeActions
    property int actionCount: 0
    property string lastAction: ""
    function runAction(value) {
      actionCount++
      lastAction = String(value || "")
      return lastAction !== ""
    }
    function launchApplication(_entry) { return true }
  }

  AppMenu.BarWidget {
    id: launcherWidget
    bar: fakeBar
  }

  property int loadAttempts: 0

  Timer {
    id: loadTimer
    interval: 20
    repeat: true
    running: true
    onTriggered: {
      root.loadAttempts++
      if (appMenuService.menuReady) {
        stop()
        root.runChecks()
      } else if (root.loadAttempts >= 100) {
        stop()
        root.fail("real Quattro menu source did not load")
      }
    }
  }

  function runChecks() {
    if (appMenu.opened) return fail("menu starts open")
    if (launcherWidget.animationActive) return fail("launcher animates while idle")
    const initialState = JSON.parse(appMenu.debugState(""))
    if (initialState.opened || initialState.route !== "root"
        || !initialState.serviceReady || initialState.rowCount !== 0)
      return fail("initial state contract")
    if (appMenuService.desktopEntries.length > 0
        && appMenuService.debugState().appCount === 0)
      return fail("DesktopEntries source was not indexed")
    if (appMenuService.debugState().menuCount < 250
        || !appMenuService.menuItem("system.lock")
        || !appMenuService.menuItem("style.theme"))
      return fail("real Quattro menu source contract")

    if (appMenu.open('{"menu":"apps"}') !== "ok") return fail("open result")
    if (!appMenu.opened || appMenu.requestedRoute !== "apps"
        || !appMenuService.menuOpen) return fail("open state")
    if (!launcherWidget.animationActive) return fail("launcher animation did not follow menu state")

    const previousRevision = appMenuService.revision
    if (appMenu.refresh() !== "ok" || appMenuService.revision !== previousRevision + 1)
      return fail("refresh delegation")

    appMenuService.configure({
      version: 1,
      favorites: ["org.example.Editor.desktop", "org.example.Editor"],
      hidden: ["org.example.Hidden"],
      presentation: {
        icons: false,
        scale: 80,
        selectionStyle: "glide",
        background: "full"
      }
    })
    const serviceState = appMenuService.debugState()
    if (serviceState.favoriteCount !== 1 || serviceState.hiddenCount !== 1)
      return fail("service configuration normalization")
    if (appMenu.backgroundMode !== "full" || appMenu.selectionStyle !== "glide"
        || appMenu.backgroundVersion !== 7
        || appMenu.backgroundUrl.indexOf("shibumi-displayed-wallpaper.png?v=7") < 0)
      return fail("presentation and wallpaper service contract")
    if (!appMenu.setPresentation("selectionStyle", "gradient")
        || fakeShell.shellConfig.bar.shibumi.menu.presentation.selectionStyle !== "gradient")
      return fail("presentation persistence through host configuration")
    if (!appMenu.setPresentation("icons", true)
        || !appMenu.setPresentation("scale", 60)
        || !appMenu.setPresentation("background", "search")
        || fakeShell.shellConfig.bar.shibumi.menu.presentation.icons !== true
        || fakeShell.shellConfig.bar.shibumi.menu.presentation.scale !== 60
        || fakeShell.shellConfig.bar.shibumi.menu.presentation.background !== "search")
      return fail("complete presentation persistence contract")
    if (!appMenu.setLauncher("mode", "icon")
        || !appMenu.setLauncher("text", "arch")
        || !appMenu.setLauncher("icon", "rebel")
        || fakeShell.shellConfig.bar.shibumi.menu.launcher.mode !== "icon"
        || fakeShell.shellConfig.bar.shibumi.menu.launcher.text !== "arch"
        || fakeShell.shellConfig.bar.shibumi.menu.launcher.icon !== "rebel")
      return fail("launcher persistence contract")
    if (appMenu.setLauncher("icon", "unsafe"))
      return fail("invalid launcher mutation")
    if (appMenu.setPresentation("selectionStyle", "unsafe")
        || appMenuService.menuConfig.presentation.selectionStyle !== "gradient")
      return fail("invalid presentation mutation")
    if (!appMenuService.toggleFavorite("org.example.Editor")
        || fakeShell.shellConfig.bar.shibumi.menu.favorites.length !== 0)
      return fail("favorite persistence through host configuration")
    if (!appMenuService.toggleHidden("org.example.Editor")
        || fakeShell.shellConfig.bar.shibumi.menu.hidden.indexOf("org.example.Editor") < 0)
      return fail("hidden persistence through host configuration")
    if (appMenuService.toggleFavorite("missing.desktop"))
      return fail("unknown app preference mutation")

    appMenuService.replaceMenuTexts(`{
      "apps": { "label": "Apps", "aliases": ["applications"] },
      "style": { "label": "Style" },
      "style.theme": { "label": "Theme", "action": "theme-command" }
    }`, '{ "style.theme": { "label": "Theme picker" } }')
    if (!appMenuService.menuReady || appMenuService.resolveMenuRoute("applications") !== "apps")
      return fail("menu source service contract")
    const themeItem = appMenuService.menuItem("style.theme")
    if (!themeItem || themeItem.label !== "Theme picker" || themeItem.action !== "theme-command")
      return fail("menu source partial override")

    appMenu.open('{"menu":"root"}')
    if (appMenu.visibleRows.length !== 2 || appMenu.cursorActive)
      return fail("controller root rows")
    appMenu.select(1)
    if (!appMenu.cursorActive || appMenu.selectedIndex !== 0)
      return fail("first down selection")
    appMenu.setQuery("theme")
    if (appMenu.visibleRows.length !== 1 || appMenu.visibleRows[0].id !== "style.theme")
      return fail("controller descendant search")
    if (!appMenu.activateIndex(0) || fakeActions.actionCount !== 1
        || fakeActions.lastAction !== "theme-command" || appMenu.opened)
      return fail("controller action dispatch")

    appMenu.open('{"menu":"root"}')
    appMenu.openSettings()
    if (!appMenu.settingsOpen || appMenu.menuTitle !== "Shibumi settings")
      return fail("settings open contract")
    if (appMenu.barController !== fakeBar
        || !appMenu.setGroupSetting("G4", "compact", true)
        || !appMenu.setBarPresentation("accent", "color02")
        || !appMenu.setWorkspacePreference("style", "magic")
        || !appMenu.setPickerStyle("hearthstone")
        || !appMenu.setBarPosition("bottom")
        || !appMenu.setAllSplits(true)
        || !appMenu.resetBarLayout()
        || !appMenu.setReactorMode(8))
      return fail("settings controller delegation")
    const shibumi = fakeShell.shellConfig.bar.shibumi
    if (shibumi.widgets.G4.compact !== true
        || shibumi.presentation.accent !== "color02"
        || shibumi.workspace.style !== "magic"
        || shibumi.picker.style !== "hearthstone"
        || shibumi.reactor.mode !== 8
        || fakeShell.shellConfig.bar.position !== "bottom"
        || fakeBar.splitMutationCount !== 1 || !fakeBar.lastSplitValue
        || fakeBar.resetLayoutCount !== 1)
      return fail("settings persistence through active bar")
    if (!appMenu.goBack() || appMenu.settingsOpen)
      return fail("settings back contract")
    if (!appMenu.activateIndex(0) || appMenu.activeRoute !== "apps"
        || appMenu.navStack.length !== 1)
      return fail("integrated apps navigation")
    if (!appMenu.goBack() || appMenu.activeRoute !== "root")
      return fail("controller back navigation")
    appMenu.close()
    if (appMenuService.menuOpen) return fail("shared menu-open state")
    if (launcherWidget.animationActive) return fail("launcher animation remained active after close")

    appMenuService.replaceMenuTexts('{ "apps": { "label": "Apps" } }', "broken")
    if (!appMenuService.menuReady || appMenuService.debugState().menuError !== "invalid-user-menu"
        || appMenuService.menuItem("apps") === null)
      return fail("malformed user menu fallback")

    appMenu.service = null
    if (!JSON.parse(appMenu.debugState("")).serviceReady)
      return fail("late service lookup")

    appMenu.close()
    if (appMenu.opened) return fail("close state")
    appMenu.open("not-json")
    if (!appMenu.opened || appMenu.requestedRoute !== "root") return fail("invalid payload fallback")
    appMenu.close()

    if (!launcherWidget.summonMenu()) return fail("launcher summon result")
    if (Math.round(launcherWidget.implicitWidth) !== 24)
      return fail("V1 icon launcher geometry")
    if (fakeShell.toggleCount !== 1) return fail("launcher summon count")
    if (fakeShell.toggledId !== "hancore.shibumi.bar") return fail("launcher plugin id")
    const payload = JSON.parse(fakeShell.toggledPayload)
    if (payload.menu !== "root" || payload.screen !== "DP-1")
      return fail("launcher payload")

    console.log("app menu contract smoke passed")
    Qt.quit()
  }
}
