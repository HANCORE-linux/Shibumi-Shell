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
  property string currentPage: "bars"
  property bool paletteOpen: false
  property bool installMode: false
  property bool installConfirmed: false
  property string query: ""
  property string pickerProvider: "All"
  property string installUrl: ""
  property string installStatus: ""

  readonly property var pageOptions: [
    { id: "main", label: "Overview", glyph: "radio_button_checked" },
    { id: "bars", label: "Bars", glyph: "align_vertical_center" },
    { id: "plugins", label: "Widgets", glyph: "widgets" },
    { id: "functions", label: "Appearance", glyph: "brush" },
    { id: "splits", label: "Layout", glyph: "view_week" },
    { id: "preferences", label: "Advanced", glyph: "settings" }
  ]
  readonly property bool ready: navRepeater.count === pageOptions.length
    && pageReady
  readonly property bool pageReady: pageLoader.item !== null
    && pageLoader.item.ready === true
  readonly property var pageItem: pageLoader.item
  readonly property bool fitsWidth: implicitWidth <= width + 0.5
  readonly property var filteredPlugins: {
    const needle = query.trim().toLowerCase()
    const entries = (controller.pluginEntries || []).filter(
      function(entry) {
        return entry.barWidget === true
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

  implicitWidth: Commons.Style.space(720)
  implicitHeight: Commons.Style.space(500)

  function pageComponent(page) {
    if (page === "bars") return barsPage
    if (page === "plugins") return pluginsPage
    if (page === "splits") return splitPage
    if (page === "functions") return functionsPage
    if (page === "preferences") return preferencesPage
    return overviewPage
  }

  function setPage(value) {
    const next = String(value || "")
    if (!pageOptions.some(function(page) { return page.id === next }))
      return false
    currentPage = next
    return true
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
    if (!paletteOpen) return
    closeWidgetPicker()
    event.accepted = true
  }

  Row {
    anchors.fill: parent
    spacing: 0

    Rectangle {
      id: sidebar
      width: Commons.Style.space(154)
      height: parent.height
      color: root.controller.marketPanel

      Column {
        anchors.fill: parent
        anchors.rightMargin: Commons.Style.space(16)
        spacing: Commons.Style.space(4)

        Text {
          height: Commons.Style.space(34)
          verticalAlignment: Text.AlignVCenter
          text: "SHIBUMI"
          color: root.accent
          font.family: root.controller.marketFont
          font.pixelSize: Commons.Style.font.caption * root.uiScale
          font.weight: Font.DemiBold
          font.letterSpacing: 1.8
        }

        Text {
          width: parent.width
          height: Commons.Style.space(22)
          verticalAlignment: Text.AlignVCenter
          text: "CONTROL"
          color: root.foreground
          opacity: 0.42
          font.family: root.controller.marketFont
          font.pixelSize: Commons.Style.font.caption * root.uiScale
          font.letterSpacing: 1.4
        }

        Repeater {
          id: navRepeater
          model: root.pageOptions

          delegate: Rectangle {
            id: navItem
            required property var modelData
            width: parent.width
            height: Commons.Style.space(36)
            radius: 0
            color: root.currentPage === navItem.modelData.id
              ? root.controller.buttonFillColor : navPointer.containsMouse
                ? root.controller.controlHoverFillColor : "transparent"

            Rectangle {
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              width: Commons.Style.space(2)
              height: parent.height
              visible: root.currentPage === navItem.modelData.id
              color: root.accent
            }

            Row {
              anchors.fill: parent
              anchors.leftMargin: Commons.Style.space(9)
              spacing: Commons.Style.space(9)

              IconText {
                anchors.verticalCenter: parent.verticalCenter
                width: Commons.Style.space(18)
                text: navItem.modelData.glyph
                color: root.foreground
                opacity: root.currentPage === navItem.modelData.id ? 1 : 0.82
                horizontalAlignment: Text.AlignHCenter
                font.pixelSize: Commons.Style.font.iconLarge * root.uiScale
                font.weight: Font.Medium
                fill: 0
              }

              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: navItem.modelData.label
                color: root.currentPage === navItem.modelData.id
                  ? root.foreground : root.foreground
                opacity: root.currentPage === navItem.modelData.id ? 1 : 0.66
                font.family: root.controller.marketFont
                font.pixelSize: Commons.Style.font.subtitle * root.uiScale
                font.weight: root.currentPage === navItem.modelData.id
                  ? Font.Medium : Font.Normal
              }
            }

            MouseArea {
              id: navPointer
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.setPage(navItem.modelData.id)
            }
          }
        }

        Item { width: 1; height: Commons.Style.space(10) }

        Rectangle {
          width: parent.width
          height: 1
          color: root.controller.dividerColor
        }

        Text {
          width: parent.width
          text: root.controller.pluginsScanning
            ? "Refreshing plugin index …"
            : root.controller.availablePluginCount + " Plugins · Quattro"
          color: root.foreground
          opacity: 0.42
          wrapMode: Text.WordWrap
          font.family: root.controller.marketFont
          font.pixelSize: Commons.Style.font.caption * root.uiScale
        }
      }
    }

    Rectangle {
      width: 1
      height: parent.height
      color: root.controller.dividerColor
    }

    Item {
      width: parent.width - sidebar.width - 1
      height: parent.height

      Flickable {
        id: pageFlick
        anchors.fill: parent
        anchors.leftMargin: Commons.Style.space(22)
        contentWidth: width
        contentHeight: pageLoader.item
          ? pageLoader.item.implicitHeight + Commons.Style.space(12) : height
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        clip: true

        Loader {
          id: pageLoader
          width: parent.width - Commons.Style.space(8)
          height: item ? item.implicitHeight : 1
          sourceComponent: root.pageComponent(root.currentPage)
        }
      }
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
      radius: 0
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
              : "Add widget"
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
          radius: 0
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
              text: "Search widgets or plugins …"
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
          width: parent.width
          height: root.installMode
            ? parent.height - y : parent.height - y

          Flickable {
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
                text: "AVAILABLE WIDGETS"
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
                radius: 0
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
              radius: 0
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
    id: barsPage
    BarsPage {
      controller: root.controller
      uiScale: root.uiScale
      foreground: root.foreground
      accent: root.accent
    }
  }

  Component {
    id: overviewPage
    ControlOverviewPage {
      controller: root.controller
      uiScale: root.uiScale
      foreground: root.foreground
      accent: root.accent
    }
  }

  Component {
    id: pluginsPage
    PluginCatalogPage {
      controller: root.controller
      uiScale: root.uiScale
      foreground: root.foreground
      accent: root.accent
    }
  }

  Component {
    id: splitPage
    SplitSettingsPage {
      controller: root.controller
      uiScale: root.uiScale
      foreground: root.foreground
      accent: root.accent
    }
  }

  Component {
    id: functionsPage
    BarFunctionsPage {
      controller: root.controller
      uiScale: root.uiScale
      foreground: root.foreground
      accent: root.accent
    }
  }

  Component {
    id: preferencesPage
    ControlMainPage {
      controller: root.controller
      uiScale: root.uiScale
      foreground: root.foreground
      accent: root.accent
    }
  }
}
