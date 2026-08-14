pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io
import qs.Commons as Commons

Item {
  id: root

  required property var controller
  property real uiScale: 1
  property color foreground: Commons.Color.menu.text
  property color accent: Commons.Color.menu.selectedText
  property string currentPage: "quick"
  property string lastConfigurePage: "main"
  property string configureDetailPage: ""
  property bool pluginFavoritesOnly: false
  property string pendingConfigureRoute: ""
  property alias settingsQuery: settingsSearch.text
  property bool paletteOpen: false
  property bool installMode: false
  property bool installerDirect: false
  property bool installConfirmed: false
  property string query: ""
  property string pickerProvider: "All"
  property string installUrl: ""
  property string installStatus: ""
  readonly property string normalizedInstallUrl:
    extractInstallUrl(installUrl)
  readonly property bool installInputWasCommand: normalizedInstallUrl !== ""
    && normalizedInstallUrl !== installUrl.trim()
  readonly property bool returnOnly: controller.stockOmarchyHost === true

  readonly property var pageOptions: {
    const pages = [
      { id: "bars", label: "Bars", glyph: "align_vertical_center" },
      { id: "functions", label: "Icons", glyph: "brush" },
      { id: "logo", label: "Logo", glyph: "branding_watermark" },
      { id: "workspaces", label: "Workspaces", glyph: "grid_view" },
      { id: "pickers", label: "Pickers", glyph: "collections" },
      { id: "plugins", label: "Plugins", glyph: "extension" },
      { id: "health", label: "Health", glyph: "health_and_safety" }
    ]
    return root.returnOnly ? [] : pages
  }
  readonly property var settingsSearchEntries: {
    const pageKeywords = {
      bars: "bars shell omarchy shibumi switch continuity layout v1 v2 "
        + "protect protection lock split gap slots divider separator "
        + "full fit dock notch position "
        + "surface color accent border panel tooltip",
      plugins: "widgets modules plugins add install enable disable remove "
        + "delete provider active available",
      workspaces: "workspace workspaces count active marker style navigation",
      pickers: "picker pickers theme wallpaper screenshot video media browser",
      logo: "logo launcher identity wordmark icon",
      functions: "icons icon appearance widget color surface style content "
        + "tone shape spacing opacity outline",
      health: "health runtime diagnostics errors warnings lifecycle plugins "
        + "source git drift versions updates"
    }
    const values = pageOptions.map(function(page) {
      return {
        kind: "page",
        id: page.id === "main" ? "configure" : page.id,
        name: page.label,
        label: page.label,
        description: "Control Center page",
        detail: "Control Center page",
        provider: "Settings",
        author: "Shibumi",
        category: "Settings",
        searchTags: String(pageKeywords[page.id] || "").split(" "),
        kinds: ["setting"],
        glyph: page.glyph
      }
    })
    const plugins = (controller.pluginEntries || []).filter(function(entry) {
      return entry.userToggleable === true && entry.styleAvailable !== false
    }).map(function(entry) {
      return {
        kind: "plugin",
        id: entry.id,
        group: controller.shibumiWidgetGroup(entry.id),
        name: entry.name,
        label: entry.name,
        description: entry.description,
        detail: entry.provider + " · " + entry.compatibility,
        provider: entry.provider,
        author: entry.author,
        category: entry.category,
        searchTags: entry.searchTags,
        kinds: entry.kinds,
        glyph: entry.glyph || "widgets"
      }
    })
    return values.concat(plugins)
  }
  readonly property int healthErrorCount: {
    const report = controller && controller.healthReport
      ? controller.healthReport : ({ checks: [] })
    const checks = Array.isArray(report.checks) ? report.checks : []
    const errors = checks.filter(function(check) {
      return String(check.status || "") === "error"
    }).length
    return errors > 0 ? errors
      : String(controller.healthFailure || "") !== "" ? 1 : 0
  }
  readonly property int healthWarningCount: {
    const report = controller && controller.healthReport
      ? controller.healthReport : ({ checks: [] })
    const checks = Array.isArray(report.checks) ? report.checks : []
    return checks.filter(function(check) {
      return String(check.status || "") === "warning"
    }).length
  }
  readonly property bool healthChecked: {
    const report = controller && controller.healthReport
      ? controller.healthReport : ({ checks: [] })
    return Array.isArray(report.checks) && report.checks.length > 0
  }
  readonly property bool healthPassed: healthChecked
    && healthErrorCount === 0 && healthWarningCount === 0
  readonly property color healthErrorColor:
    controller.accentColor("color01")
  readonly property color healthPassColor:
    controller.accentColor("color03")
  readonly property color registryValueColor:
    controller.accentColor("color03")
  readonly property bool configureDetailOpen: configureDetailPage !== ""
  readonly property bool compactConfigureLanding:
    currentPage === "configure"
    && !configureDetailOpen
    && settingsQuery.trim() === ""
  readonly property real compactConfigureLandingPanelHeight:
    Commons.Style.space(550)
  // Header, divider, search/mode bands, Flickable tail and the same 18 px
  // breathing room used by the fitted Icons overview.
  readonly property real configureDetailPanelChromeHeight:
    Commons.Style.space(28) + Commons.Style.spacing.sm * 2
    + Commons.Style.space(1) + Commons.Style.space(42) * 2
    + Commons.Style.space(12) + Commons.Style.space(18)
  readonly property bool compactBarsPage:
    currentPage === "configure"
    && configureDetailPage === "bars"
    && settingsQuery.trim() === ""
    && pageLoader.item !== null
  readonly property real compactBarsPanelHeight:
    configureDetailPanelChromeHeight
    + Math.max(1, Number(pageLoader.item
      ? pageLoader.item.implicitHeight : 1))
  readonly property bool compactIconsOverview:
    currentPage === "configure"
    && configureDetailPage === "functions"
    && settingsQuery.trim() === ""
    && pageLoader.item !== null
    && pageLoader.item.widgetDetailOpen === false
  readonly property real compactIconsPanelHeight:
    Commons.Style.space(470)
    + Math.max(0, Number(pageLoader.item
      ? pageLoader.item.widgetOverviewRowCount : 5) - 5)
      * Commons.Style.space(41)
  readonly property bool compactIconsSelection:
    currentPage === "configure"
    && configureDetailPage === "functions"
    && settingsQuery.trim() === ""
    && pageLoader.item !== null
    && pageLoader.item.widgetDetailOpen === true
  readonly property real compactIconsSelectionPanelHeight:
    // One no-scroll height for V1/V2, including V2 Fill + Outline + Geometry.
    Commons.Style.space(550)
  readonly property bool compactHealthPage:
    currentPage === "configure"
    && configureDetailPage === "health"
    && settingsQuery.trim() === ""
    && pageLoader.item !== null
  readonly property real compactHealthPanelHeight:
    configureDetailPanelChromeHeight
    + Math.max(1, Number(pageLoader.item
      ? pageLoader.item.implicitHeight : 1))
  readonly property bool compactPickersPage:
    currentPage === "configure"
    && configureDetailPage === "pickers"
    && settingsQuery.trim() === ""
  readonly property real compactPickersPanelHeight:
    Commons.Style.space(470)
  readonly property bool compactWorkspacesPage:
    currentPage === "configure"
    && configureDetailPage === "workspaces"
    && settingsQuery.trim() === ""
    && pageLoader.item !== null
  readonly property real compactWorkspacesPanelHeight:
    configureDetailPanelChromeHeight
    + Math.max(1, Number(pageLoader.item
      ? pageLoader.item.implicitHeight : 1))
  readonly property bool compactLogoPage:
    currentPage === "configure"
    && configureDetailPage === "logo"
    && settingsQuery.trim() === ""
  readonly property real compactLogoPanelHeight:
    Commons.Style.space(470)
    + Math.max(0, Number(pageLoader.item
      ? pageLoader.item.optionRowCount : 2) - 2)
      * Commons.Style.space(63)
  readonly property bool compactPluginsPage:
    currentPage === "configure"
    && configureDetailPage === "plugins"
    && settingsQuery.trim() === ""
  readonly property real compactPluginsPanelHeight:
    Commons.Style.space(500)
  readonly property bool barsChildRouteAvailable:
    currentPage === "configure"
    && (configureDetailPage === "bars"
      || configureDetailPage === "bars-motion")
    && pageLoader.item !== null
    && pageLoader.item.childRouteAvailable === true
  readonly property bool barsChildRouteActive:
    barsChildRouteAvailable && configureDetailPage === "bars-motion"
  readonly property string barsChildRouteLabel:
    barsChildRouteAvailable && pageLoader.item.childRouteLabel !== undefined
      ? String(pageLoader.item.childRouteLabel) : ""
  readonly property bool pluginFavoritesRouteAvailable:
    currentPage === "configure" && configureDetailPage === "plugins"
  readonly property bool pluginFavoritesRouteActive:
    pluginFavoritesRouteAvailable && pluginFavoritesOnly
  readonly property string restorePage: currentPage === "configure"
    && configureDetailOpen ? configureDetailPage : currentPage
  readonly property bool ready: quickPage.ready
    && (returnOnly || configureLanding.ready && pageReady)
  readonly property bool pageReady: currentPage === "quick"
    ? quickPage.ready
    : !configureDetailOpen && settingsQuery.trim() === ""
      ? configureLanding.ready
      : settingsQuery.trim() !== "" ? searchPage.ready
        : pageLoader.item !== null && pageLoader.item.ready === true
  readonly property var pageItem: currentPage === "quick"
    ? quickPage : !configureDetailOpen && settingsQuery.trim() === ""
      ? configureLanding : settingsQuery.trim() !== ""
        ? searchPage : pageLoader.item
  readonly property bool fitsWidth: implicitWidth <= width + 0.5
  readonly property var settingsSearchSuggestions: settingsSearch.suggestions
  readonly property int activeSettingsSearchSuggestion:
    settingsSearch.activeSuggestionIndex
  readonly property var settingsSearchResults: searchPage.results
  readonly property var filteredPlugins: {
    const needle = query.trim().toLowerCase()
    const entries = (controller.pluginEntries || []).filter(
      function(entry) {
        return entry.userToggleable === true
          && entry.styleAvailable !== false
          && (root.pickerProvider === "All"
            || entry.provider === root.pickerProvider)
      })
    if (!needle) return entries
    return entries.filter(function(entry) {
      return String(entry.name || "").toLowerCase().indexOf(needle) >= 0
        || String(entry.id || "").toLowerCase().indexOf(needle) >= 0
        || String(entry.compatibility || "").toLowerCase().indexOf(needle) >= 0
    })
  }
  readonly property bool validInstallUrl: normalizedInstallUrl !== ""
  readonly property var validPageIds: pageOptions.map(function(page) {
    return page.id
  }).concat(returnOnly ? ["quick"]
    : ["quick", "configure", "main", "bars-motion"])

  implicitWidth: Commons.Style.space(720)
  implicitHeight: Commons.Style.space(500)

  function pageComponent(page) {
    if (page === "bars" || page === "bars-motion") return activeBarPage
    if (page === "plugins") return pluginsPage
    if (page === "workspaces") return workspacesPage
    if (page === "pickers") return pickersPage
    if (page === "logo") return logoPage
    if (page === "functions") return functionsPage
    if (page === "health") return healthPage
    return overviewPage
  }

  function setPage(value) {
    const requested = String(value || "")
    // Keep former Advanced and Layout deep links working without retaining a
    // second editor for controls that are now owned by Health and Bars.
    const next = requested === "preferences" ? "health"
      : requested === "splits" ? "bars" : requested
    if (returnOnly && next !== "quick") return false
    const acceptedPages = Array.isArray(validPageIds)
      ? validPageIds : ["quick"]
    if (acceptedPages.indexOf(next) < 0)
      return false
    if (controller && typeof controller.trackSettingsPage === "function")
      controller.trackSettingsPage(next)
    if (next === "quick") {
      pluginFavoritesOnly = false
      configureDetailPage = ""
      configureLanding.cancelTransition()
      currentPage = "quick"
      settingsQuery = ""
      return true
    }
    currentPage = "configure"
    settingsQuery = ""
    if (next === "configure") {
      pluginFavoritesOnly = false
      configureDetailPage = ""
      configureLanding.cancelTransition()
      configureLanding.focusIndex = -1
      configureLanding.focus = false
      return true
    }
    pluginFavoritesOnly = false
    configureDetailPage = next
    lastConfigurePage = next === "bars-motion" ? "bars" : next
    scheduleConfigureRoute(next === "bars-motion" ? "bars" : next)
    return true
  }

  function scheduleConfigureRoute(value) {
    pendingConfigureRoute = String(value || "")
    configureRouteSync.restart()
  }

  Timer {
    id: configureRouteSync
    interval: 0
    onTriggered: {
      const route = root.pendingConfigureRoute
      root.pendingConfigureRoute = ""
      if (route === "") return
      configureLanding.showRoute(route)
      pageScrollAnimation.stop()
      pageFlick.contentY = 0
    }
  }

  function showBarsChildRoute() {
    if (!barsChildRouteAvailable) return false
    return setPage("bars-motion")
  }

  function showPluginFavorites() {
    if (configureDetailPage !== "plugins" || currentPage !== "configure") {
      if (!setPage("plugins")) return false
    }
    pluginFavoritesOnly = true
    pageScrollAnimation.stop()
    pageFlick.contentY = 0
    return true
  }

  function setMode(value) {
    const next = String(value || "")
    if (next === "quick") return setPage("quick")
    if (next !== "configure" || returnOnly) return false
    return setPage("configure")
  }

  function focusPredictiveSettingsSearch() {
    if (returnOnly) return false
    settingsSearch.forceInputFocus()
    return true
  }

  function setPredictiveSettingsQuery(value) {
    settingsSearch.suggestionsSuppressed = false
    settingsSearch.activeSuggestionIndex = -1
    settingsSearch.text = String(value || "")
    return true
  }

  function acceptSettingsSearchSuggestion(index) {
    return settingsSearch.acceptSuggestion(index)
  }

  function dismissSettingsSearch() {
    return settingsSearch.handleEscape()
  }

  function blurPredictiveSettingsSearch() {
    return settingsSearch.blur()
  }

  function settingsSearchContainsPoint(x, y) {
    const local = settingsSearch.mapFromItem(root, x, y)
    return local.x >= 0 && local.x <= settingsSearch.width
      && local.y >= 0
      && local.y <= settingsSearch.height
        + settingsSearch.reservedPopupHeight
  }

  function pluginSearchPage() {
    const page = pageLoader.item
    return page && page.searchInputActiveFocus !== undefined
      && typeof page.searchContainsPoint === "function"
      && typeof page.blurPluginSearch === "function" ? page : null
  }

  function dismissSearchesAt(x, y) {
    let dismissed = false
    if (settingsSearch.inputActiveFocus
        && !settingsSearchContainsPoint(x, y)) {
      settingsSearch.blur()
      dismissed = true
    }
    const pluginPage = pluginSearchPage()
    if (pluginPage !== null
        && pluginPage.searchInputActiveFocus === true
        && !pluginPage.searchContainsPoint(root, x, y)) {
      pluginPage.blurPluginSearch()
      dismissed = true
    }
    return dismissed
  }

  function openWidgetPicker() {
    if (returnOnly) return false
    query = ""
    pickerProvider = "All"
    installMode = false
    installerDirect = false
    installConfirmed = false
    installStatus = ""
    paletteOpen = true
    Qt.callLater(function() { paletteSearch.forceActiveFocus() })
    return true
  }

  function openPluginInstaller() {
    if (returnOnly) return false
    query = ""
    pickerProvider = "All"
    installMode = true
    installerDirect = true
    installConfirmed = false
    installStatus = ""
    paletteOpen = true
    Qt.callLater(function() { installInput.forceActiveFocus() })
    return true
  }

  function closeWidgetPicker() {
    if (pluginInstall.running) return false
    paletteOpen = false
    installMode = false
    installerDirect = false
    installConfirmed = false
    return true
  }

  function showInstaller() {
    if (returnOnly) return
    installMode = true
    installerDirect = false
    installConfirmed = false
    installStatus = ""
    Qt.callLater(function() { installInput.forceActiveFocus() })
  }

  function supportedInstallUrl(value) {
    return /^(https:\/\/|ssh:\/\/|git@)[^\s\x00-\x1f\x7f]+$/i
      .test(String(value || ""))
  }

  function installInputTokens(value) {
    const input = String(value || "").trim()
    if (input === "") return []
    const tokens = []
    let token = ""
    let quote = ""
    for (let index = 0; index < input.length; index++) {
      const character = input.charAt(index)
      if (quote !== "") {
        if (character === quote) quote = ""
        else token += character
        continue
      }
      if (character === "\"" || character === "'") {
        quote = character
      } else if (/\s/.test(character)) {
        if (token !== "") {
          tokens.push(token)
          token = ""
        }
      } else {
        token += character
      }
    }
    if (quote !== "") return []
    if (token !== "") tokens.push(token)
    return tokens
  }

  function extractInstallUrl(value) {
    const tokens = installInputTokens(value)
    let repository = ""
    for (let index = 0; index < tokens.length; index++) {
      const token = tokens[index]
      if (!supportedInstallUrl(token)) continue
      if (repository !== "") return ""
      repository = token
    }
    return repository
  }

  function normalizeInstallInput() {
    const repository = extractInstallUrl(installUrl)
    if (repository === "") return false
    installUrl = repository
    return true
  }

  function pluginInstallCommand(value) {
    const repository = extractInstallUrl(value)
    return repository === "" ? []
      : ["omarchy", "plugin", "add", repository, "--yes"]
  }

  function startInstall() {
    const command = pluginInstallCommand(installUrl)
    if (command.length === 0 || !installConfirmed || pluginInstall.running)
      return false
    installUrl = command[3]
    installStatus = "Validating and installing plugin …"
    pluginInstall.command = command
    pluginInstall.running = true
    return true
  }

  function dismissEscapeState() {
    if (quickPage.pendingAction !== "") {
      quickPage.cancelPendingAction()
      return true
    }
    if (paletteOpen) {
      closeWidgetPicker()
      return true
    }
    const pluginPage = pluginSearchPage()
    if (pluginPage !== null
        && (pluginPage.searchInputActiveFocus === true
          || String(pluginPage.pluginQuery || "") !== "")) {
      pluginPage.dismissPluginSearch()
      return true
    }
    if (settingsSearch.inputActiveFocus
        || settingsSearch.suggestionsVisible || settingsQuery !== "") {
      settingsSearch.handleEscape()
      return true
    }
    return false
  }

  Keys.onEscapePressed: function(event) {
    event.accepted = root.dismissEscapeState()
  }

  Shortcut {
    sequence: "Ctrl+K"
    enabled: !root.returnOnly
    onActivated: settingsSearch.forceInputFocus()
  }

  onReturnOnlyChanged: {
    if (!returnOnly) return
    closeWidgetPicker()
    setPage("quick")
  }

  NumberAnimation {
    id: pageScrollAnimation
    target: pageFlick
    property: "contentY"
    duration: 220
    easing.type: Easing.OutCubic
  }

  Column {
    anchors.fill: parent
    spacing: 0

    Item {
      id: searchBand
      z: settingsSearch.suggestionsVisible ? 50 : 5
      width: parent.width
      visible: !root.returnOnly
      height: visible ? Commons.Style.space(42)
        + settingsSearch.reservedPopupHeight : 0

      Rectangle {
        id: settingsSearchFrame
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: Commons.Style.space(4)
        anchors.leftMargin: Commons.Style.space(20)
        anchors.rightMargin: Commons.Style.space(20)
        height: Commons.Style.space(34)
        radius: root.controller.controlRadius
        color: "transparent"
        border.width: 1
        border.color: root.controller.controlBorderColor

        PredictiveSearchInput {
          id: settingsSearch
          anchors.fill: parent
          controller: root.controller
          entries: root.settingsSearchEntries
          placeholder: "Search settings, options, or plugins…"
          popupStyle: "catalog"
          suggestionLimit: 4
          hint: "CTRL K"
          foreground: root.foreground
          accent: root.accent
          uiScale: root.uiScale
          onEdited: function(value) {
            if (value.trim() !== ""
                && (root.currentPage === "quick"
                  || !root.configureDetailOpen)) {
              root.currentPage = "configure"
              root.configureDetailPage = root.lastConfigurePage
              root.scheduleConfigureRoute(root.lastConfigurePage)
            }
          }
        }
      }
    }

    Item {
      id: modeBand
      width: parent.width
      visible: !root.returnOnly
      height: visible ? Commons.Style.space(42) : 0

      Row {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: Commons.Style.space(20)
        anchors.rightMargin: Commons.Style.space(20)
        height: Commons.Style.space(31)
        spacing: Commons.Style.space(34)

        Rectangle {
          id: modeSelector
          width: Math.min(Commons.Style.space(270), parent.width * 0.42)
          height: parent.height
          radius: root.controller.controlRadius
          color: "transparent"
          border.width: 1
          border.color: root.controller.controlBorderColor
          clip: true

          Row {
            anchors.fill: parent
            anchors.margins: 2
            spacing: 0

            Repeater {
              model: [
                { value: "quick", label: "QUICK" },
                { value: "configure", label: "CONFIGURE" }
              ]

              delegate: Rectangle {
                id: modeOption
                required property var modelData
                readonly property bool active: modelData.value === "quick"
                  ? root.currentPage === "quick"
                  : root.currentPage !== "quick"
                width: parent.width / 2
                height: parent.height
                radius: Math.max(0, root.controller.controlRadius - 2)
                color: active || modeOptionPointer.containsMouse
                  ? root.controller.marketPanelRaised : "transparent"

                Text {
                  anchors.centerIn: parent
                  text: modeOption.modelData.label
                  color: root.foreground
                  opacity: modeOption.active || modeOptionPointer.containsMouse
                    ? 1 : 0.42
                  font.family: root.controller.marketFont
                  font.pixelSize: Commons.Style.font.caption * root.uiScale
                  font.weight: Font.DemiBold
                  font.letterSpacing: 0.8
                }

                MouseArea {
                  id: modeOptionPointer
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.setMode(modeOption.modelData.value)
                }
              }
            }
          }
        }

        Rectangle {
          id: statusSelector
          width: parent.width - x
          height: parent.height
          radius: root.controller.controlRadius
          color: "transparent"
          border.width: 1
          border.color: root.controller.controlBorderColor
          clip: true

          Row {
            anchors.fill: parent
            anchors.margins: 2
            spacing: 0

            Rectangle {
              id: healthStatusShortcut
              width: parent.width / 2
              height: parent.height
              radius: Math.max(0, root.controller.controlRadius - 2)
              color: healthStatusPointer.containsMouse
                || root.configureDetailPage === "health"
                ? root.controller.marketPanelRaised : "transparent"

              Text {
                anchors.centerIn: parent
                text: root.healthErrorCount > 0
                  ? "HEALTH  ·  " + root.healthErrorCount
                  : root.healthWarningCount > 0
                    ? "HEALTH  ·  REVIEW"
                    : root.healthPassed ? "HEALTH  ·  PASS" : "HEALTH"
                color: root.healthErrorCount > 0
                  ? root.healthErrorColor
                  : root.healthWarningCount > 0
                    ? root.accent
                    : root.healthPassed ? root.healthPassColor : root.foreground
                opacity: root.configureDetailPage === "health"
                  || healthStatusPointer.containsMouse ? 1 : 0.62
                font.family: root.controller.marketFont
                font.pixelSize: Commons.Style.font.caption * root.uiScale
                font.weight: Font.DemiBold
                font.letterSpacing: 0.8
              }

              MouseArea {
                id: healthStatusPointer
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.setPage("health")
              }
            }

            Rectangle {
              id: pluginRegistryStatus
              width: parent.width / 2
              height: parent.height
              radius: Math.max(0, root.controller.controlRadius - 2)
              color: pluginRegistryPointer.containsMouse
                || root.configureDetailPage === "plugins"
                ? root.controller.marketPanelRaised : "transparent"

              Row {
                anchors.centerIn: parent
                spacing: Commons.Style.space(6)
                opacity: root.configureDetailPage === "plugins"
                  || pluginRegistryPointer.containsMouse ? 1 : 0.62

                Text {
                  text: "PLUGINS"
                  color: root.foreground
                  font.family: root.controller.marketFont
                  font.pixelSize: Commons.Style.font.caption * root.uiScale
                  font.weight: Font.DemiBold
                  font.letterSpacing: 0.8
                }

                Text {
                  text: root.controller.registryShibumiPluginCount + " S · "
                    + root.controller.registryOmarchyPluginCount + " O · "
                    + root.controller.registryExternalPluginCount + " EXT"
                  color: root.registryValueColor
                  font.family: root.controller.marketFont
                  font.pixelSize: Commons.Style.font.caption * root.uiScale
                  font.weight: Font.DemiBold
                  font.letterSpacing: 0.8
                }
              }

              MouseArea {
                id: pluginRegistryPointer
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.setPage("plugins")
              }
            }
          }
        }
      }
    }

    Item {
      id: workspace
      width: parent.width
      height: parent.height - searchBand.height - modeBand.height
      clip: true

      Flickable {
        id: quickFlick
        z: 1
        anchors.fill: parent
        anchors.leftMargin: Commons.Style.space(20)
        anchors.rightMargin: Commons.Style.space(20)
        visible: root.currentPage === "quick"
        contentWidth: width
        contentHeight: quickPage.implicitHeight + Commons.Style.space(12)
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        clip: true

        QuickControlPage {
          id: quickPage
          width: parent.width
          controller: root.controller
          foreground: root.foreground
          accent: root.accent
          uiScale: root.uiScale
          motionActive: root.controller.open === true
            && root.currentPage === "quick" && !root.paletteOpen
        }
      }

      Flickable {
        id: configureLandingFlick
        z: 1
        anchors.fill: parent
        visible: !root.returnOnly && root.currentPage === "configure"
        contentWidth: width
        contentHeight: configureLanding.implicitHeight
          + Commons.Style.space(12)
        interactive: !root.configureDetailOpen
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        clip: true

        ConfigureLandingPage {
          id: configureLanding
          x: Commons.Style.space(20)
          width: parent.width - Commons.Style.space(40)
          controller: root.controller
          pageOptions: root.pageOptions
          foreground: root.foreground
          accent: root.accent
          uiScale: root.uiScale
          activePage: root.currentPage === "configure"
            && !root.configureDetailOpen
          detailOpen: root.configureDetailOpen
          barsChildRouteAvailable: root.barsChildRouteAvailable
          barsChildRouteActive: root.barsChildRouteActive
          barsChildRouteLabel: root.barsChildRouteLabel
          favoritesRouteAvailable: root.pluginFavoritesRouteAvailable
          favoritesRouteActive: root.pluginFavoritesRouteActive
          motionActive: root.controller.open === true
            && root.currentPage === "configure"
            && !root.configureDetailOpen && !root.paletteOpen
          onPageRequested: function(pageId) { root.setPage(pageId) }
          onBarsChildRequested: root.showBarsChildRoute()
          onFavoritesRequested: root.showPluginFavorites()
          onBackRequested: root.setPage("configure")
        }
      }

      Item {
        id: configureDetailPane
        z: 3
        x: Commons.Style.space(194)
        width: parent.width - x - Commons.Style.space(20)
        height: parent.height
        visible: !root.returnOnly && root.currentPage === "configure"
          && root.configureDetailOpen

        Flickable {
          id: pageFlick
          anchors.fill: parent
          contentWidth: width
          contentHeight: activePage.implicitHeight
            + Commons.Style.space(12)
          boundsBehavior: Flickable.StopAtBounds
          flickableDirection: Flickable.VerticalFlick
          clip: true

          Item {
            id: activePage
            width: parent.width
            implicitHeight: root.settingsQuery.trim() !== ""
              ? searchPage.implicitHeight
              : pageLoader.item ? pageLoader.item.implicitHeight : 1

            ControlSearchPage {
              id: searchPage
              width: parent.width
              visible: root.settingsQuery.trim() !== ""
              controller: root.controller
              pageOptions: root.pageOptions
              searchEntries: root.settingsSearchEntries
              query: root.settingsQuery
              foreground: root.foreground
              accent: root.accent
              uiScale: root.uiScale
              motionActive: root.controller.open === true
                && root.settingsQuery.trim() !== "" && !root.paletteOpen
              onPageRequested: function(pageId) { root.setPage(pageId) }
            }

            Loader {
              id: pageLoader
              width: parent.width
              height: item ? item.implicitHeight : 1
              visible: root.settingsQuery.trim() === ""
              sourceComponent: root.pageComponent(
                root.configureDetailPage)
              onLoaded: {
                if (root.configureDetailPage === "bars-motion"
                    && item.childRouteAvailable !== true) {
                  Qt.callLater(function() { root.setPage("bars") })
                  return
                }
                if (root.configureDetailPage === "functions"
                    && root.controller
                    && typeof root.controller.restoreWidgetDetails
                      === "function")
                  root.controller.restoreWidgetDetails(item)
              }
            }
          }
        }
      }

      ThinScrollBar {
        z: 6
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.topMargin: Commons.Style.space(4)
        anchors.rightMargin: Commons.Style.space(4)
        anchors.bottomMargin: Commons.Style.space(4)
        active: root.currentPage === "quick"
        flickable: quickFlick
        foreground: root.foreground
        accent: root.accent
      }

      ThinScrollBar {
        z: 6
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.topMargin: Commons.Style.space(4)
        anchors.rightMargin: Commons.Style.space(4)
        anchors.bottomMargin: Commons.Style.space(4)
        active: root.currentPage === "configure"
          && !root.configureDetailOpen
        flickable: configureLandingFlick
        foreground: root.foreground
        accent: root.accent
      }

      ThinScrollBar {
        z: 6
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.topMargin: Commons.Style.space(4)
        anchors.rightMargin: Commons.Style.space(4)
        anchors.bottomMargin: Commons.Style.space(4)
        active: root.currentPage === "configure"
          && root.configureDetailOpen
        flickable: pageFlick
        foreground: root.foreground
        accent: root.accent
      }
    }
  }

  TapHandler {
    enabled: settingsSearch.inputActiveFocus
      || (root.pluginSearchPage() !== null
        && root.pluginSearchPage().searchInputActiveFocus === true)
    acceptedButtons: Qt.LeftButton
    gesturePolicy: TapHandler.ReleaseWithinBounds

    onTapped: function(eventPoint, _button) {
      root.dismissSearchesAt(
        eventPoint.position.x, eventPoint.position.y)
    }
  }

  Rectangle {
    anchors.fill: parent
    visible: root.paletteOpen
    z: 20
    color: Qt.rgba(0, 0, 0, 0.58)

    MouseArea {
      anchors.fill: parent
      enabled: !pluginInstall.running
      onClicked: root.closeWidgetPicker()
    }

    Rectangle {
      id: commandPalette
      anchors.centerIn: parent
      width: Math.min(parent.width - Commons.Style.space(72),
        Commons.Style.space(560))
      height: installMode
        ? Commons.Style.space(292) : Commons.Style.space(410)
      radius: root.controller.controlRadius
      color: root.controller.marketPanel
      border.width: root.controller.controlBorderWidth
      border.color: root.controller.controlBorderColor

      MouseArea { anchors.fill: parent }

      Column {
        anchors.fill: parent
        anchors.margins: Commons.Style.space(14)
        spacing: Commons.Style.space(10)

        Row {
          width: parent.width
          height: Commons.Style.space(28)

          Text {
            width: parent.width - closePalette.width
            anchors.verticalCenter: parent.verticalCenter
            text: root.installMode ? "Install plugin from Git"
              : "Add plugin"
            color: root.foreground
            font.family: Commons.Style.font.menuFamily
            font.pixelSize: Commons.Style.font.heading * root.uiScale
            font.weight: Font.DemiBold
            renderType: Text.NativeRendering
          }

          Text {
            id: closePalette
            anchors.verticalCenter: parent.verticalCenter
            text: "ESC"
            color: root.foreground
            opacity: 0.42
            font.family: root.controller.marketFont
            font.pixelSize: Commons.Style.font.caption * root.uiScale
          }
        }

        Rectangle {
          width: parent.width
          height: Commons.Style.space(36)
          radius: root.controller.controlRadius
          color: root.controller.controlFillColor
          border.width: 1
          border.color: root.installMode && root.validInstallUrl
            ? root.controller.accentColor("color03")
            : root.installMode && installInput.activeFocus
              || !root.installMode && paletteSearch.activeFocus
            ? root.accent : root.controller.controlBorderColor

          TextInput {
            id: paletteSearch
            anchors.fill: parent
            anchors.leftMargin: Commons.Style.space(11)
            anchors.rightMargin: Commons.Style.space(11)
            visible: !root.installMode
            color: root.foreground
            selectionColor: Commons.Util.alpha(root.accent, 0.38)
            selectedTextColor: root.foreground
            verticalAlignment: TextInput.AlignVCenter
            clip: true
            text: root.query
            font.family: Commons.Style.font.menuFamily
            font.pixelSize: Commons.Style.font.bodySmall * root.uiScale
            font.weight: Font.Normal
            renderType: Text.NativeRendering
            onTextEdited: root.query = text
            Keys.onEscapePressed: function(event) {
              root.closeWidgetPicker()
              event.accepted = true
            }

            Text {
              anchors.fill: parent
              verticalAlignment: Text.AlignVCenter
              visible: parent.text === ""
              text: "Search bar plugins …"
              color: root.foreground
              opacity: 0.38
              font: parent.font
            }
          }

          TextInput {
            id: installInput
            anchors.fill: parent
            anchors.leftMargin: Commons.Style.space(11)
            anchors.rightMargin: Commons.Style.space(11)
            visible: root.installMode
            enabled: !pluginInstall.running
            color: root.foreground
            selectionColor: Commons.Util.alpha(root.accent, 0.38)
            selectedTextColor: root.foreground
            verticalAlignment: TextInput.AlignVCenter
            clip: true
            text: root.installUrl
            font.family: "monospace"
            font.pixelSize: Commons.Style.font.bodySmall * root.uiScale
            font.weight: Font.Normal
            renderType: Text.NativeRendering
            onTextEdited: {
              root.installUrl = text
              root.installConfirmed = false
              root.installStatus = ""
            }
            onEditingFinished: root.normalizeInstallInput()

            Text {
              anchors.fill: parent
              verticalAlignment: Text.AlignVCenter
              visible: parent.text === ""
              text: "https://github.com/…/plugin.git"
              color: root.foreground
              opacity: 0.38
              font: parent.font
            }
          }
        }

        Item {
          id: pluginResultsViewport
          width: parent.width
          height: root.installMode
            ? parent.height - y : parent.height - y

          Flickable {
            id: resultsFlick
            anchors.fill: parent
            visible: !root.installMode
            contentWidth: width
            contentHeight: resultsColumn.implicitHeight
            boundsBehavior: Flickable.StopAtBounds
            clip: true

            Column {
              id: resultsColumn
              width: parent.width
              spacing: 0

              Text {
                height: Commons.Style.space(24)
                text: "AVAILABLE PLUGINS"
                color: root.foreground
                opacity: 0.42
                font.family: Commons.Style.font.menuFamily
                font.pixelSize: Commons.Style.font.caption * root.uiScale
                font.weight: Font.Medium
                font.letterSpacing: 1
              }

              ProviderFilter {
                width: parent.width
                controller: root.controller
                selectedProvider: root.pickerProvider
                foreground: root.foreground
                accent: root.accent
                uiScale: root.uiScale
                onSelected: function(provider) {
                  root.pickerProvider = provider
                }
              }

              Flow {
                id: moduleBay
                width: parent.width
                spacing: Commons.Style.space(8)

                Repeater {
                  model: root.filteredPlugins

                  delegate: WidgetModuleTile {
                    id: moduleTile
                    required property var modelData
                    width: (moduleBay.width - moduleBay.spacing) / 2
                    controller: root.controller
                    glyph: modelData.glyph
                    label: modelData.name
                    provider: modelData.provider
                    relationship: modelData.replacementLabel || ""
                    inserted: modelData.installedInBar === true
                    foreground: root.foreground
                    accent: root.accent
                    uiScale: root.uiScale
                    onToggled: {
                      root.controller.setPluginEnabled(
                        moduleTile.modelData.id, !moduleTile.inserted)
                      root.closeWidgetPicker()
                    }
                  }
                }
              }

              Rectangle {
                width: parent.width
                height: 1
                color: root.controller.dividerColor
              }

              Rectangle {
                width: parent.width
                height: Commons.Style.space(42)
                radius: root.controller.controlRadius
                color: installPointer.containsMouse
                  ? root.controller.controlHoverFillColor : "transparent"

                Row {
                  anchors.fill: parent
                  anchors.leftMargin: Commons.Style.space(8)
                  anchors.rightMargin: Commons.Style.space(8)

                  Row {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - arrow.width
                    spacing: Commons.Style.space(8)

                    IconText {
                      anchors.verticalCenter: parent.verticalCenter
                      width: Commons.Style.space(18)
                      text: "download"
                      color: root.foreground
                      font.pixelSize: Commons.Style.font.iconLarge * root.uiScale
                    }

                    Text {
                      anchors.verticalCenter: parent.verticalCenter
                      text: "Install plugin from Git …"
                      color: root.foreground
                      font.family: Commons.Style.font.menuFamily
                      font.pixelSize: Commons.Style.font.bodySmall * root.uiScale
                    }
                  }

                  Text {
                    id: arrow
                    anchors.verticalCenter: parent.verticalCenter
                    text: "→"
                    color: root.accent
                    font.pixelSize: Commons.Style.font.body
                  }
                }

                MouseArea {
                  id: installPointer
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.showInstaller()
                }
              }
            }
          }

          ThinScrollBar {
            z: 2
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.topMargin: Commons.Style.space(3)
            anchors.rightMargin: -Commons.Style.space(8)
            anchors.bottomMargin: Commons.Style.space(3)
            active: !root.installMode
            flickable: resultsFlick
            foreground: root.foreground
            accent: root.accent
          }

          Column {
            anchors.fill: parent
            visible: root.installMode
            spacing: Commons.Style.space(10)

            Text {
              width: parent.width
              text: "Plugins run as unsandboxed code inside the long-lived Omarchy shell process. Only install repositories you trust and whose changes you have reviewed."
              color: root.foreground
              opacity: 0.68
              wrapMode: Text.WordWrap
              font.family: Commons.Style.font.menuFamily
              font.pixelSize: Commons.Style.font.caption * root.uiScale
              font.weight: Font.Normal
              renderType: Text.NativeRendering
            }

            Rectangle {
              id: riskConfirmation
              width: parent.width
              height: Commons.Style.space(32)
              radius: root.controller.controlRadius
              opacity: root.validInstallUrl ? 1 : 0.32
              color: root.installConfirmed
                ? Commons.Util.alpha(root.accent, 0.15)
                : root.controller.controlFillColor
              border.width: 1
              border.color: root.installConfirmed
                ? root.accent : root.validInstallUrl
                  ? root.controller.accentColor("color01")
                  : root.controller.controlBorderColor

              Behavior on opacity {
                NumberAnimation {
                  duration: 140
                  easing.type: Easing.OutCubic
                }
              }

              Rectangle {
                anchors.fill: parent
                radius: parent.radius
                color: "transparent"
                border.width: 1
                border.color: root.controller.accentColor("color01")
                visible: root.validInstallUrl && !root.installConfirmed

                SequentialAnimation on opacity {
                  running: root.paletteOpen && root.installMode
                    && root.validInstallUrl && !root.installConfirmed
                  loops: 2
                  NumberAnimation {
                    from: 0.28
                    to: 1
                    duration: 420
                    easing.type: Easing.InOutSine
                  }
                  NumberAnimation {
                    from: 1
                    to: 0.28
                    duration: 420
                    easing.type: Easing.InOutSine
                  }
                }
              }

              Text {
                anchors.centerIn: parent
                text: root.installConfirmed
                  ? "✓ Risk understood"
                  : "Understand and confirm the risk"
                color: root.installConfirmed ? root.accent : root.foreground
                font.family: root.controller.marketFont
                font.pixelSize:
                  Commons.Style.font.bodySmall * root.uiScale
                font.weight: Font.Medium
                renderType: Text.NativeRendering
              }

              MouseArea {
                anchors.fill: parent
                enabled: root.validInstallUrl && !pluginInstall.running
                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: root.installConfirmed = !root.installConfirmed
              }
            }

            Row {
              width: parent.width
              spacing: Commons.Style.space(8)

              CompactSettingChoice {
                width: (parent.width - parent.spacing) / 2
                controller: root.controller
                label: root.installerDirect ? "Cancel" : "Back"
                foreground: root.foreground
                accent: root.accent
                uiScale: root.uiScale
                onClicked: {
                  if (root.installerDirect) {
                    root.closeWidgetPicker()
                    return
                  }
                  root.installMode = false
                  root.installConfirmed = false
                  Qt.callLater(function() {
                    paletteSearch.forceActiveFocus()
                  })
                }
              }

              CompactSettingChoice {
                width: (parent.width - parent.spacing) / 2
                controller: root.controller
                label: pluginInstall.running ? "Installing …" : "Install"
                primary: root.validInstallUrl && root.installConfirmed
                foreground: root.foreground
                accent: root.accent
                uiScale: root.uiScale
                onClicked: root.startInstall()
              }
            }

            Text {
              width: parent.width
              visible: root.installStatus !== ""
                || root.installInputWasCommand
                || (root.installUrl !== "" && !root.validInstallUrl)
              text: root.installStatus !== "" ? root.installStatus
                : root.installInputWasCommand
                  ? "Repository detected: " + root.normalizedInstallUrl
                  : "Use an HTTPS, SSH, or git@ URL or paste an Omarchy add command."
              color: root.installStatus.indexOf("failed") >= 0
                ? Commons.Color.urgent : root.foreground
              opacity: 0.68
              wrapMode: Text.WordWrap
              font.family: Commons.Style.font.menuFamily
              font.pixelSize: Commons.Style.font.caption * root.uiScale
            }
          }
        }
      }
    }
  }

  Process {
    id: pluginInstall
    running: false
    stdout: StdioCollector {
      id: installStdout
      waitForEnd: true
    }
    stderr: StdioCollector {
      id: installStderr
      waitForEnd: true
    }
    onExited: function(exitCode) {
      if (exitCode === 0) {
        root.installStatus = "Installed. Refreshing the plugin list …"
        root.controller.rescanPlugins()
        root.installConfirmed = false
      } else {
        const detail = String(installStderr.text || installStdout.text || "")
          .trim().split("\n").slice(-1)[0]
        root.installStatus = "Installation failed"
          + (detail ? ": " + detail : ".")
      }
    }
  }

  Component {
    id: activeBarPage
    ActiveBarSettingsPage {
      controller: root.controller
      uiScale: root.uiScale
      foreground: root.foreground
      accent: root.accent
      motionDetailOpen: root.configureDetailPage === "bars-motion"
      motionActive: root.controller.open === true
        && (root.configureDetailPage === "bars"
          || root.configureDetailPage === "bars-motion")
        && root.settingsQuery.trim() === "" && !root.paletteOpen
    }
  }

  Component {
    id: overviewPage
    ControlOverviewPage {
      controller: root.controller
      uiScale: root.uiScale
      foreground: root.foreground
      accent: root.accent
      motionActive: root.controller.open === true
        && root.configureDetailPage === "main"
        && root.settingsQuery.trim() === "" && !root.paletteOpen
    }
  }

  Component {
    id: pluginsPage
    PluginCatalogPage {
      controller: root.controller
      favoritesOnly: root.pluginFavoritesOnly
      uiScale: root.uiScale
      foreground: root.foreground
      accent: root.accent
      motionActive: root.controller.open === true
        && root.configureDetailPage === "plugins"
        && root.settingsQuery.trim() === "" && !root.paletteOpen
    }
  }

  Component {
    id: workspacesPage
    WorkspaceSettingsPage {
      controller: root.controller
      uiScale: root.uiScale
      foreground: root.foreground
      accent: root.accent
      motionActive: root.controller.open === true
        && root.configureDetailPage === "workspaces"
        && root.settingsQuery.trim() === "" && !root.paletteOpen
    }
  }

  Component {
    id: pickersPage
    PickerSettingsPage {
      controller: root.controller
      uiScale: root.uiScale
      foreground: root.foreground
      accent: root.accent
      motionActive: root.controller.open === true
        && root.configureDetailPage === "pickers"
        && root.settingsQuery.trim() === "" && !root.paletteOpen
    }
  }

  Component {
    id: logoPage
    LogoSettingsPage {
      controller: root.controller
      uiScale: root.uiScale
      foreground: root.foreground
      accent: root.accent
      motionActive: root.controller.open === true
        && root.configureDetailPage === "logo"
        && root.settingsQuery.trim() === "" && !root.paletteOpen
    }
  }

  Component {
    id: functionsPage
    BarFunctionsPage {
      controller: root.controller
      uiScale: root.uiScale
      foreground: root.foreground
      accent: root.accent
      motionActive: root.controller.open === true
        && root.configureDetailPage === "functions"
        && root.settingsQuery.trim() === "" && !root.paletteOpen
    }
  }

  Component {
    id: healthPage
    ControlMainPage {
      controller: root.controller
      uiScale: root.uiScale
      foreground: root.foreground
      accent: root.accent
      motionActive: root.controller.open === true
        && root.configureDetailPage === "health"
        && root.settingsQuery.trim() === "" && !root.paletteOpen
    }
  }
}
