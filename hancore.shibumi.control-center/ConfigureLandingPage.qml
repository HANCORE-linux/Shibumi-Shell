pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons as Commons

Column {
  id: root

  required property var controller
  required property var pageOptions
  property real uiScale: 1
  property color foreground: Commons.Color.menu.text
  property color accent: Commons.Color.menu.selectedText
  property bool motionActive: false
  property bool activePage: false
  property bool detailOpen: false
  property bool barsChildRouteAvailable: false
  property bool barsChildRouteActive: false
  property string barsChildRouteLabel: ""
  property bool favoritesRouteAvailable: false
  property bool favoritesRouteActive: false
  property bool transitioning: false
  property string selectedPage: ""
  property int hoveredIndex: -1
  property int focusIndex: -1
  property int lastPreviewIndex: 0
  readonly property var routeOptions: pageOptions.map(function(page) {
    const details = {
      plugins: "Installed and available modules",
      workspaces: "Count and marker previews",
      pickers: "Image and media style previews",
      logo: "Launcher wordmarks and icons",
      functions: "Per-widget content and surfaces",
      bars: "Position, layout and profile styles",
      health: "Runtime and error diagnostics"
    }
    const previewDetails = {
      bars: "V1 Islands, V2 Notch and the Omarchy host",
      functions: "Content modes across active widgets",
      logo: "Independent wordmark and icon identities",
      workspaces: "Default, Numbers, Magic and Frame samples",
      pickers: "Carousel, Tanzaku and Hearthstone at a glance",
      plugins: "Installed modules as marketplace cards",
      health: "Live checks with attention states first"
    }
    return {
      id: page.id,
      label: page.label,
      glyph: page.glyph,
      detail: details[page.id] || "Control Center settings",
      previewDetail: previewDetails[page.id] || "Settings preview"
    }
  })
  readonly property bool ready: routeRepeater.count === routeOptions.length
  readonly property int previewIndex: {
    const candidate = hoveredIndex >= 0
      ? hoveredIndex : focusIndex >= 0 ? focusIndex : lastPreviewIndex
    return Math.max(0, Math.min(candidate, routeOptions.length - 1))
  }
  readonly property var previewRoute: routeOptions.length > 0
      && previewIndex >= 0 && previewIndex < routeOptions.length
    ? routeOptions[previewIndex]
    : ({ id: "", label: "", detail: "", previewDetail: "" })
  readonly property int barsRouteIndex: {
    for (let index = 0; index < routeOptions.length; index++) {
      if (routeOptions[index].id === "bars") return index
    }
    return -1
  }
  readonly property int pluginsRouteIndex: {
    for (let index = 0; index < routeOptions.length; index++) {
      if (routeOptions[index].id === "plugins") return index
    }
    return -1
  }
  readonly property bool barsChildRouteVisible: detailOpen
    && selectedPage === "bars" && barsChildRouteAvailable
  readonly property bool pluginFavoritesVisible: detailOpen
    && selectedPage === "plugins" && favoritesRouteAvailable
  readonly property bool childRouteVisible:
    barsChildRouteVisible || pluginFavoritesVisible
  readonly property bool childRouteActive: barsChildRouteVisible
    ? barsChildRouteActive : favoritesRouteActive
  readonly property int childRouteIndex: barsChildRouteVisible
    ? barsRouteIndex : pluginsRouteIndex
  readonly property real surfaceRouteExtension: childRouteVisible
    ? Commons.Style.space(34) : 0
  signal pageRequested(string pageId)
  signal barsChildRequested()
  signal favoritesRequested()
  signal backRequested()

  width: parent ? parent.width : 1
  spacing: root.transitioning ? 0 : Commons.Style.space(14)
  activeFocusOnTab: true

  Behavior on spacing {
    NumberAnimation { duration: 300; easing.type: Easing.InOutCubic }
  }

  function targetY(pageId) {
    void(pageId)
    return 0
  }

  function routeHomeY(index) {
    const base = index
      * (Commons.Style.space(43) + Commons.Style.space(7))
    return base + (root.childRouteVisible
      && index > root.childRouteIndex ? root.surfaceRouteExtension : 0)
  }

  function openRoute(pageId) {
    if (transitioning) return false
    selectedPage = String(pageId)
    transitioning = true
    routeTransition.restart()
    return true
  }

  function cancelTransition() {
    routeTransition.stop()
    transitioning = false
    selectedPage = ""
    hoveredIndex = -1
  }

  function showRoute(pageId) {
    routeTransition.stop()
    selectedPage = String(pageId || "")
    transitioning = selectedPage !== ""
    hoveredIndex = -1
    for (let index = 0; index < routeOptions.length; index++) {
      if (routeOptions[index].id === selectedPage) {
        focusIndex = index
        break
      }
    }
    Qt.callLater(function() { root.forceActiveFocus() })
    return transitioning
  }

  function activateFocusedRoute() {
    if (focusIndex < 0 || focusIndex >= routeOptions.length) return false
    const pageId = routeOptions[focusIndex].id
    if (detailOpen) {
      pageRequested(pageId)
      return true
    }
    return openRoute(pageId)
  }

  onActivePageChanged: {
    if (activePage) {
      cancelTransition()
      focusIndex = -1
    }
  }

  onActiveFocusChanged: {
    if (activeFocus && activePage && focusIndex < 0)
      focusIndex = 0
  }

  onHoveredIndexChanged: {
    if (hoveredIndex >= 0) lastPreviewIndex = hoveredIndex
  }

  onFocusIndexChanged: {
    if (focusIndex >= 0 && hoveredIndex < 0)
      lastPreviewIndex = focusIndex
  }

  Keys.onUpPressed: function(event) {
    focusIndex = Math.max(0, focusIndex - 1)
    event.accepted = true
  }
  Keys.onDownPressed: function(event) {
    focusIndex = Math.min(routeOptions.length - 1, focusIndex + 1)
    event.accepted = true
  }
  Keys.onReturnPressed: function(event) {
    activateFocusedRoute()
    event.accepted = true
  }
  Keys.onEnterPressed: function(event) {
    activateFocusedRoute()
    event.accepted = true
  }

  Column {
    id: intro
    width: parent.width
    height: root.transitioning ? 0 : implicitHeight
    spacing: Commons.Style.space(14)
    opacity: root.transitioning ? 0 : 1
    clip: true

    Behavior on height {
      NumberAnimation { duration: 300; easing.type: Easing.InOutCubic }
    }

    Behavior on opacity {
      NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
    }

    Text {
      text: "Choose what you want to change"
      color: root.foreground
      font.family: root.controller.marketFont
      font.pixelSize: Commons.Style.space(24) * root.uiScale
      font.weight: Font.DemiBold
    }

    Text {
      width: parent.width
      text: "Each route keeps its own capabilities and moves into the editor "
        + "only after you select it."
      color: root.foreground
      opacity: 0.54
      wrapMode: Text.WordWrap
      font.family: root.controller.marketFont
      font.pixelSize: Commons.Style.font.caption * root.uiScale
    }
  }

  Item {
    id: routeGraph
    property real routeGap: Commons.Style.space(38)
    property real portOffset: Commons.Style.space(6)
    width: parent.width
    height: Math.max(routeColumn.implicitHeight, Commons.Style.space(294))

    Canvas {
      id: routeCanvas
      anchors.fill: parent
      z: 2
      opacity: root.transitioning ? 0 : 1
      antialiasing: true

      Behavior on opacity {
        NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
      }

      function drawRoute(context, index) {
        const routeItem = routeRepeater.itemAt(index)
        if (!routeItem) return
        const startX = routeColumn.width + routeGraph.portOffset
        const startY = routeItem.homeY + routeItem.homeHeight / 2
        const endX = motionStage.x
        const endY = motionStage.height / 2
        const hovered = index === root.hoveredIndex
        const selected = routeItem.selected
        const routeColor = selected
          ? root.accent
          : hovered ? Commons.Util.alpha(root.accent, 0.58)
            : Commons.Util.alpha(root.foreground, 0.15)

        context.beginPath()
        context.moveTo(startX, startY)
        context.bezierCurveTo(
          startX + (endX - startX) * 0.55, startY,
          endX - (endX - startX) * 0.55, endY,
          endX, endY)
        context.strokeStyle = routeColor
        context.lineWidth = selected ? 1.7 : hovered ? 1.25 : 1
        context.stroke()

        context.beginPath()
        context.arc(startX, startY, 3.6, 0, Math.PI * 2)
        context.fillStyle = routeColor
        context.fill()
      }

      onPaint: {
        const context = getContext("2d")
        context.reset()
        context.clearRect(0, 0, width, height)
        for (let index = 0; index < root.routeOptions.length; index++)
          drawRoute(context, index)
        context.beginPath()
        context.arc(motionStage.x, motionStage.height / 2, 4.4,
          0, Math.PI * 2)
        context.fillStyle = root.accent
        context.fill()
      }

      Connections {
        target: root
        function onHoveredIndexChanged() { routeCanvas.requestPaint() }
        function onSelectedPageChanged() { routeCanvas.requestPaint() }
        function onForegroundChanged() { routeCanvas.requestPaint() }
        function onAccentChanged() { routeCanvas.requestPaint() }
      }

      onWidthChanged: requestPaint()
      onHeightChanged: requestPaint()
      Component.onCompleted: requestPaint()
    }

    Canvas {
      id: detailRouteCanvas
      x: -Commons.Style.space(14)
      y: 0
      z: 4
      width: Commons.Style.space(14)
      height: routeColumn.implicitHeight
      visible: root.detailOpen
      antialiasing: true

      onPaint: {
        const context = getContext("2d")
        context.reset()
        context.clearRect(0, 0, width, height)
        if (!root.detailOpen || root.routeOptions.length < 1) return
        const nodeX = Commons.Style.space(4)
        const firstItem = routeRepeater.itemAt(0)
        const lastItem = routeRepeater.itemAt(root.routeOptions.length - 1)
        if (!firstItem || !lastItem) return
        const firstY = firstItem.homeY + firstItem.homeHeight / 2
        const lastY = lastItem.homeY + lastItem.homeHeight / 2
        context.strokeStyle = Commons.Util.alpha(root.foreground, 0.18)
        context.lineWidth = 1
        context.beginPath()
        context.moveTo(nodeX, firstY)
        context.lineTo(nodeX, lastY)
        context.stroke()

        for (let index = 0; index < root.routeOptions.length; index++) {
          const routeItem = routeRepeater.itemAt(index)
          if (!routeItem) continue
          const nodeY = routeItem.homeY + routeItem.homeHeight / 2
          const active = root.routeOptions[index].id === root.selectedPage
          context.strokeStyle = active
            ? root.accent : Commons.Util.alpha(root.foreground, 0.18)
          context.beginPath()
          context.moveTo(nodeX, nodeY)
          context.lineTo(width, nodeY)
          context.stroke()
          context.beginPath()
          context.arc(nodeX, nodeY, 3.6, 0, Math.PI * 2)
          context.fillStyle = active
            ? root.accent : Commons.Util.alpha(root.foreground, 0.24)
          context.fill()
        }
      }

      Connections {
        target: root
        function onSelectedPageChanged() {
          detailRouteCanvas.requestPaint()
        }
        function onForegroundChanged() {
          detailRouteCanvas.requestPaint()
        }
        function onAccentChanged() {
          detailRouteCanvas.requestPaint()
        }
        function onDetailOpenChanged() {
          detailRouteCanvas.requestPaint()
        }
        function onBarsChildRouteVisibleChanged() {
          detailRouteCanvas.requestPaint()
        }
        function onPluginFavoritesVisibleChanged() {
          detailRouteCanvas.requestPaint()
        }
      }

      onWidthChanged: requestPaint()
      onHeightChanged: requestPaint()
      Component.onCompleted: requestPaint()
    }

    Item {
      id: routeColumn
      z: 3
      width: Math.min(Commons.Style.space(282), parent.width * 0.43)
      height: parent.height
      implicitHeight: root.routeOptions.length * Commons.Style.space(43)
        + Math.max(0, root.routeOptions.length - 1)
          * Commons.Style.space(7)
        + root.surfaceRouteExtension

      Repeater {
        id: routeRepeater
        model: root.routeOptions

        delegate: Rectangle {
          id: routeCard
          required property var modelData
          required property int index
          readonly property real homeY: root.routeHomeY(index)
          readonly property real homeHeight: Commons.Style.space(43)
          readonly property bool selected:
            root.selectedPage === modelData.id
          readonly property bool focused:
            root.activeFocus && root.focusIndex === index
          x: 0
          y: root.transitioning
            ? root.targetY(modelData.id) + homeY : homeY
          width: root.transitioning
            ? Commons.Style.space(154) : routeColumn.width
          height: homeHeight
          radius: root.controller.controlRadius
          color: selected || focused || routePointer.containsMouse
            ? root.controller.controlHoverFillColor
            : root.controller.controlFillColor
          border.width: root.controller.controlBorderWidth
          border.color: selected || focused
            ? root.accent : root.controller.controlBorderColor
          opacity: 1

          Behavior on x {
            NumberAnimation { duration: 300; easing.type: Easing.InOutCubic }
          }
          Behavior on y {
            NumberAnimation { duration: 300; easing.type: Easing.InOutCubic }
          }
          Behavior on width {
            NumberAnimation { duration: 300; easing.type: Easing.InOutCubic }
          }
          Behavior on height {
            NumberAnimation { duration: 300; easing.type: Easing.InOutCubic }
          }
          Behavior on opacity {
            NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
          }

          Row {
            anchors.fill: parent
            anchors.leftMargin: Commons.Style.space(10)
            anchors.rightMargin: Commons.Style.space(9)
            spacing: Commons.Style.space(9)

            IconText {
              anchors.verticalCenter: parent.verticalCenter
              width: Commons.Style.space(18)
              text: routeCard.modelData.glyph
              color: root.accent
              opacity: 0.88
              font.pixelSize: Commons.Style.font.iconLarge * root.uiScale
              fill: 0
            }

            Column {
              anchors.verticalCenter: parent.verticalCenter
              width: parent.width - x
              spacing: 0

              Text {
                width: parent.width
                text: routeCard.modelData.label
                color: root.foreground
                elide: Text.ElideRight
                font.family: root.controller.marketFont
                font.pixelSize: Commons.Style.font.bodySmall * root.uiScale
                font.weight: Font.Medium
              }

              Text {
                width: parent.width
                visible: true
                text: routeCard.modelData.detail
                color: root.foreground
                opacity: 0.38
                elide: Text.ElideRight
                font.family: root.controller.marketFont
                font.pixelSize: Commons.Style.font.caption * root.uiScale
              }
            }
          }

          MouseArea {
            id: routePointer
            anchors.fill: parent
            enabled: !root.transitioning || root.detailOpen
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onEntered: root.hoveredIndex = routeCard.index
            onExited: {
              if (root.hoveredIndex === routeCard.index)
                root.hoveredIndex = -1
            }
            onClicked: {
              if (root.detailOpen) {
                root.focusIndex = routeCard.index
                root.pageRequested(routeCard.modelData.id)
              } else {
                root.openRoute(routeCard.modelData.id)
              }
            }
          }
        }
      }

      Canvas {
        id: surfaceRouteCanvas
        property real barsNodeY: root.childRouteIndex >= 0
          ? root.routeHomeY(root.childRouteIndex)
            + Commons.Style.space(43) / 2
          : 0
        property real childNodeY: surfaceRouteRow.y
          + surfaceRouteRow.height / 2

        x: -Commons.Style.space(14)
        y: barsNodeY
        z: 5
        width: Commons.Style.space(44)
        height: Math.max(1, childNodeY - barsNodeY
          + Commons.Style.space(4))
        visible: root.childRouteVisible
        antialiasing: true

        onPaint: {
          const context = getContext("2d")
          context.reset()
          context.clearRect(0, 0, width, height)
          if (!root.childRouteVisible) return
          const railX = Commons.Style.space(4)
          const nodeX = Commons.Style.space(34)
          const nodeY = height - Commons.Style.space(4)
          const routeColor = root.childRouteActive
            ? root.accent : Commons.Util.alpha(root.foreground, 0.24)
          context.beginPath()
          if (root.childRouteActive) {
            context.moveTo(railX, 0)
            context.lineTo(railX, nodeY)
          } else {
            context.moveTo(railX, nodeY)
          }
          context.lineTo(nodeX, nodeY)
          context.strokeStyle = routeColor
          context.lineWidth = root.childRouteActive ? 1.5 : 1
          context.stroke()
          context.beginPath()
          context.arc(nodeX, nodeY, 3.2, 0, Math.PI * 2)
          context.fillStyle = routeColor
          context.fill()
        }

        Connections {
          target: root
          function onBarsChildRouteActiveChanged() {
            surfaceRouteCanvas.requestPaint()
          }
          function onBarsChildRouteVisibleChanged() {
            surfaceRouteCanvas.requestPaint()
          }
          function onPluginFavoritesVisibleChanged() {
            surfaceRouteCanvas.requestPaint()
          }
          function onFavoritesRouteActiveChanged() {
            surfaceRouteCanvas.requestPaint()
          }
          function onForegroundChanged() {
            surfaceRouteCanvas.requestPaint()
          }
          function onAccentChanged() {
            surfaceRouteCanvas.requestPaint()
          }
        }

        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        Component.onCompleted: requestPaint()
      }

      Rectangle {
        id: surfaceRouteRow
        x: Commons.Style.space(24)
        y: root.childRouteIndex >= 0
          ? root.routeHomeY(root.childRouteIndex)
            + Commons.Style.space(47)
          : 0
        z: 4
        width: Math.max(1, Commons.Style.space(130))
        height: Commons.Style.space(27)
        visible: root.childRouteVisible
        activeFocusOnTab: visible
        radius: root.controller.controlRadius
        color: root.childRouteActive || activeFocus
            || surfaceRoutePointer.containsMouse
          ? root.controller.controlHoverFillColor : "transparent"
        border.width: root.childRouteActive || activeFocus ? 1 : 0
        border.color: root.childRouteActive
          ? root.accent : root.controller.controlBorderColor

        Text {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          anchors.leftMargin: Commons.Style.space(9)
          anchors.rightMargin: Commons.Style.space(7)
          text: root.pluginFavoritesVisible
            ? "Favorites" : root.barsChildRouteLabel
          color: root.childRouteActive ? root.accent : root.foreground
          opacity: root.childRouteActive || parent.activeFocus
            || surfaceRoutePointer.containsMouse ? 1 : 0.62
          elide: Text.ElideRight
          font.family: root.controller.marketFont
          font.pixelSize: Commons.Style.font.caption * root.uiScale
          font.weight: Font.Medium
        }

        MouseArea {
          id: surfaceRoutePointer
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            surfaceRouteRow.forceActiveFocus()
            if (root.pluginFavoritesVisible) root.favoritesRequested()
            else root.barsChildRequested()
          }
        }

        Keys.onReturnPressed: function(event) {
          if (root.pluginFavoritesVisible) root.favoritesRequested()
          else root.barsChildRequested()
          event.accepted = true
        }
        Keys.onEnterPressed: function(event) {
          if (root.pluginFavoritesVisible) root.favoritesRequested()
          else root.barsChildRequested()
          event.accepted = true
        }
      }
    }

    ConfigureRoutePreview {
      id: motionStage
      z: 1
      anchors.right: parent.right
      width: parent.width - routeColumn.width - routeGraph.routeGap
      height: parent.height
      controller: root.controller
      routeId: root.previewRoute.id
      label: root.previewRoute.label
      detail: root.previewRoute.previewDetail
      uiScale: root.uiScale
      foreground: root.foreground
      accent: root.accent
      opacity: root.transitioning ? 0 : 1

      Behavior on opacity {
        NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
      }
    }
  }

  Timer {
    id: routeTransition
    interval: 330
    repeat: false
    onTriggered: root.pageRequested(root.selectedPage)
  }
}
