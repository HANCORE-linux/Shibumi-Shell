pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons as Commons
import "../../core" as Core
import "../../core/RunGeometry.js" as RunGeometry
import "../../core/ResponsiveLayout.js" as ResponsiveLayout
import "." as Shibumi

Item {
  id: root

  required property var bar
  property var layoutSession: null
  property string screenName: ""
  readonly property int responsiveStage: contentLoader.item
    && "narrowStage" in contentLoader.item
      ? Number(contentLoader.item.narrowStage) || 0 : 0
  readonly property var responsiveProbe: contentLoader.item
    && "responsiveProbe" in contentLoader.item
      ? contentLoader.item.responsiveProbe : ({})
  readonly property var reactorFacade: bar && bar.shell
    && typeof bar.shell.serviceFor === "function"
    ? bar.shell.serviceFor("hancore.shibumi.reactor") : null
  readonly property int reactorMode: reactorFacade
    ? Number(reactorFacade.mode || 0) : 0
  readonly property bool layoutProtected: bar.layoutController
    && "activeLayoutProtected" in bar.layoutController
    && bar.layoutController.activeLayoutProtected === true
  readonly property bool layoutChangesAllowed:
    layoutSession && layoutSession.editing || !layoutProtected
  focus: layoutSession && layoutSession.editing

  Loader {
    id: contentLoader
    anchors.fill: parent
    sourceComponent: root.bar.vertical ? verticalContent : horizontalContent
  }

  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton
    z: -10

    onClicked: {
      if (root.layoutSession && root.layoutSession.editing)
        root.layoutSession.setEditing(false)
    }
    onDoubleClicked: {
      if (root.layoutSession) root.layoutSession.setEditing(true)
    }
  }

  Keys.onEscapePressed: {
    if (root.layoutSession) root.layoutSession.setEditing(false)
  }

  Connections {
    target: root.layoutSession

    function onEditingChanged() {
      if (root.layoutSession && root.layoutSession.editing)
        root.forceActiveFocus()
    }
  }

  Component {
    id: horizontalContent

    Item {
      id: horizontalSurface

      readonly property int frameInset: root.bar.visualTokens.islandInsetX
      readonly property int contentInset:
        root.bar.visualTokens.islandContentInsetX !== undefined
          ? root.bar.visualTokens.islandContentInsetX : Commons.Style.space(4)
      readonly property int cutPadding: Commons.Style.space(4)
      readonly property int centerGap: Commons.Style.space(12)
      readonly property string shellStyle:
        ["shibumi", "full", "fit", "dock", "notch"]
          .indexOf(String(root.bar.visualTokens.shellStyle || "")) >= 0
          ? String(root.bar.visualTokens.shellStyle) : "shibumi"
      readonly property bool shibumiShell: shellStyle === "shibumi"
      readonly property bool compactShell:
        ["fit", "dock", "notch"].indexOf(shellStyle) >= 0
      readonly property real naturalShellWidth:
        leftGroups.budgetWidthForStage(0) + leftExtras.width
        + centerGroups.budgetWidthForStage(0) + centerExtras.width
        + rightExtras.width + rightGroups.budgetWidthForStage(0)
        + leftGroups.editingWidthOverhead
        + centerGroups.editingWidthOverhead
        + rightGroups.editingWidthOverhead
        + 2 * centerGap + 2 * contentInset
        + (shellStyle === "notch"
          ? 2 * root.bar.visualTokens.shellWingWidth : 0)
      readonly property real shellWidth: shibumiShell
        ? Math.max(0, width - 2 * frameInset)
        : compactShell ? Math.min(width - 2 * frameInset,
            Math.max(Commons.Style.space(80), naturalShellWidth))
        : width
      // Fit/Dock/Notch are content-sized. Feeding their current shell width
      // back into responsive staging lets a transient provider width compact
      // the shell and hide G9/G10 even though the monitor still has room.
      // Stage against the output capacity; shellWidth remains presentation.
      readonly property real responsiveCapacity: compactShell
        ? Math.max(0, width - 2 * frameInset) : shellWidth
      readonly property real shellX: shibumiShell ? frameInset
        : Math.round((width - shellWidth) / 2)
      readonly property real shellContentInset: contentInset
        + (shellStyle === "notch"
          ? root.bar.visualTokens.shellWingWidth : 0)
      readonly property real measuredCenterSpan: Math.max(0,
        rightRegion.x - (leftRegion.x + leftRegion.width) - 2 * centerGap)
      readonly property real centerAvailableWidth:
        ResponsiveLayout.centerAvailableWidth(compactShell, width,
          frameInset, shellContentInset, leftRegion.width, rightRegion.width,
          centerGap, measuredCenterSpan)
      property int narrowStage: 0
      readonly property real sideMargin: shellX + shellContentInset
      readonly property real responsiveSideInset: shellContentInset
      readonly property real centerFloorWidth: Math.max(80,
        Number(centerGroups.minimumResponsiveWidth) || 0)
      readonly property var narrowCandidateWidths: [0, 1, 2, 3].map(function(stage) {
        return leftGroups.budgetWidthForStage(stage)
          + rightGroups.budgetWidthForStage(stage)
          + horizontalSurface.centerFloorWidth
          + 2 * horizontalSurface.centerGap
          + 2 * horizontalSurface.responsiveSideInset
      })
      readonly property var responsiveProbe: ({
        shellWidth: Math.round(shellWidth),
        capacity: Math.round(responsiveCapacity),
        stage: narrowStage,
        candidates: narrowCandidateWidths.map(function(value) {
          return Math.round(Number(value) || 0)
        }),
        left: leftGroups.stageBudgetWidths,
        right: rightGroups.stageBudgetWidths,
        centerFloor: Math.round(centerFloorWidth),
        centerAvailable: Math.round(centerAvailableWidth)
      })
      readonly property real idealCenterX: Math.round((width - centerRegion.width) / 2)
      readonly property real minCenterX: Math.round(leftRegion.x + leftRegion.width + centerGap)
      readonly property real maxCenterX: Math.round(rightRegion.x - centerGap - centerRegion.width)
      readonly property real centerTargetX: maxCenterX < minCenterX
        // At an exact fit, pixel rounding can make the two legal limits cross
        // by one pixel. Falling back to the screen center then overlaps the
        // asymmetric right run (notably G8 with G9/MPRIS). Split the tiny
        // deficit between both sides instead and preserve the visible gaps.
        ? Math.round((minCenterX + maxCenterX) / 2)
        : Math.max(minCenterX, Math.min(idealCenterX, maxCenterX))
      readonly property var runs: {
        void(leftGroups.groupGeometry)
        void(rightGroups.groupGeometry)
        void(leftRegion.x)
        void(leftRegion.width)
        void(centerRegion.x)
        void(centerRegion.width)
        void(rightRegion.x)
        void(rightRegion.width)
        void(runChrome.width)
        void(root.bar.layoutController.splits)
        return RunGeometry.compute({
          width: runChrome.width,
          padding: cutPadding,
          sections: [
            {
              x: leftRegion.x + leftGroups.x - runChrome.x,
              groups: leftGroups.groupGeometry,
              splits: root.bar.layoutController.splits.left
            },
            {
              x: rightRegion.x + rightGroups.x - runChrome.x,
              groups: rightGroups.groupGeometry,
              splits: root.bar.layoutController.splits.right
            }
          ],
          left: leftRegion.width > 0.5 ? {
            x: leftRegion.x - runChrome.x,
            width: leftRegion.width
          } : null,
          center: {
            x: centerRegion.x - runChrome.x,
            width: centerRegion.width
          },
          right: rightRegion.width > 0.5 ? {
            x: rightRegion.x - runChrome.x,
            width: rightRegion.width
          } : null,
          boundaries: root.bar.layoutController.splits.boundaries
        })
      }

      function toggleBoundary(index) {
        if (!root.layoutChangesAllowed) return false
        return root.bar.layoutController.toggleSplit(
          "boundaries", index,
          root.layoutSession && root.layoutSession.editing)
      }

      function updateNarrowStage() {
        narrowStage = ResponsiveLayout.nextNarrowStage(narrowStage,
          responsiveCapacity, narrowCandidateWidths)
      }

      function scheduleNarrowUpdate() { narrowTimer.restart() }

      function resetResponsiveProbe() {
        // Provider swaps and widget enable/disable operations are transient
        // width changes. If the bar entered the hysteresis band while one
        // side was rebuilding, it could otherwise keep G9/G10 hidden after
        // the original layout had returned. Probe the complete stage once
        // the configuration settles; updateNarrowStage immediately narrows
        // it again when the full composition genuinely does not fit.
        narrowStage = 0
        scheduleNarrowUpdate()
      }

      onWidthChanged: scheduleNarrowUpdate()
      onNarrowCandidateWidthsChanged: scheduleNarrowUpdate()
      Component.onCompleted: scheduleNarrowUpdate()

      Timer {
        id: narrowTimer
        interval: 80
        onTriggered: horizontalSurface.updateNarrowStage()
      }

      Timer {
        id: responsiveResetTimer
        interval: 220
        onTriggered: horizontalSurface.resetResponsiveProbe()
      }

      Connections {
        target: root.bar && root.bar.shell
          && typeof root.bar.shell.serviceFor === "function"
          ? root.bar.shell.serviceFor("hancore.shibumi.state") : null
        ignoreUnknownSignals: true
        function onRevisionChanged() { responsiveResetTimer.restart() }
      }

      Connections {
        target: root.bar
        ignoreUnknownSignals: true
        function onLayoutConfigChanged() { responsiveResetTimer.restart() }
      }

      Shibumi.RunChrome {
        id: runChrome

        bar: root.bar
        screenName: root.screenName
        screenX: horizontalSurface.shellX
        runs: horizontalSurface.runs
        // V1 and every V2 shell form are intentionally opaque. The saved
        // transparency preference belongs only to the stock Omarchy bar.
        visible: true
        x: horizontalSurface.shellX
        width: Math.max(0, horizontalSurface.shellWidth)
        height: horizontalSurface.shibumiShell
          ? Math.min(parent.height, root.bar.visualTokens.islandHeight)
          : parent.height
        y: horizontalSurface.shibumiShell
          ? (root.bar.position === "bottom" ? 0
            : root.bar.visualTokens.islandOffsetY)
          : (root.bar.position === "bottom"
            ? parent.height - height : 0)
        z: 0
      }

      Rectangle {
        x: runChrome.x - Commons.Style.space(3)
        y: runChrome.y - Commons.Style.space(3)
        width: runChrome.width + Commons.Style.space(6)
        height: runChrome.height + Commons.Style.space(6)
        visible: root.layoutSession && root.layoutSession.editing
        color: "transparent"
        border.width: 1
        border.color: root.bar.urgent
        radius: root.bar.layoutController.v2Mode
          ? 0 : root.bar.visualTokens.islandRadius + Commons.Style.space(2)
        z: 80

        SequentialAnimation on opacity {
          running: root.layoutSession && root.layoutSession.editing
          loops: Animation.Infinite
          NumberAnimation {
            from: 1
            to: 0.45
            duration: 900
            easing.type: Easing.InOutSine
          }
          NumberAnimation {
            from: 0.45
            to: 1
            duration: 900
            easing.type: Easing.InOutSine
          }
        }
      }

      Loader {
        id: gapEffectsLoader

        active: !root.bar.barHidden
          && root.bar.layoutController.v2Mode !== true
          && root.reactorMode >= 1 && root.reactorMode <= 8
          && horizontalSurface.runs.length > 1
        x: runChrome.x
        y: runChrome.y
        width: runChrome.width
        height: runChrome.height
        z: 5
        sourceComponent: !active ? null
          : root.reactorMode >= 7 ? reactorEventComponent
          : gapEffectsComponent

        Component {
          id: gapEffectsComponent

          Shibumi.GapEffectsLayer {
            bar: root.bar
            mode: root.reactorMode
            runs: horizontalSurface.runs
          }
        }

        Component {
          id: reactorEventComponent

          Shibumi.ReactorEventLayer {
            bar: root.bar
            service: root.reactorFacade
            runs: horizontalSurface.runs
            screenName: root.screenName
          }
        }
      }

      Row {
        id: leftRegion

        anchors.left: parent.left
        anchors.leftMargin: horizontalSurface.shellX
          + horizontalSurface.shellContentInset
        anchors.verticalCenter: runChrome.verticalCenter
        z: 10

        Shibumi.GroupSection {
          id: leftGroups
          // Provider-owned extras may follow the full bar height while the
          // grouped V1 row remains 32px. Center both siblings independently
          // so either height cannot displace the other from the island axis.
          anchors.verticalCenter: parent.verticalCenter
          bar: root.bar
          region: "left"
          screenName: root.screenName
          layoutSession: root.layoutSession
          visibilityStage: horizontalSurface.narrowStage
        }

        Core.BarSection {
          id: leftExtras
          anchors.verticalCenter: parent.verticalCenter
          bar: root.bar
          region: "left-extra"
          screenName: root.screenName
          entries: root.bar.unassignedLayoutEntries("left")
        }
      }

      Row {
        id: centerRegion

        anchors.verticalCenter: runChrome.verticalCenter
        x: horizontalSurface.centerTargetX
        z: 10

        Behavior on x {
          NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
        }

        Shibumi.GroupSection {
          id: centerGroups
          anchors.verticalCenter: parent.verticalCenter
          bar: root.bar
          region: "center"
          screenName: root.screenName
          layoutSession: root.layoutSession
          visibilityStage: horizontalSurface.narrowStage
          availableWidth: horizontalSurface.centerAvailableWidth
        }

        Core.BarSection {
          id: centerExtras
          anchors.verticalCenter: parent.verticalCenter
          bar: root.bar
          region: "center-extra"
          screenName: root.screenName
          entries: root.bar.unassignedLayoutEntries("center")
        }
      }

      Row {
        id: rightRegion

        anchors.right: parent.right
        anchors.rightMargin: horizontalSurface.shellX
          + horizontalSurface.shellContentInset
        anchors.verticalCenter: runChrome.verticalCenter
        z: 10

        Core.BarSection {
          id: rightExtras
          anchors.verticalCenter: parent.verticalCenter
          bar: root.bar
          region: "right-extra"
          screenName: root.screenName
          entries: root.bar.unassignedLayoutEntries("right")
        }

        Shibumi.GroupSection {
          id: rightGroups
          anchors.verticalCenter: parent.verticalCenter
          bar: root.bar
          region: "right"
          screenName: root.screenName
          layoutSession: root.layoutSession
          visibilityStage: horizontalSurface.narrowStage
        }
      }

      component BoundaryMarker: Item {
        id: boundaryMarker

        property real boundaryX: 0
        property int boundaryIndex: -1
        readonly property bool splitOn: boundaryIndex >= 0
          && root.bar.layoutController.splitEnabled("boundaries", boundaryIndex)

        visible: boundaryX > 0 && boundaryIndex >= 0
        x: boundaryX - width / 2
        width: 14
        height: parent.height
        z: 40

        Rectangle {
          anchors.centerIn: parent
          width: 1
          height: Math.min(parent.height - 8, 14)
          visible: boundaryMarker.splitOn
            && !horizontalSurface.shibumiShell
          color: boundaryMouse.containsMouse
            ? root.bar.urgent
            : root.bar.visualTokens.separator !== undefined
              ? root.bar.visualTokens.separator : root.bar.visualTokens.sumi
          opacity: 0.62

          Behavior on color { ColorAnimation { duration: 120 } }
        }

        Text {
          anchors.centerIn: parent
          visible: root.bar.layoutController.v2Mode !== true
            || !boundaryMarker.splitOn
          text: root.bar.layoutController.v2Mode !== true
              && boundaryMarker.splitOn ? "│" : "•"
          color: boundaryMouse.containsMouse
              || (root.bar.layoutController.v2Mode !== true
                && boundaryMarker.splitOn)
            ? root.bar.urgent : root.bar.visualTokens.sumi
          font.pixelSize: 10
          font.family: root.bar.fontFamily
          opacity: root.layoutSession && root.layoutSession.editing
            ? boundaryMouse.containsMouse ? 0.95 : 0.34
            : boundaryMouse.containsMouse ? 0.9 : 0

          Behavior on opacity { NumberAnimation { duration: 120 } }
        }

        MouseArea {
          id: boundaryMouse
          anchors.fill: parent
          enabled: root.layoutChangesAllowed
          hoverEnabled: true
          acceptedButtons: Qt.LeftButton
          cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
          onClicked: horizontalSurface.toggleBoundary(boundaryMarker.boundaryIndex)
        }
      }

      BoundaryMarker {
        boundaryIndex: 0
        boundaryX: leftRegion.width > 0.5 && centerRegion.width > 0.5
          ? leftRegion.x + leftRegion.width + Commons.Style.space(9) : 0
      }

      BoundaryMarker {
        boundaryIndex: 1
        boundaryX: centerRegion.width > 0.5 && rightRegion.width > 0.5
          ? rightRegion.x - Commons.Style.space(9) : 0
      }
    }
  }

  Component {
    id: verticalContent

    Item {
      Column {
        anchors.top: parent.top
        anchors.topMargin: Commons.Style.space(2)
        anchors.horizontalCenter: parent.horizontalCenter

        Shibumi.GroupSection {
          bar: root.bar
          region: "left"
          screenName: root.screenName
          layoutSession: root.layoutSession
        }

        Core.BarSection {
          bar: root.bar
          region: "left-extra"
          screenName: root.screenName
          entries: root.bar.unassignedLayoutEntries("left")
        }
      }

      Shibumi.GroupSection {
        id: centerGroups
        bar: root.bar
        region: "center"
        screenName: root.screenName
        layoutSession: root.layoutSession
        anchors.centerIn: parent
      }

      Core.BarSection {
        bar: root.bar
        region: "center-extra"
        screenName: root.screenName
        entries: root.bar.unassignedLayoutEntries("center")
        anchors.top: centerGroups.bottom
        anchors.horizontalCenter: centerGroups.horizontalCenter
      }

      Column {
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Commons.Style.space(2)
        anchors.horizontalCenter: parent.horizontalCenter

        Core.BarSection {
          bar: root.bar
          region: "right-extra"
          screenName: root.screenName
          entries: root.bar.unassignedLayoutEntries("right")
        }

        Shibumi.GroupSection {
          bar: root.bar
          region: "right"
          screenName: root.screenName
          layoutSession: root.layoutSession
        }
      }
    }
  }
}
