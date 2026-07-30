pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons as Commons
import qs.Ui as Ui

Ui.BorderSurface {
  id: root

  required property var controller
  readonly property var barController: controller.barController || null
  readonly property var tokens: barController
    && "visualTokens" in barController ? barController.visualTokens : null
  property int availableWidth: Commons.Style.space(800)
  property int availableHeight: Commons.Style.space(600)
  readonly property real uiScale: Math.max(0.6, Math.min(1.0,
    Number(controller.presentationScale || 100) / 100))
  readonly property int cardWidth: Math.min(
    Commons.Style.space(260) * (controller.settingsOpen ? 1 : uiScale),
    Math.max(1, availableWidth))
  readonly property int rowHeight: Math.round(Commons.Style.space(38) * uiScale)
  readonly property int appRowHeight: Math.round(Commons.Style.space(42) * uiScale)
  readonly property int headerHeight: Math.round(Commons.Style.space(26) * uiScale)
  readonly property int searchHeight: Math.round(Commons.Style.space(34) * uiScale)
  readonly property int contentPadding: Math.round(Commons.Style.space(10) * uiScale)
  readonly property int contentSpacing: Math.round(Commons.Style.space(6) * uiScale)
  readonly property int settingsHeight: settingsViewport.visible
    ? Math.ceil(settingsPane.implicitHeight) : 0
  readonly property int rowsHeight: {
    if (controller.visibleRows.length === 0) return rowHeight * 2
    let total = 0
    const count = Math.min(10, controller.visibleRows.length)
    for (let i = 0; i < count; i++)
      total += controller.visibleRows[i].isApp ? appRowHeight : rowHeight
    return total
  }
  readonly property int cardHeight: Math.min(
    controller.settingsOpen
      ? contentPadding * 2 + headerHeight + contentSpacing + settingsHeight
      : contentPadding * 2 + headerHeight + searchHeight + contentSpacing * 2
        + rowsHeight,
    availableHeight)
  readonly property color foreground: tokens ? tokens.ink : Commons.Color.menu.text
  readonly property color accent: tokens ? tokens.seal : Commons.Color.menu.selectedText
  readonly property real controlRadius: tokens
    ? tokens.tileRadius : Math.min(Commons.Style.space(6), Commons.Style.cornerRadius)
  readonly property var surfaceBorder: tokens
    ? Commons.Border.flat(tokens.panelBorder, tokens.panelBorderWidth)
    : Commons.Border.surfaceSpec("menu", "border", Commons.Color.menu.border,
      Math.max(1, Commons.Style.normalBorderWidth))
  readonly property int surfaceBorderWidth: tokens ? tokens.panelBorderWidth
    : Commons.Border.uniformWidth(surfaceBorder)
  readonly property int renderedRowCount: resultList.count
  readonly property bool settingsRendered: settingsViewport.visible
  readonly property bool settingsReady: settingsPane.ready
  readonly property bool settingsFitWidth: settingsPane.fitsWidth
  readonly property real settingsContentHeight: settingsFlick.contentHeight
  readonly property real settingsViewportHeight: settingsFlick.height
  readonly property bool settingsScrollRequired: settingsViewport.visible
    && settingsFlick.contentHeight > settingsFlick.height + 0.5
  readonly property bool fullBackgroundRendered: fullBackgroundLoader.active
  readonly property bool searchBackgroundRendered: searchBackgroundLoader.active

  width: cardWidth
  height: cardHeight
  radius: tokens ? tokens.panelRadius : Commons.Style.cornerRadius
  color: tokens ? tokens.panelBackground : Commons.Color.menu.background
  borderSpec: surfaceBorder
  padding: Math.max(0, contentPadding - surfaceBorderWidth)
  clip: true

  function focusSearch() {
    searchField.forceActiveFocus()
  }

  function syncSearchText() {
    if (searchField.text !== controller.query)
      searchField.text = controller.query
  }

  Loader {
    id: fullBackgroundLoader
    anchors.top: parent.top
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.left: parent.left
    anchors.topMargin: root.borderTop
    anchors.rightMargin: root.borderRight
    anchors.bottomMargin: root.borderBottom
    anchors.leftMargin: root.borderLeft
    active: root.controller.backgroundMode === "full"
      && root.controller.backgroundUrl !== ""
    z: 0
    sourceComponent: Image {
      source: root.controller.backgroundUrl
      fillMode: Image.PreserveAspectCrop
      asynchronous: true
      cache: true
      retainWhileLoading: true
      sourceSize.width: Math.max(1, root.cardWidth * 2)
      sourceSize.height: Math.max(1, root.cardHeight * 2)
    }
  }

  Rectangle {
    anchors.top: parent.top
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.left: parent.left
    anchors.topMargin: root.borderTop
    anchors.rightMargin: root.borderRight
    anchors.bottomMargin: root.borderBottom
    anchors.leftMargin: root.borderLeft
    visible: root.controller.backgroundMode === "full"
      && root.controller.backgroundUrl !== ""
    color: Commons.Util.alpha(root.color, 0.68)
    z: 1
  }

  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.RightButton | Qt.BackButton
    onClicked: {
      if (!root.controller.goBack()) root.controller.dismiss()
    }
    z: 2
  }

  Column {
    id: contentColumn
    anchors.fill: parent
    anchors.topMargin: root.contentTopInset
    anchors.rightMargin: root.contentRightInset
    anchors.bottomMargin: root.contentBottomInset
    anchors.leftMargin: root.contentLeftInset
    spacing: root.contentSpacing
    z: 3

    Item {
      id: header
      width: parent.width
      height: root.headerHeight

      Ui.PanelActionButton {
        id: backButton
        visible: root.controller.activeRoute !== "root"
          || root.controller.query !== "" || root.controller.appEditMode
        anchors.left: header.left
        anchors.verticalCenter: header.verticalCenter
        size: root.headerHeight
        iconText: "‹"
        radius: root.controlRadius
        fontSize: Commons.Style.font.heading * root.uiScale
        foreground: root.foreground
        tooltipText: "Back"
        onClicked: root.controller.goBack()
      }

      Text {
        anchors.left: backButton.visible ? backButton.right : header.left
        anchors.leftMargin: backButton.visible ? Commons.Style.spacing.xs : 0
        anchors.right: editButton.visible ? editButton.left : settingsButton.left
        anchors.rightMargin: Commons.Style.spacing.xs
        anchors.verticalCenter: header.verticalCenter
        text: root.controller.menuTitle
        color: root.foreground
        font.family: Commons.Style.font.menuFamily
        font.pixelSize: Commons.Style.font.body * root.uiScale
        font.weight: Font.Medium
        elide: Text.ElideRight
      }

      Ui.PanelActionButton {
        id: editButton
        visible: root.controller.appMode && !root.controller.settingsOpen
        anchors.right: settingsButton.left
        anchors.rightMargin: Commons.Style.spacing.xs
        anchors.verticalCenter: header.verticalCenter
        size: root.headerHeight
        iconText: "✎"
        radius: root.controlRadius
        fontSize: Commons.Style.font.body * root.uiScale
        foreground: root.controller.appEditMode ? root.accent : root.foreground
        tooltipText: root.controller.appEditMode
          ? "Finish app organization" : "Organize apps"
        onClicked: {
          root.controller.setAppEditMode(!root.controller.appEditMode)
          root.focusSearch()
        }
      }

      Ui.PanelActionButton {
        id: settingsButton
        anchors.right: closeButton.left
        anchors.rightMargin: Commons.Style.spacing.xs
        anchors.verticalCenter: header.verticalCenter
        size: root.headerHeight
        iconText: "⚙"
        radius: root.controlRadius
        fontSize: Commons.Style.font.body * root.uiScale
        foreground: root.controller.settingsOpen ? root.accent : root.foreground
        tooltipText: root.controller.settingsOpen
          ? "Close menu settings" : "Menu settings"
        onClicked: {
          if (root.controller.settingsOpen) root.controller.goBack()
          else root.controller.openSettings()
        }
      }

      Ui.PanelActionButton {
        id: closeButton
        anchors.right: header.right
        anchors.verticalCenter: header.verticalCenter
        size: root.headerHeight
        iconText: "×"
        radius: root.controlRadius
        fontSize: Commons.Style.font.body * root.uiScale
        foreground: root.foreground
        tooltipText: "Close"
        onClicked: root.controller.dismiss()
      }
    }

    Item {
      id: searchBox
      width: parent.width
      height: root.searchHeight
      visible: !root.controller.settingsOpen
      clip: true

      Loader {
        id: searchBackgroundLoader
        anchors.fill: parent
        active: root.controller.backgroundMode === "search"
          && root.controller.backgroundUrl !== ""
        sourceComponent: Image {
          source: root.controller.backgroundUrl
          fillMode: Image.PreserveAspectCrop
          asynchronous: true
          cache: true
          retainWhileLoading: true
          sourceSize.width: Math.max(1, searchBox.width * 2)
          sourceSize.height: Math.max(1, searchBox.height * 2)
        }
      }

      Rectangle {
        anchors.fill: parent
        visible: root.controller.backgroundMode === "search"
          && root.controller.backgroundUrl !== ""
        color: Commons.Util.alpha(root.color, 0.58)
      }

      ShibumiTextField {
        id: searchField
        anchors.fill: parent
        placeholderText: root.controller.appMode
          ? "Search applications…" : "Search commands…"
        foreground: root.foreground
        accent: root.accent
        controlRadius: root.controlRadius
        font.family: Commons.Style.font.menuFamily
        font.pixelSize: Commons.Style.font.body * root.uiScale
        verticalPadding: Commons.Style.spacing.xs
        onTextChanged: {
          if (searchField.text !== root.controller.query)
            root.controller.setQuery(searchField.text)
        }

        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) {
            if (!root.controller.goBack()) root.controller.dismiss()
            root.syncSearchText()
            event.accepted = true
          } else if (event.key === Qt.Key_Backspace && searchField.text.length === 0) {
            if (root.controller.goBack()) root.syncSearchText()
            event.accepted = true
          } else if (event.key === Qt.Key_Left && searchField.text.length === 0) {
            if (root.controller.goBack()) root.syncSearchText()
            event.accepted = true
          } else if (event.key === Qt.Key_Up) {
            root.controller.select(-1)
            event.accepted = true
          } else if (event.key === Qt.Key_Down) {
            root.controller.select(1)
            event.accepted = true
          } else if (event.key === Qt.Key_PageUp) {
            root.controller.select(-6)
            event.accepted = true
          } else if (event.key === Qt.Key_PageDown) {
            root.controller.select(6)
            event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
              || event.key === Qt.Key_Right) {
            if (!root.controller.cursorActive && root.controller.visibleRows.length > 0)
              root.controller.selectIndex(0)
            if (root.controller.visibleRows.length > 0)
              root.controller.activateIndex(root.controller.selectedIndex)
            root.syncSearchText()
            event.accepted = true
          }
        }
      }
    }

    Item {
      width: parent.width
      height: Math.max(0, root.height - root.contentPadding * 2
        - root.headerHeight - root.searchHeight - root.contentSpacing * 2
        )
      visible: !root.controller.settingsOpen
      clip: true

      ListView {
        id: resultList
        anchors.fill: parent
        model: root.controller.visibleRows
        currentIndex: root.controller.cursorActive
            && root.controller.selectionStyle !== "default"
          ? root.controller.selectedIndex : -1
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        highlightFollowsCurrentItem: true
        highlightMoveDuration: root.controller.selectionStyle === "glide" ? 140 : 0
        highlightResizeDuration: root.controller.selectionStyle === "glide" ? 100 : 0
        highlight: Rectangle {
          radius: root.controlRadius
          border.width: Math.max(1, Commons.Style.normalBorderWidth)
          border.color: Commons.Util.alpha(root.accent, 0.36)
          gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop {
              position: 0
              color: Commons.Util.alpha(root.accent,
                root.controller.selectionStyle === "gradient" ? 0.24 : 0.15)
            }
            GradientStop {
              position: 1
              color: Commons.Util.alpha(root.accent,
                root.controller.selectionStyle === "gradient" ? 0.02 : 0.15)
            }
          }
        }

        section.property: "section"
        section.criteria: ViewSection.FullString
        section.delegate: Item {
          required property string section
          width: ListView.view.width
          height: section === "drilldown" ? Commons.Style.spacing.md : 0
          visible: height > 0
          Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            height: Commons.Style.spacing.hairline
            color: Commons.Util.alpha(root.foreground, 0.18)
          }
        }

        delegate: Item {
          id: rowHost
          required property var modelData
          required property int index
          width: ListView.view.width
          height: modelData.isApp ? root.appRowHeight : root.rowHeight
          z: 1

          MenuAppRow {
            anchors.fill: rowHost
            visible: rowHost.modelData.isApp
            rowData: rowHost.modelData
            rowIndex: rowHost.index
            selected: root.controller.cursorActive
              && root.controller.selectedIndex === rowHost.index
            editMode: root.controller.appEditMode
            showIcon: root.controller.showIcons
            uiScale: root.uiScale
            selectionStyle: root.controller.selectionStyle
            controlRadius: root.controlRadius
            controller: root.controller
          }

          MenuCommandRow {
            anchors.fill: rowHost
            visible: !rowHost.modelData.isApp
            rowData: rowHost.modelData
            rowIndex: rowHost.index
            selected: root.controller.cursorActive
              && root.controller.selectedIndex === rowHost.index
            showIcon: root.controller.showIcons
            uiScale: root.uiScale
            selectionStyle: root.controller.selectionStyle
            controlRadius: root.controlRadius
            controller: root.controller
          }
        }

        Connections {
          target: root.controller
          function onSelectedIndexChanged() {
            if (root.controller.cursorActive && resultList.count > 0)
              resultList.positionViewAtIndex(
                root.controller.selectedIndex, ListView.Contain)
          }
          function onQueryChanged() { root.syncSearchText() }
        }
      }

      Column {
        anchors.centerIn: parent
        visible: root.controller.visibleRows.length === 0
        spacing: Commons.Style.spacing.xs

        Text {
          width: root.cardWidth - root.contentPadding * 2
          text: "󰈉"
          color: root.accent
          opacity: 0.8
          font.family: Commons.Style.font.menuFamily
          font.pixelSize: Commons.Style.font.display * root.uiScale
          horizontalAlignment: Text.AlignHCenter
        }

        Text {
          width: root.cardWidth - root.contentPadding * 2
          text: root.controller.emptyMessage
          color: root.foreground
          opacity: 0.68
          font.family: Commons.Style.font.menuFamily
          font.pixelSize: Commons.Style.font.bodySmall * root.uiScale
          horizontalAlignment: Text.AlignHCenter
          wrapMode: Text.Wrap
        }
      }
    }

    Item {
      id: settingsViewport
      width: parent.width
      height: Math.max(0, root.height - root.contentPadding * 2
        - root.headerHeight - root.contentSpacing)
      visible: root.controller.settingsOpen
      clip: true

      Flickable {
        id: settingsFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: settingsPane.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick

        MenuSettings {
          id: settingsPane
          width: settingsFlick.width
          controller: root.controller
          uiScale: root.uiScale
          foreground: root.foreground
          accent: root.accent
          controlRadius: root.controlRadius
        }
      }

      Rectangle {
        anchors.right: parent.right
        width: 2
        height: Math.max(18,
          settingsViewport.height * settingsFlick.visibleArea.heightRatio)
        y: settingsFlick.visibleArea.yPosition * settingsViewport.height
        visible: root.settingsScrollRequired
        radius: 1
        color: root.accent
        opacity: 0.58
      }
    }

  }
}
