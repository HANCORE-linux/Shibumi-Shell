pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons as Commons
import qs.Ui as Ui

ShibumiPanel {
  id: panel

  required property var ownerWidget
  required property var updateService
  property var stateService: null

  property string activeTab: "packages"
  property Component packagesComponent: Component {
    PackagesTab {
      updateService: panel.updateService
      panel: panel
    }
  }
  property Component themesComponent: Component {
    ThemesTab {
      updateService: panel.updateService
      panel: panel
    }
  }

  readonly property var widgetPreferences: {
    const config = stateService && stateService.config
      ? stateService.config : ({})
    const widgets = config.widgets || ({})
    const group = widgets.G3 || ({})
    return group[ownerWidget.moduleName] || ({})
  }
  readonly property bool packageBadgeEnabled:
    widgetPreferences.packageBadge !== false
  readonly property bool themeBadgeEnabled:
    widgetPreferences.themeBadge !== false
  readonly property string fontFamily: bar
    ? String(bar.fontFamily || Commons.Style.font.family)
    : Commons.Style.font.family

  owner: ownerWidget
  focusTarget: keyCatcher
  contentWidth: fittedContentWidth(Commons.Style.space(520))
  contentHeight: cappedContentHeight(Commons.Style.space(460))

  function setBadgePreference(key, value) {
    return stateService && typeof stateService.setWidgetSetting === "function"
      ? stateService.setWidgetSetting(
          "G3", ownerWidget.moduleName, key, value) : false
  }

  Component.onCompleted: activeTab = updateService.preferredTab()

  Ui.PanelKeyCatcher {
    id: keyCatcher
    anchors.fill: parent
    onCloseRequested: panel.ownerWidget.close()
    onTabRequested: function(direction) {
      panel.ownerWidget.switchPanel(direction)
    }
    onMoveRequested: function(dx, _dy) {
      if (dx < 0) panel.activeTab = "packages"
      else if (dx > 0) panel.activeTab = "themes"
    }

    Column {
      anchors.fill: parent
      spacing: Commons.Style.space(8)

      Item {
        id: header
        width: parent.width
        height: Commons.Style.space(28)

        Text {
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: "Updates"
          color: panel.controlForeground
          font.family: panel.fontFamily
          font.pixelSize: Commons.Style.font.heading
          font.weight: Font.Medium
          font.letterSpacing: 2
        }

        Row {
          anchors.right: closeButton.left
          anchors.rightMargin: Commons.Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
          spacing: Commons.Style.space(5)

          PanelButton {
            id: packageBadgeToggle
            panel: panel
            text: "PKG"
            selected: panel.packageBadgeEnabled
            enabled: panel.stateService !== null
            controlHeight: Commons.Style.space(22)
            fontSize: Commons.Style.font.caption
            fontWeight: Font.Medium
            idleTextColor: panel.controlMutedHigh
            hoverTextColor: panel.controlMutedHigh
            hoverBorderColor: panel.controlHoverBorderColor
            tooltipText: selected
              ? "Package count is shown in the badge"
              : "Package count is hidden from the badge"
            onClicked: panel.setBadgePreference(
              "packageBadge", !panel.packageBadgeEnabled)
          }

          PanelButton {
            id: themeBadgeToggle
            panel: panel
            text: "Themes"
            selected: panel.themeBadgeEnabled
            enabled: panel.stateService !== null
            controlHeight: Commons.Style.space(22)
            fontSize: Commons.Style.font.caption
            fontWeight: Font.Medium
            idleTextColor: panel.controlMutedHigh
            hoverTextColor: panel.controlMutedHigh
            hoverBorderColor: panel.controlHoverBorderColor
            tooltipText: selected
              ? "Theme count is shown in the badge"
              : "Theme count is hidden from the badge"
            onClicked: panel.setBadgePreference(
              "themeBadge", !panel.themeBadgeEnabled)
          }

          IconAction {
            icon: panel.updateService.busy ? "sync" : "refresh"
            enabled: !panel.updateService.busy
            tooltip: panel.updateService.busy
              ? "Checking packages and user themes"
              : "Check packages and user themes"
            onClicked: panel.updateService.refreshAll()
          }
        }

        IconAction {
          id: closeButton
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          icon: "close"
          tooltip: "Close"
          onClicked: panel.ownerWidget.close()
        }
      }

      Rectangle {
        width: parent.width
        height: 1
        color: panel.dividerColor
      }

      Row {
        width: parent.width
        height: Commons.Style.space(26)
        spacing: Commons.Style.space(6)

        Repeater {
          model: [
            {
              key: "packages",
              label: "Packages",
              count: panel.updateService.packageCount
            },
            {
              key: "themes",
              label: "Themes",
              count: panel.updateService.themeCount
            }
          ]

          delegate: PanelButton {
            required property var modelData
            width: (parent.width - Commons.Style.space(6)) / 2
            panel: panel
            text: modelData.label + (modelData.count > 0
              ? "  " + modelData.count : "")
            selected: panel.activeTab === modelData.key
            controlHeight: Commons.Style.space(26)
            onClicked: panel.activeTab = modelData.key
          }
        }
      }

      Item {
        width: parent.width
        height: Math.max(1, parent.height - y)

        Loader {
          anchors.fill: parent
          active: panel.activeTab === "packages"
          sourceComponent: packagesComponent
        }

        Loader {
          anchors.fill: parent
          active: panel.activeTab === "themes"
          sourceComponent: themesComponent
        }
      }
    }
  }

  component IconAction: Ui.CursorSurface {
    id: action
    property string icon: ""
    property string tooltip: ""
    signal clicked()
    implicitWidth: Commons.Style.space(28)
    implicitHeight: Commons.Style.space(28)
    radius: panel.controlRadius
    foreground: panel.bar ? panel.bar.foreground : Commons.Color.foreground
    accent: panel.bar ? panel.bar.urgent : Commons.Color.accent
    opacity: enabled ? 1 : 0.35

    IconText {
      anchors.centerIn: parent
      text: action.icon
      color: action.foreground
      font.pixelSize: Commons.Style.font.body
    }

    MouseArea {
      id: actionMouse
      anchors.fill: parent
      hoverEnabled: true
      enabled: action.enabled
      cursorShape: action.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
      onContainsMouseChanged: action.hasCursor = containsMouse
      onClicked: action.clicked()
    }

    ShibumiPanelToolTip {
      panel: panel
      visible: action.tooltip !== "" && actionMouse.containsMouse
      text: action.tooltip
    }
  }
}
