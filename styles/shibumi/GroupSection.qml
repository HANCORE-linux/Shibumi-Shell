pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons as Commons
import "../../core" as Core
import "../../core/ResponsiveLayout.js" as ResponsiveLayout

Item {
  id: root

  required property var bar
  required property string region
  property string screenName: ""
  property var layoutSession: null
  property real availableWidth: 0
  property int visibilityStage: 0
  readonly property bool v2Editing: layoutSession
    && layoutSession.editing
    && bar.layoutController && bar.layoutController.v2Mode === true
  readonly property var groups: v2Editing
    && bar.layoutController.v2Slots
    ? bar.layoutController.v2Slots[region] || []
    : bar.layoutController && bar.layoutController.order
      ? bar.layoutController.order[region] || [] : []
  readonly property int baseV2SlotCount: bar.layoutController
    && typeof bar.layoutController.baseV2SlotCount === "function"
    ? bar.layoutController.baseV2SlotCount(region) : 0
  readonly property int maxV2SlotCount: bar.layoutController
    && typeof bar.layoutController.maxV2SlotCount === "function"
    ? bar.layoutController.maxV2SlotCount(region) : 0
  readonly property bool canAddV2Slot: v2Editing
    && maxV2SlotCount > 0 && groups.length < maxV2SlotCount
  readonly property int groupSpacing: bar.visualTokens.groupGap
  readonly property int splitGrow: bar.visualTokens.splitGap
  readonly property bool persistentSeparators:
    bar.visualTokens && bar.visualTokens.v2Shell === true
  readonly property var contentItem: content.item
  readonly property var groupGeometry: contentItem && contentItem.groupGeometry
    ? contentItem.groupGeometry : []
  readonly property var separatorGeometry: contentItem
    && contentItem.separatorGeometry ? contentItem.separatorGeometry : []
  readonly property var stageBudgetWidths: contentItem
    && contentItem.stageBudgetWidths ? contentItem.stageBudgetWidths : [0, 0, 0, 0]
  readonly property real minimumResponsiveWidth: contentItem
    && contentItem.minimumResponsiveWidth !== undefined
      ? Number(contentItem.minimumResponsiveWidth) || 0 : implicitWidth

  implicitWidth: contentItem && "layoutWidth" in contentItem
    ? contentItem.layoutWidth : contentItem ? contentItem.implicitWidth : 0
  implicitHeight: contentItem && "layoutHeight" in contentItem
    ? contentItem.layoutHeight : contentItem ? contentItem.implicitHeight : 0
  width: implicitWidth
  height: implicitHeight

  function splitAfter(index) {
    const groupId = index >= 0 && index < groups.length
      ? String(groups[index]) : ""
    const stateService = bar && bar.shell
      && typeof bar.shell.serviceFor === "function"
      ? bar.shell.serviceFor("hancore.shibumi.state") : null
    const appearanceSeparator = persistentSeparators && stateService
      && typeof stateService.groupSetting === "function"
      ? stateService.groupSetting(groupId, "separator", false) === true
      : false
    return appearanceSeparator || (bar.layoutController
      && typeof bar.layoutController.splitEnabled === "function"
      ? bar.layoutController.splitEnabled(region, index) : false)
  }

  function markerGapWidth(separated) {
    return groupSpacing + (separated ? splitGrow : 0)
  }

  function separatorCenterOffset(separated) {
    // Match V2's 15px separator extension: the active line sits 10px beyond
    // the widget/surface edge; an unset marker remains centered in the gap.
    return separated ? Math.max(0, splitGrow - groupSpacing)
      : groupSpacing / 2
  }

  function toggleSeparator(groupId) {
    return persistentSeparators && bar
      && typeof bar.toggleGroupSeparator === "function"
      ? bar.toggleGroupSeparator(String(groupId || "")) : false
  }

  function groupVisibleAtStage(groupId, stage) {
    return ResponsiveLayout.groupVisibleAtStage(groupId, stage)
  }

  function budgetWidthForStage(stage) {
    var index = Math.max(0, Math.min(3, Number(stage) || 0))
    return Math.max(0, Number(stageBudgetWidths[index]) || 0)
  }

  function tokenNumber(name, fallback) {
    const tokens = bar ? bar.visualTokens : null
    return tokens && tokens[name] !== undefined
      ? Number(tokens[name]) || fallback : fallback
  }

  function tokenColor(name, fallback) {
    const tokens = bar ? bar.visualTokens : null
    return tokens && tokens[name] !== undefined ? tokens[name] : fallback
  }

  Loader {
    id: content
    sourceComponent: root.bar.vertical ? verticalGroups : horizontalGroups
  }

  Component {
    id: horizontalGroups

    Row {
      id: horizontalRow

      spacing: 0
      readonly property real layoutWidth: {
        void(root.visibilityStage)
        var total = 0
        for (var i = 0; i < horizontalRepeater.count; i++) {
          var item = horizontalRepeater.itemAt(i)
          if (item) total += item.width
        }
        return total + (root.canAddV2Slot
          ? root.groupSpacing + addSlotTarget.width : 0)
      }
      readonly property real layoutHeight: {
        var height = 0
        for (var i = 0; i < horizontalRepeater.count; i++) {
          var item = horizontalRepeater.itemAt(i)
          if (item && item.visible) height = Math.max(height, item.height)
        }
        return Math.max(height, root.canAddV2Slot ? addSlotTarget.height : 0)
      }
      readonly property real minimumResponsiveWidth: {
        void(root.groups)
        var total = 0
        var visibleCount = 0
        for (var i = 0; i < horizontalRepeater.count; i++) {
          var item = horizontalRepeater.itemAt(i)
          if (!item || !item.groupHasContent) continue
          total += item.minimumGroupWidth
          if (root.splitAfter(item.index)) total += root.splitGrow
          visibleCount++
        }
        return total + Math.max(0, visibleCount - 1) * root.groupSpacing
      }
      readonly property var stageBudgetWidths: {
        void(root.groups)
        var widths = [0, 0, 0, 0]
        for (var stage = 0; stage < 4; stage++) {
          var visibleCount = 0
          for (var i = 0; i < horizontalRepeater.count; i++) {
            var item = horizontalRepeater.itemAt(i)
            if (!item || !item.budgetHasContent
                || !root.groupVisibleAtStage(item.modelData, stage)) continue
            widths[stage] += item.naturalGroupWidth
            if (root.splitAfter(item.index)) widths[stage] += root.splitGrow
            visibleCount++
          }
          widths[stage] += Math.max(0, visibleCount - 1) * root.groupSpacing
        }
        return widths
      }
      readonly property var groupGeometry: {
        void(root.groups)
        var result = []
        for (var i = 0; i < horizontalRepeater.count; i++) {
          var item = horizontalRepeater.itemAt(i)
          if (!item || !item.effectiveHasContent) continue
          result.push({
            groupId: item.modelData,
            index: item.index,
            left: item.x + item.contentLeft,
            right: item.x + item.contentRight
          })
        }
        return result
      }
      readonly property var separatorGeometry: {
        void(root.groups)
        var result = []
        for (var i = 0; i < horizontalRepeater.count; i++) {
          var item = horizontalRepeater.itemAt(i)
          if (!item || !item.separatorAvailable) continue
          result.push({
            groupId: item.modelData,
            visualRight: item.x + item.visualRightEdge,
            markerCenter: item.x + item.separatorCenter
          })
        }
        return result
      }
      function hasContentBefore(index) {
        for (var i = index - 1; i >= 0; i--) {
          var item = horizontalRepeater.itemAt(i)
          if (item && item.effectiveHasContent) return true
        }
        return false
      }

      function hasContentAfter(index) {
        for (var i = index + 1; i < horizontalRepeater.count; i++) {
          var item = horizontalRepeater.itemAt(i)
          if (item && item.effectiveHasContent) return true
        }
        return false
      }

      Repeater {
        id: horizontalRepeater
        model: root.groups

        delegate: Item {
          id: horizontalCell
          required property string modelData
          required property int index
          readonly property bool emptySlot: root.v2Editing && modelData === ""
          readonly property bool groupHasContent: groupSlot.hasContent
          readonly property bool autoShown: emptySlot
            || root.groupVisibleAtStage(modelData, root.visibilityStage)
          readonly property Item targetVisual: emptySlot
            ? emptySlotTarget : groupSlot
          property bool measuredHasContent: false
          property real measuredNaturalGroupWidth: 0
          property real measuredMinimumGroupWidth: 0
          readonly property bool effectiveHasContent: autoShown
            && (groupHasContent || emptySlot)
          readonly property bool budgetHasContent: groupHasContent
            || (measuredHasContent && groupSlot.groupEnabled
              && !autoShown)
          readonly property real naturalGroupWidth: emptySlot
            ? emptySlotTarget.width : groupHasContent
              ? groupSlot.implicitWidth : measuredNaturalGroupWidth
          readonly property real minimumGroupWidth: emptySlot
            ? emptySlotTarget.width : groupHasContent
              ? groupSlot.minimumResponsiveWidth : measuredMinimumGroupWidth
          readonly property real contentLeft: targetVisual.x
          readonly property real contentRight: targetVisual.x + targetVisual.width
          readonly property real visualRightEdge: groupSlot.x + groupSlot.width
          readonly property bool separatorAvailable:
            splitMarker.hasFollowingGroup
          readonly property real separatorCenter:
            splitMarker.x + splitMarker.width / 2
          property var targetSession: root.layoutSession
          property var registeredSession: null
          readonly property int leadingGap: effectiveHasContent
            && horizontalRow.hasContentBefore(index) ? root.groupSpacing : 0
          readonly property bool separated: effectiveHasContent
            && horizontalRow.hasContentAfter(index) && root.splitAfter(index)
          implicitWidth: effectiveHasContent
            ? leadingGap + targetVisual.width + (separated ? root.splitGrow : 0)
            : 0
          implicitHeight: effectiveHasContent ? targetVisual.height : 0
          width: implicitWidth
          height: implicitHeight
          // Keep the cell visible while its widget determines its initial
          // size. Basing ancestor visibility on groupHasContent would make
          // the child's effective visible state false and deadlock discovery.
          visible: autoShown && groupSlot.groupEnabled
          opacity: autoShown ? 1 : 0
          // The V1 split handle is 14px wide while an unsplit gap is only 6px.
          // Let the handle overlap the adjacent cells instead of clipping its
          // center outside this delegate.
          clip: false

          Behavior on opacity {
            NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
          }

          function syncTargetRegistration() {
            if (registeredSession
                && (registeredSession !== targetSession || !effectiveHasContent)
                && typeof registeredSession.unregisterTarget === "function")
              registeredSession.unregisterTarget(targetVisual)
            registeredSession = targetSession
            if (!registeredSession || !effectiveHasContent) return
            if (root.v2Editing
                && typeof registeredSession.registerSlotTarget === "function")
              registeredSession.registerSlotTarget(
                root.region, index, modelData, targetVisual)
            else if (typeof registeredSession.registerTarget === "function")
              registeredSession.registerTarget(modelData, targetVisual)
          }

          function retainResponsiveMetrics() {
            if (!groupHasContent || groupSlot.implicitWidth <= 0.5) return
            measuredHasContent = true
            measuredNaturalGroupWidth = Math.max(0, groupSlot.implicitWidth)
            measuredMinimumGroupWidth = Math.max(0,
              groupSlot.minimumResponsiveWidth)
          }

          onTargetSessionChanged: registrationTimer.restart()
          onGroupHasContentChanged: {
            retainResponsiveMetrics()
            registrationTimer.restart()
          }
          onAutoShownChanged: registrationTimer.restart()
          onModelDataChanged: registrationTimer.restart()
          Component.onCompleted: {
            retainResponsiveMetrics()
            registrationTimer.restart()
          }
          Timer {
            id: registrationTimer
            interval: 0
            onTriggered: horizontalCell.syncTargetRegistration()
          }

          Core.GroupSlot {
            id: groupSlot
            bar: root.bar
            groupId: horizontalCell.modelData
            screenName: root.screenName
            availableWidth: root.availableWidth
            x: horizontalCell.leadingGap
            opacity: root.layoutSession && root.layoutSession.active
              && root.layoutSession.sourceGroupId === horizontalCell.modelData
              ? 0.28 : 1

            Behavior on opacity {
              NumberAnimation { duration: 80 }
            }

            onImplicitWidthChanged: horizontalCell.retainResponsiveMetrics()
            onMinimumResponsiveWidthChanged:
              horizontalCell.retainResponsiveMetrics()
          }

          Rectangle {
            id: emptySlotTarget
            x: horizontalCell.leadingGap
            anchors.verticalCenter: parent.verticalCenter
            width: horizontalCell.emptySlot ? 28 : 0
            height: horizontalCell.emptySlot
              ? root.tokenNumber("slotHeight", 28) : 0
            visible: horizontalCell.emptySlot
            radius: root.tokenNumber("tileRadius", 8)
            color: removeEmptyMouse.containsMouse
              ? Qt.rgba(root.bar.urgent.r, root.bar.urgent.g,
                  root.bar.urgent.b, 0.14)
              : Qt.rgba(root.bar.foreground.r, root.bar.foreground.g,
                  root.bar.foreground.b, 0.04)
            border.width: 1
            border.color: removeEmptyMouse.containsMouse
              ? root.bar.urgent
              : root.tokenColor("pillBorder", root.bar.foreground)

            Text {
              anchors.centerIn: parent
              text: horizontalCell.index >= root.baseV2SlotCount ? "×" : "·"
              color: removeEmptyMouse.containsMouse
                ? root.bar.urgent
                : root.tokenColor("sumi", root.bar.foreground)
              font.family: root.bar.fontFamily
              font.pixelSize: 12
            }

            MouseArea {
              id: removeEmptyMouse
              anchors.fill: parent
              hoverEnabled: true
              acceptedButtons: Qt.LeftButton
              enabled: horizontalCell.index >= root.baseV2SlotCount
              cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
              onClicked: root.bar.layoutController.removeV2SlotAt(
                root.region, horizontalCell.index)
            }
          }

          Rectangle {
            x: horizontalCell.targetVisual.x - 2
            y: horizontalCell.targetVisual.y - 2
            width: horizontalCell.targetVisual.width + 4
            height: horizontalCell.targetVisual.height + 4
            visible: root.layoutSession && root.layoutSession.editing
              && root.layoutSession.active
              && root.layoutSession.targetItem === horizontalCell.targetVisual
            color: Qt.rgba(root.bar.urgent.r, root.bar.urgent.g,
              root.bar.urgent.b, 0.18)
            border.width: 2
            border.color: root.bar.urgent
            radius: root.bar.visualTokens.pillRadius
            z: 20
          }

          MouseArea {
            id: dragMouse

            x: groupSlot.x
            y: groupSlot.y
            width: groupSlot.width
            height: groupSlot.height
            enabled: root.layoutSession && root.layoutSession.editing
              && horizontalCell.groupHasContent
            acceptedButtons: Qt.LeftButton
            preventStealing: true
            cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
            z: 30

            function windowPoint(mouse) {
              return mapToItem(null, mouse.x, mouse.y)
            }

            onPressed: mouse => {
              const point = windowPoint(mouse)
              root.layoutSession.begin(horizontalCell.modelData, groupSlot,
                point.x, point.y)
            }
            onPositionChanged: mouse => {
              if (!pressed || !root.layoutSession.active) return
              const point = windowPoint(mouse)
              root.layoutSession.move(point.x, point.y)
            }
            onReleased: {
              if (root.layoutSession.active) root.layoutSession.drop()
            }
            onCanceled: root.layoutSession.cancel()
          }

          Item {
            id: splitMarker

            readonly property bool hasFollowingGroup: horizontalCell.effectiveHasContent
              && horizontalRow.hasContentAfter(horizontalCell.index)
            x: groupSlot.x + groupSlot.width
              + root.separatorCenterOffset(horizontalCell.separated)
              - width / 2
            anchors.verticalCenter: groupSlot.verticalCenter
            width: 14
            height: groupSlot.height
            visible: hasFollowingGroup
            z: 40

            Rectangle {
              anchors.centerIn: parent
              width: 1
              height: Math.min(parent.height - 8, 14)
              visible: horizontalCell.separated
                && root.persistentSeparators
              color: splitMouse.containsMouse
                ? root.bar.urgent
                : root.tokenColor("separator", root.bar.visualTokens.sumi)
              opacity: 0.62

              Behavior on color { ColorAnimation { duration: 120 } }
            }

            Text {
              anchors.centerIn: parent
              visible: root.persistentSeparators
                && !horizontalCell.separated
              text: "•"
              color: splitMouse.containsMouse
                ? root.bar.urgent : root.bar.visualTokens.sumi
              font.pixelSize: 10
              font.family: root.bar.fontFamily
              opacity: root.v2Editing
                ? splitMouse.containsMouse ? 0.95 : 0.34
                : splitMouse.containsMouse ? 0.9 : 0

              Behavior on opacity { NumberAnimation { duration: 120 } }
            }

            MouseArea {
              id: splitMouse
              anchors.fill: parent
              enabled: root.persistentSeparators
              hoverEnabled: true
              acceptedButtons: Qt.LeftButton
              cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
              onClicked: root.toggleSeparator(horizontalCell.modelData)
            }
          }
        }
      }

      Item {
        id: addSlotTarget

        width: root.canAddV2Slot ? 28 : 0
        height: root.canAddV2Slot ? root.tokenNumber("slotHeight", 28) : 0
        visible: root.canAddV2Slot

        Rectangle {
          x: root.groupSpacing
          anchors.verticalCenter: parent.verticalCenter
          width: 28
          height: 28
          radius: root.tokenNumber("tileRadius", 8)
          color: addSlotMouse.containsMouse
            ? Qt.rgba(root.bar.urgent.r, root.bar.urgent.g,
                root.bar.urgent.b, 0.14)
            : Qt.rgba(root.bar.foreground.r, root.bar.foreground.g,
                root.bar.foreground.b, 0.04)
          border.width: 1
          border.color: addSlotMouse.containsMouse
            ? root.bar.urgent
            : root.tokenColor("pillBorder", root.bar.foreground)

          Text {
            anchors.centerIn: parent
            text: "+"
            color: addSlotMouse.containsMouse
              ? root.bar.urgent
              : root.tokenColor("sumi", root.bar.foreground)
            font.family: root.bar.fontFamily
            font.pixelSize: 14
          }

          MouseArea {
            id: addSlotMouse
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton
            cursorShape: Qt.PointingHandCursor
            onClicked: root.bar.layoutController.addV2Slot(root.region)
          }
        }
      }
    }
  }

  Component {
    id: verticalGroups

    Column {
      id: verticalColumn

      spacing: 0
      readonly property var groupGeometry: []
      readonly property int lastVisibleIndex: {
        var last = -1
        for (var i = 0; i < verticalRepeater.count; i++) {
          var item = verticalRepeater.itemAt(i)
          if (item && item.groupHasContent) last = i
        }
        return last
      }

      function hasContentBefore(index) {
        for (var i = index - 1; i >= 0; i--) {
          var item = verticalRepeater.itemAt(i)
          if (item && item.groupHasContent) return true
        }
        return false
      }

      Repeater {
        id: verticalRepeater
        model: root.groups

        delegate: Item {
          id: verticalCell
          required property string modelData
          required property int index
          readonly property bool groupHasContent: groupSlot.hasContent
          readonly property int leadingGap: groupHasContent
            && verticalColumn.hasContentBefore(index) ? root.groupSpacing : 0
          readonly property bool separated: groupHasContent
            && index < verticalColumn.lastVisibleIndex && root.splitAfter(index)
          implicitWidth: groupHasContent ? groupSlot.implicitWidth : 0
          implicitHeight: groupHasContent
            ? leadingGap + groupSlot.implicitHeight + (separated ? root.splitGrow : 0)
            : 0
          width: implicitWidth
          height: implicitHeight

          Core.GroupSlot {
            id: groupSlot
            bar: root.bar
            groupId: verticalCell.modelData
            screenName: root.screenName
            availableWidth: root.availableWidth
            y: verticalCell.leadingGap
          }
        }
      }
    }
  }

}
