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
  property alias settingsQuery: settingsSearch.text
  property bool paletteOpen: false
  property bool installMode: false
  property bool installConfirmed: false
  property string query: ""
  property string pickerProvider: "All"
  property string installUrl: ""
  property string installStatus: ""
  readonly property real routeActivationViewportRatio: 2 / 3

  readonly property var pageOptions: {
    const pages = [
      { id: "bars", label: "Bars", glyph: "align_vertical_center" },
      { id: "functions", label: "Icons", glyph: "brush" },
      { id: "logo", label: "Logo", glyph: "branding_watermark" },
      { id: "workspaces", label: "Workspaces", glyph: "grid_view" },
      { id: "pickers", label: "Pickers", glyph: "collections" },
      { id: "plugins", label: "Plugins", glyph: "extension" },
      { id: "preferences", label: "Advanced", glyph: "settings" }
    ]
    return controller.stockOmarchyHost
      ? pages.filter(function(page) {
          return page.id !== "plugins" && page.id !== "splits"
        })
      : pages
  }
  readonly property var settingsSearchEntries: {
    const pageKeywords = {
      bars: "bars shell omarchy shibumi switch continuity layout v1 v2 "
        + "split gap slots divider separator full fit dock notch position "
        + "surface color accent border panel tooltip",
      plugins: "widgets modules plugins add install enable disable remove "
        + "delete provider active available",
      workspaces: "workspace workspaces count active marker style navigation",
      pickers: "picker pickers theme wallpaper screenshot video media browser",
      logo: "logo launcher identity wordmark icon",
      functions: "icons icon appearance widget color surface style content "
        + "tone shape spacing opacity outline",
      preferences: "advanced reload reset power lock suspend reboot shutdown"
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
  readonly property bool configureDetailOpen: configureDetailPage !== ""
  readonly property bool barsSurfaceAvailable:
    currentPage === "configure" && configureDetailPage === "bars"
    && pageLoader.item !== null
    && pageLoader.item.surfaceSectionAvailable === true
  readonly property real barsSurfaceTargetY: {
    if (!barsSurfaceAvailable
        || pageLoader.item.surfaceSectionY === undefined)
      return -1
    return Number(pageLoader.item.surfaceSectionY)
  }
  readonly property real detailScrollMaximum: Math.max(
    0, pageFlick.contentHeight - pageFlick.height)
  readonly property real barsSurfaceActivationY: {
    if (barsSurfaceTargetY < 0) return -1
    // Shared scrollspy convention: activate a child route once its heading
    // reaches the upper two thirds of the visible detail viewport.
    const requested = Math.max(0, barsSurfaceTargetY
      - pageFlick.height * routeActivationViewportRatio)
    return Math.min(requested, detailScrollMaximum)
  }
  readonly property bool barsSurfaceRouteActive:
    barsSurfaceActivationY >= 0
    && pageFlick.contentY >= barsSurfaceActivationY - 0.5
  readonly property bool pluginFavoritesRouteAvailable:
    currentPage === "configure" && configureDetailPage === "plugins"
  readonly property bool pluginFavoritesRouteActive:
    pluginFavoritesRouteAvailable && pluginFavoritesOnly
  readonly property string restorePage: currentPage === "configure"
    && configureDetailOpen ? configureDetailPage : currentPage
  readonly property bool ready: quickPage.ready
    && configureLanding.ready && pageReady
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
  readonly property bool validInstallUrl: /^(https:\/\/|ssh:\/\/|git@)[^\s]+$/i
    .test(installUrl.trim())
  readonly property var validPageIds: pageOptions.map(function(page) {
    return page.id
  }).concat(["quick", "configure", "main"]).concat(
    controller.stockOmarchyHost ? [] : ["splits"])

  implicitWidth: Commons.Style.space(720)
  implicitHeight: Commons.Style.space(500)

  function pageComponent(page) {
    if (page === "bars") return activeBarPage
    if (page === "plugins") return pluginsPage
    if (page === "workspaces") return workspacesPage
    if (page === "pickers") return pickersPage
    if (page === "logo") return logoPage
    if (page === "splits") return splitPage
    if (page === "functions") return functionsPage
    if (page === "preferences") return preferencesPage
    return overviewPage
  }

  function setPage(value) {
    const next = String(value || "")
    if (validPageIds.indexOf(next) < 0)
      return false
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
      Qt.callLater(function() { configureLanding.forceActiveFocus() })
      return true
    }
    pluginFavoritesOnly = false
    configureDetailPage = next
    lastConfigurePage = next
    Qt.callLater(function() {
      configureLanding.showRoute(next)
      pageScrollAnimation.stop()
      pageFlick.contentY = 0
    })
    return true
  }

  function scrollToBarSurface() {
    if (!barsSurfaceAvailable || barsSurfaceTargetY < 0) return false
    pageScrollAnimation.stop()
    pageScrollAnimation.from = pageFlick.contentY
    pageScrollAnimation.to = Math.max(0, Math.min(
      detailScrollMaximum, barsSurfaceTargetY - Commons.Style.space(8)))
    pageScrollAnimation.start()
    return true
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
    if (next !== "configure") return false
    return setPage("configure")
  }

  function focusPredictiveSettingsSearch() {
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
    query = ""
    pickerProvider = "All"
    installMode = false
    installConfirmed = false
    installStatus = ""
    paletteOpen = true
    Qt.callLater(function() { paletteSearch.forceActiveFocus() })
    return true
  }

  function closeWidgetPicker() {
    if (pluginInstall.running) return false
    paletteOpen = false
    installMode = false
    installConfirmed = false
    return true
  }

  function showInstaller() {
    installMode = true
    installConfirmed = false
    installStatus = ""
    Qt.callLater(function() { installInput.forceActiveFocus() })
  }

  function startInstall() {
    if (!validInstallUrl || !installConfirmed || pluginInstall.running)
      return false
    installStatus = "Validating and installing plugin …"
    pluginInstall.command = [
      "omarchy", "plugin", "add", installUrl.trim(), "--yes"
    ]
    pluginInstall.running = true
    return true
  }

  Keys.onEscapePressed: function(event) {
    if (paletteOpen) {
      closeWidgetPicker()
      event.accepted = true
      return
    }
    if (settingsQuery !== "") {
      settingsQuery = ""
      event.accepted = true
    }
  }

  Shortcut {
    sequence: "Ctrl+K"
    onActivated: settingsSearch.forceInputFocus()
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
      height: Commons.Style.space(42)
        + settingsSearch.reservedPopupHeight

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
              Qt.callLater(function() {
                configureLanding.showRoute(root.lastConfigurePage)
              })
            }
          }
        }
      }
    }

    Item {
      id: modeBand
      width: parent.width
      height: Commons.Style.space(42)

      Row {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: Commons.Style.space(20)
        anchors.rightMargin: Commons.Style.space(20)
        height: Commons.Style.space(31)
        spacing: Commons.Style.space(6)

        Rectangle {
          id: modeSelector
          width: Commons.Style.space(206)
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
                color: active
                  ? root.controller.marketPanelRaised : "transparent"

                Text {
                  anchors.centerIn: parent
                  text: modeOption.modelData.label
                  color: root.foreground
                  opacity: modeOption.active ? 1 : 0.42
                  font.family: root.controller.marketFont
                  font.pixelSize: Commons.Style.font.caption * root.uiScale
                  font.weight: Font.DemiBold
                  font.letterSpacing: 0.8
                }

                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.setMode(modeOption.modelData.value)
                }
              }
            }
          }
        }

        Rectangle {
          id: widgetsShortcut
          width: Commons.Style.space(178)
          height: parent.height
          radius: root.controller.controlRadius
          color: widgetsShortcutPointer.containsMouse
            || root.configureDetailPage === "plugins"
            ? root.controller.marketPanelRaised : "transparent"
          opacity: root.controller.stockOmarchyHost ? 0.34 : 1
          border.width: 1
          border.color: root.configureDetailPage === "plugins"
            ? root.accent : root.controller.controlBorderColor

          Text {
            anchors.centerIn: parent
            text: "PLUGINS  " + root.controller.enabledWidgetCount
              + " / " + root.controller.availableWidgetCount
            color: root.foreground
            font.family: root.controller.marketFont
            font.pixelSize: Commons.Style.font.caption * root.uiScale
            font.weight: Font.DemiBold
            font.letterSpacing: 0.8
          }

          MouseArea {
            id: widgetsShortcutPointer
            anchors.fill: parent
            enabled: !root.controller.stockOmarchyHost
            hoverEnabled: true
            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: root.setPage("plugins")
          }
        }

        Rectangle {
          id: pluginRegistryStatus
          width: parent.width - x
          height: parent.height
          radius: root.controller.controlRadius
          color: "transparent"
          border.width: 1
          border.color: root.controller.controlBorderColor

          Text {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Commons.Style.space(10)
            anchors.rightMargin: Commons.Style.space(10)
            text: "REGISTRY  "
              + root.controller.registryShibumiPluginCount + " SHIBUMI · "
              + root.controller.registryOmarchyPluginCount + " OMARCHY · "
              + root.controller.registryExternalPluginCount + " EXT"
            color: root.foreground
            opacity: 0.62
            elide: Text.ElideRight
            horizontalAlignment: Text.AlignHCenter
            font.family: root.controller.marketFont
            font.pixelSize: Commons.Style.font.caption * root.uiScale
            font.weight: Font.DemiBold
            font.letterSpacing: 0.8
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
        visible: root.currentPage === "configure"
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
          surfaceRouteAvailable: root.barsSurfaceAvailable
          surfaceRouteActive: root.barsSurfaceRouteActive
          favoritesRouteAvailable: root.pluginFavoritesRouteAvailable
          favoritesRouteActive: root.pluginFavoritesRouteActive
          motionActive: root.controller.open === true
            && root.currentPage === "configure"
            && !root.configureDetailOpen && !root.paletteOpen
          onPageRequested: function(pageId) { root.setPage(pageId) }
          onSurfaceRequested: root.scrollToBarSurface()
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
        visible: root.currentPage === "configure"
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
          }

          Text {
            id: closePalette
            anchors.verticalCenter: parent.verticalCenter
            text: "ESC"
            color: root.foreground
            opacity: 0.42
            font.family: "monospace"
            font.pixelSize: Commons.Style.font.caption * root.uiScale
          }
        }

        Rectangle {
          width: parent.width
          height: Commons.Style.space(36)
          radius: root.controller.controlRadius
          color: root.controller.controlFillColor
          border.width: 1
          border.color: root.installMode && installInput.activeFocus
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
            font.pixelSize: Commons.Style.font.caption * root.uiScale
            onTextEdited: {
              root.installUrl = text
              root.installConfirmed = false
              root.installStatus = ""
            }

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
            }

            Rectangle {
              width: parent.width
              height: Commons.Style.space(32)
              radius: root.controller.controlRadius
              color: root.installConfirmed
                ? Commons.Util.alpha(root.accent, 0.15)
                : root.controller.controlFillColor
              border.width: 1
              border.color: root.installConfirmed
                ? root.accent : root.controller.controlBorderColor

              Text {
                anchors.centerIn: parent
                text: root.installConfirmed
                  ? "✓ Risk understood"
                  : "Understand and confirm the risk"
                color: root.installConfirmed ? root.accent : root.foreground
                font.family: Commons.Style.font.menuFamily
                font.pixelSize: Commons.Style.font.caption * root.uiScale
                font.weight: Font.Medium
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
                label: "Back"
                foreground: root.foreground
                accent: root.accent
                uiScale: root.uiScale
                onClicked: {
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
                || (root.installUrl !== "" && !root.validInstallUrl)
              text: root.installStatus !== "" ? root.installStatus
                : "Use an HTTPS, SSH, or git@ URL."
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
      motionActive: root.controller.open === true
        && root.configureDetailPage === "bars"
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
    id: splitPage
    SplitSettingsPage {
      controller: root.controller
      uiScale: root.uiScale
      foreground: root.foreground
      accent: root.accent
      motionActive: root.controller.open === true
        && root.configureDetailPage === "splits"
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
    id: preferencesPage
    ControlMainPage {
      controller: root.controller
      uiScale: root.uiScale
      foreground: root.foreground
      accent: root.accent
      motionActive: root.controller.open === true
        && root.configureDetailPage === "preferences"
        && root.settingsQuery.trim() === "" && !root.paletteOpen
    }
  }
}
