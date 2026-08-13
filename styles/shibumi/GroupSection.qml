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
  readonly property bool editing: layoutSession && layoutSession.editing
  readonly property bool v2Mode: bar.layoutController
    && bar.layoutController.v2Mode === true
  readonly property bool v2Editing: editing && v2Mode
  readonly property bool v1Editing: editing && !v2Mode
  readonly property bool slotEditing: v1Editing || v2Editing
  readonly property bool layoutProtected: bar.layoutController
    && "activeLayoutProtected" in bar.layoutController
    && bar.layoutController.activeLayoutProtected === true
  readonly property bool separatorChangesAllowed: editing || !layoutProtected
  readonly property var groups: v2Mode
    ? v2Editing && bar.layoutController.v2Slots
      ? bar.layoutController.v2Slots[region] || []
      : bar.layoutController && bar.layoutController.order
        ? bar.layoutController.order[region] || [] : []
    : bar.layoutController && bar.layoutController.v1Slots
      ? bar.layoutController.v1Slots[region] || [] : []
  readonly property int baseSlotCount: bar.layoutController
    ? v2Mode && typeof bar.layoutController.baseV2SlotCount === "function"
      ? bar.layoutController.baseV2SlotCount(region)
      : !v2Mode && typeof bar.layoutController.baseV1SlotCount === "function"
        ? bar.layoutController.baseV1SlotCount(region) : 0
    : 0
  readonly property int maxSlotCount: bar.layoutController
    ? v2Mode && typeof bar.layoutController.maxV2SlotCount === "function"
      ? bar.layoutController.maxV2SlotCount(region)
      : !v2Mode && typeof bar.layoutController.maxV1SlotCount === "function"
        ? bar.layoutController.maxV1SlotCount(region) : 0
    : 0
  readonly property bool canAddSlot: slotEditing
    && maxSlotCount > baseSlotCount && groups.length < maxSlotCount
  readonly property real slotVisualSize: v2Mode
    ? tokenNumber("slotHeight", 28) : tokenNumber("pillHeight", 24)
  readonly property real slotVisualRadius: v2Mode
    ? tokenNumber("tileRadius", 8) : tokenNumber("pillRadius", 12)
  readonly property int groupSpacing: bar.visualTokens.groupGap
  readonly property int splitGrow: bar.visualTokens.splitGap
  readonly property bool persistentSeparators:
    bar.visualTokens && bar.visualTokens.v2Shell === true
  readonly property var stateService: bar && bar.shell
    && typeof bar.shell.serviceFor === "function"
    ? bar.shell.serviceFor("hancore.shibumi.state") : null
  readonly property int stateRevision: stateService
    && stateService.revision !== undefined
    ? Number(stateService.revision) || 0 : 0
  readonly property var stateConfig: stateService && stateService.config
    ? stateService.config : ({})
  readonly property var contentItem: content.item
  readonly property var groupGeometry: contentItem && contentItem.groupGeometry
    ? contentItem.groupGeometry : []
  readonly property var separatorGeometry: contentItem
    && contentItem.separatorGeometry ? contentItem.separatorGeometry : []
  readonly property int separatorHitTargetCount: separatorHitRepeater.count
  readonly property int enabledSeparatorHitTargetCount: {
    void(separatorHitRepeater.count)
    var enabledCount = 0
    for (var index = 0; index < separatorHitRepeater.count; index++) {
      var target = separatorHitRepeater.itemAt(index)
      if (target) {
        void(target.enabled)
        if (target.enabled) enabledCount++
      }
    }
    return enabledCount
  }
  property string hoveredSeparatorGroupId: ""
  readonly property var stageBudgetWidths: contentItem
    && contentItem.stageBudgetWidths ? contentItem.stageBudgetWidths : [0, 0, 0, 0]
  readonly property real editingWidthOverhead: slotEditing && contentItem
    ? Math.max(0, Number(contentItem.layoutWidth || 0)
      - Number(stageBudgetWidths[0] || 0))
    : 0
  readonly property real minimumResponsiveWidth: contentItem
    && contentItem.minimumResponsiveWidth !== undefined
      ? Number(contentItem.minimumResponsiveWidth) || 0 : implicitWidth

  implicitWidth: contentItem && "layoutWidth" in contentItem
    ? contentItem.layoutWidth : contentItem ? contentItem.implicitWidth : 0
  implicitHeight: contentItem && "layoutHeight" in contentItem
    ? contentItem.layoutHeight : contentItem ? contentItem.implicitHeight : 0
  width: implicitWidth
  height: implicitHeight

  // QML Repeaters rebuild every delegate when a JavaScript array model is
  // replaced. V1 extension changes must retain existing widget owners (most
  // importantly G1 and its open Control Center), so mirror the order into a
  // row-stable model and only insert, move, or remove changed groups.
  ListModel { id: stableGroupModel }

  function stableGroupValues() {
    const result = []
    for (let index = 0; index < stableGroupModel.count; index++)
      result.push(String(stableGroupModel.get(index).groupId || ""))
    return result
  }

  function isGroupSubsequence(shorter, longer) {
    let cursor = 0
    for (let index = 0; index < longer.length
        && cursor < shorter.length; index++) {
      if (String(longer[index] || "") === String(shorter[cursor] || ""))
        cursor++
    }
    return cursor === shorter.length
  }

  function syncStableGroups() {
    const desired = Array.isArray(groups) ? groups : []
    const current = stableGroupValues()
    if (JSON.stringify(current) === JSON.stringify(desired)) return

    // Pure additions/removals retain every unchanged delegate. Reorders need
    // a rebuild because Repeater row moves do not change the visual child
    // order; edit mode already closes panels before such a drag operation.
    if (isGroupSubsequence(current, desired)) {
      let currentIndex = 0
      for (let target = 0; target < desired.length; target++) {
        const groupId = String(desired[target] || "")
        if (currentIndex < stableGroupModel.count
            && String(stableGroupModel.get(currentIndex).groupId || "")
              === groupId) {
          currentIndex++
          continue
        }
        stableGroupModel.insert(target, { groupId: groupId })
        currentIndex++
      }
      return
    }
    if (isGroupSubsequence(desired, current)) {
      let desiredIndex = desired.length - 1
      for (let index = stableGroupModel.count - 1; index >= 0; index--) {
        const groupId = String(stableGroupModel.get(index).groupId || "")
        if (desiredIndex >= 0
            && groupId === String(desired[desiredIndex] || "")) {
          desiredIndex--
          continue
        }
        stableGroupModel.remove(index)
      }
      return
    }
    stableGroupModel.clear()
    for (let index = 0; index < desired.length; index++)
      stableGroupModel.append({ groupId: String(desired[index] || "") })
  }

  onGroupsChanged: syncStableGroups()
  Component.onCompleted: syncStableGroups()

  function splitAfter(index) {
    // Keep the replaced config object itself in the dependency graph. Method
    // calls across the plugin-service boundary do not reliably preserve the
    // nested config read, and revision is not forwarded by every host proxy.
    void(root.stateRevision)
    void(root.stateConfig)
    const groupId = index >= 0 && index < groups.length
      ? String(groups[index]) : ""
    const widgetSettings = root.stateConfig && root.stateConfig.widgets
      && root.stateConfig.widgets[groupId]
      ? root.stateConfig.widgets[groupId] : ({})
    const appearanceSeparator = persistentSeparators
      && widgetSettings.separator === true
    // V2 separators are group-owned appearance state. Never OR them with
    // V1's positional split array, otherwise an active V1 split makes the V2
    // line impossible to turn off even though the V2 state changed correctly.
    if (persistentSeparators) return appearanceSeparator
    return bar.layoutController
      && typeof bar.layoutController.splitEnabled === "function"
      ? bar.layoutController.splitEnabled(region, index) : false
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

  function toggleSeparator(groupId, index) {
    if (!separatorChangesAllowed) return false
    if (persistentSeparators && bar
        && typeof bar.toggleGroupSeparator === "function")
      return bar.toggleGroupSeparator(String(groupId || ""), editing)
    return !v2Mode && bar.layoutController
      && typeof bar.layoutController.toggleSplit === "function"
      ? bar.layoutController.toggleSplit(region, Number(index), editing) : false
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

  // Separator markers may be painted into the gap owned by the following
  // cell. Keep their input layer at section scope so parent delegate bounds
  // cannot make an otherwise visible V2 marker unclickable.
  Item {
    anchors.fill: parent
    z: 50

    Repeater {
      id: separatorHitRepeater
      model: root.bar.vertical ? [] : root.separatorGeometry

      delegate: MouseArea {
        required property var modelData

        x: Number(modelData.markerCenter || 0) - width / 2
        y: 0
        width: 14
        height: root ? root.height : 0
        // Keep the hit target active while protected so clicks cannot fall
        // through the intentionally overlapping divider area to a widget.
        // toggleSeparator() consumes the click without mutating layout state.
        enabled: root ? root.persistentSeparators || !root.v2Mode : false
        hoverEnabled: root ? root.separatorChangesAllowed : false
        acceptedButtons: Qt.LeftButton
        cursorShape: root && root.separatorChangesAllowed
          ? Qt.PointingHandCursor : Qt.ArrowCursor

        onEntered: {
          if (root)
            root.hoveredSeparatorGroupId = String(modelData.groupId || "")
        }
        onExited: {
          if (root && root.hoveredSeparatorGroupId
              === String(modelData.groupId || ""))
            root.hoveredSeparatorGroupId = ""
        }
        onClicked: {
          if (root) root.toggleSeparator(
            String(modelData.groupId || ""), Number(modelData.index))
        }
        Component.onDestruction: {
          if (root && root.hoveredSeparatorGroupId
              === String(modelData.groupId || ""))
            root.hoveredSeparatorGroupId = ""
        }
      }
    }
  }

  Component {
    id: horizontalGroups

    Row {
      id: horizontalRow

      spacing: 0
      function scheduleLayout() {
        if (!layoutTimer.running) layoutTimer.start()
      }
      Timer {
        id: layoutTimer
        interval: 0
        onTriggered: {
          if (horizontalRow) horizontalRow.forceLayout()
        }
      }
      readonly property real layoutWidth: {
        if (!root) return 0
        void(root.visibilityStage)
        var total = 0
        for (var i = 0; i < horizontalRepeater.count; i++) {
          var item = horizontalRepeater.itemAt(i)
          if (item) total += item.width
        }
        return total + (root.canAddSlot
          ? root.groupSpacing + addSlotTarget.width : 0)
      }
      readonly property real layoutHeight: {
        if (!root) return 0
        var height = 0
        for (var i = 0; i < horizontalRepeater.count; i++) {
          var item = horizontalRepeater.itemAt(i)
          if (item && item.visible) height = Math.max(height, item.height)
        }
        return Math.max(height, root.canAddSlot ? addSlotTarget.height : 0)
      }
      readonly property real minimumResponsiveWidth: {
        if (!root) return 0
        void(root.groups)
        var total = 0
        var visibleCount = 0
        for (var i = 0; i < horizontalRepeater.count; i++) {
          var item = horizontalRepeater.itemAt(i)
          if (!item || !item.groupHasContent) continue
          total += item.minimumGroupWidth
          if (item.separated) total += root.splitGrow
          visibleCount++
        }
        return total + Math.max(0, visibleCount - 1) * root.groupSpacing
      }
      readonly property var stageBudgetWidths: {
        if (!root) return [0, 0, 0, 0]
        void(root.groups)
        var widths = [0, 0, 0, 0]
        for (var stage = 0; stage < 4; stage++) {
          var visibleCount = 0
          for (var i = 0; i < horizontalRepeater.count; i++) {
            var item = horizontalRepeater.itemAt(i)
            if (!item || !item.budgetHasContent
                || !root.groupVisibleAtStage(item.modelData, stage)) continue
            widths[stage] += item.naturalGroupWidth
            if (horizontalRow.splitAfterAtStage(item.index, stage))
              widths[stage] += root.splitGrow
            visibleCount++
          }
          widths[stage] += Math.max(0, visibleCount - 1) * root.groupSpacing
        }
        return widths
      }
      readonly property var groupGeometry: {
        if (!root) return []
        void(root.groups)
        var result = []
        for (var i = 0; i < horizontalRepeater.count; i++) {
          var item = horizontalRepeater.itemAt(i)
          if (item) {
            void(item.x)
            void(item.contentLeft)
            void(item.contentRight)
            void(item.contentShown)
            void(item.effectiveHasContent)
          }
          if (!item || !(root.v2Editing
              ? item.effectiveHasContent : item.contentShown)) continue
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
        if (!root) return []
        void(root.groups)
        var result = []
        for (var i = 0; i < horizontalRepeater.count; i++) {
          var item = horizontalRepeater.itemAt(i)
          if (item) {
            void(item.x)
            void(item.separatorAvailable)
            void(item.separatorIndex)
            void(item.visualRightEdge)
            void(item.separatorCenter)
          }
          if (!item || !item.separatorAvailable) continue
          result.push({
            groupId: item.modelData,
            index: item.separatorIndex,
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

      function nextShownIndex(index) {
        void(horizontalRepeater.count)
        for (var i = index + 1; i < horizontalRepeater.count; i++) {
          var item = horizontalRepeater.itemAt(i)
          if (item && item.contentShown) return i
        }
        return -1
      }

      function nextBudgetShownIndex(index, stage) {
        if (!root) return -1
        void(horizontalRepeater.count)
        for (var i = index + 1; i < horizontalRepeater.count; i++) {
          var item = horizontalRepeater.itemAt(i)
          if (item && item.budgetHasContent
              && root.groupVisibleAtStage(item.modelData, stage)) return i
        }
        return -1
      }

      function splitAfterAtStage(index, stage) {
        if (!root) return false
        var nextIndex = nextBudgetShownIndex(index, stage)
        if (nextIndex <= index) return false
        return root.v2Mode
          ? root.splitAfter(index)
          : root.splitAfter(nextIndex - 1)
      }

      Repeater {
        id: horizontalRepeater
        model: stableGroupModel

        delegate: Item {
          id: horizontalCell
          required property string groupId
          required property int index
          readonly property string modelData: groupId
          // The bar outlives every per-output section. Break this initial
          // binding on completion so GroupSlot never receives null while its
          // bound declaration context is being destroyed.
          property var lifecycleBar: root ? root.bar : null
          readonly property bool emptySlot: root
            ? root.slotEditing && modelData === "" : false
          readonly property bool groupHasContent: groupSlot.hasContent
          readonly property bool stageShown: root && modelData !== ""
            ? root.groupVisibleAtStage(modelData, root.visibilityStage) : false
          readonly property bool contentShown: modelData !== ""
            && groupSlot.groupEnabled && groupHasContent && stageShown
          readonly property bool proxySlot: root
            ? root.v1Editing && modelData !== "" && !contentShown : false
          readonly property bool placeholderSlot: emptySlot || proxySlot
          readonly property bool removableEmptySlot: root && emptySlot
            ? root.v2Mode ? index >= root.baseSlotCount
              : root.bar.layoutController
                && typeof root.bar.layoutController.isExtraV1Slot === "function"
                && root.bar.layoutController.isExtraV1Slot(root.region, index)
            : false
          readonly property bool autoShown: placeholderSlot || stageShown
          readonly property Item targetVisual: placeholderSlot
            ? emptySlotTarget : groupSlot
          property bool measuredHasContent: false
          property real measuredNaturalGroupWidth: 0
          property real measuredMinimumGroupWidth: 0
          readonly property bool effectiveHasContent: placeholderSlot
            || contentShown
          readonly property bool budgetHasContent: groupSlot.groupEnabled
            && (groupHasContent
            || (measuredHasContent && groupSlot.groupEnabled
              && !autoShown))
          readonly property real naturalGroupWidth: placeholderSlot
            ? emptySlotTarget.width : groupHasContent
              ? groupSlot.implicitWidth : measuredNaturalGroupWidth
          readonly property real minimumGroupWidth: placeholderSlot
            ? emptySlotTarget.width : groupHasContent
              ? groupSlot.minimumResponsiveWidth : measuredMinimumGroupWidth
          readonly property real contentLeft: targetVisual.x
          readonly property real contentRight: targetVisual.x + targetVisual.width
          readonly property real visualRightEdge: groupSlot.x + groupSlot.width
          readonly property int nextShownIndex: horizontalRow
            ? horizontalRow.nextShownIndex(index) : -1
          // V1 splits remain positional. When disabled or empty slots sit
          // before the next rendered group, the visible marker belongs to the
          // last slot boundary before that group (for example, directly left
          // of Brightness), not to the earlier rendered group's own index.
          readonly property int separatorIndex: root
            ? root.v2Mode
              ? index : nextShownIndex > index ? nextShownIndex - 1 : index
            : index
          readonly property bool separatorAvailable:
            splitMarker.hasFollowingGroup
          readonly property real separatorCenter:
            splitMarker.x + splitMarker.width / 2
          property var targetSession: root ? root.layoutSession : null
          property var registeredSession: null
          property var registeredItem: null
          property string registeredGroupId: ""
          property string registeredRegion: ""
          property int registeredIndex: -1
          property bool registeredAsSlot: false
          readonly property int leadingGap: effectiveHasContent
            && root && horizontalRow
            && horizontalRow.hasContentBefore(index) ? root.groupSpacing : 0
          readonly property bool separated: contentShown && root
            && nextShownIndex > index
            && root.splitAfter(separatorIndex)
          implicitWidth: effectiveHasContent
            ? leadingGap + targetVisual.width
              + (separated && root ? root.splitGrow : 0)
            : 0
          implicitHeight: effectiveHasContent && root
            ? root.v2Mode ? targetVisual.height : 32 : 0
          width: implicitWidth
          height: implicitHeight
          onWidthChanged: {
            if (horizontalRow) horizontalRow.scheduleLayout()
          }
          onVisibleChanged: {
            if (horizontalRow) horizontalRow.scheduleLayout()
          }
          // Keep the cell visible while its widget determines its initial
          // size. Basing ancestor visibility on groupHasContent would make
          // the child's effective visible state false and deadlock discovery.
          visible: autoShown && (placeholderSlot || groupSlot.groupEnabled)
          opacity: autoShown ? 1 : 0
          // The V1 split handle is 14px wide while an unsplit gap is only 6px.
          // Let the handle overlap the adjacent cells instead of clipping its
          // center outside this delegate.
          clip: false

          Behavior on opacity {
            NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
          }

          function clearTargetRegistration() {
            if (registeredSession && registeredItem
                && typeof registeredSession.unregisterTarget === "function")
              registeredSession.unregisterTarget(registeredItem)

            registeredSession = null
            registeredItem = null
            registeredGroupId = ""
            registeredRegion = ""
            registeredIndex = -1
            registeredAsSlot = false
          }

          function syncTargetRegistration(force) {
            const owner = root
            if (!owner) {
              clearTargetRegistration()
              return
            }

            const nextSession = targetSession
            const nextItem = targetVisual
            const nextGroupId = String(modelData || "")
            const nextAsSlot = owner.slotEditing
            const unchanged = registeredSession === nextSession
              && registeredItem === nextItem
              && registeredGroupId === nextGroupId
              && registeredRegion === owner.region
              && registeredIndex === index
              && registeredAsSlot === nextAsSlot
              && effectiveHasContent
            if (unchanged && force !== true) return

            clearTargetRegistration()
            if (!nextSession || !effectiveHasContent || !nextItem) return

            if (nextAsSlot
                && typeof nextSession.registerSlotTarget === "function")
              nextSession.registerSlotTarget(
                owner.region, index, nextGroupId, nextItem)
            else if (typeof nextSession.registerTarget === "function")
              nextSession.registerTarget(nextGroupId, nextItem)
            else return

            registeredSession = nextSession
            registeredItem = nextItem
            registeredGroupId = nextGroupId
            registeredRegion = owner.region
            registeredIndex = index
            registeredAsSlot = nextAsSlot
          }

          function retainResponsiveMetrics() {
            if (!groupHasContent || groupSlot.implicitWidth <= 0.5) return
            measuredHasContent = true
            measuredNaturalGroupWidth = Math.max(0, groupSlot.implicitWidth)
            measuredMinimumGroupWidth = Math.max(0,
              groupSlot.minimumResponsiveWidth)
          }

          onTargetSessionChanged: {
            syncTargetRegistration()
            registrationTimer.restart()
          }
          onGroupHasContentChanged: {
            retainResponsiveMetrics()
            registrationTimer.restart()
          }
          onAutoShownChanged: registrationTimer.restart()
          onPlaceholderSlotChanged: {
            syncTargetRegistration()
            registrationTimer.restart()
          }
          onContentShownChanged: registrationTimer.restart()
          Connections {
            target: root
            function onSlotEditingChanged() {
              horizontalCell.syncTargetRegistration()
              registrationTimer.restart()
            }
          }
          onModelDataChanged: {
            syncTargetRegistration()
            registrationTimer.restart()
          }
          onIndexChanged: {
            syncTargetRegistration()
            registrationTimer.restart()
          }
          Component.onDestruction: {
            if (registrationTimer) registrationTimer.stop()
            clearTargetRegistration()
          }
          Component.onCompleted: {
            const currentBar = lifecycleBar
            lifecycleBar = currentBar
            retainResponsiveMetrics()
            registrationTimer.restart()
          }
          Timer {
            id: registrationTimer
            interval: 0
            onTriggered: {
              if (root) horizontalCell.syncTargetRegistration(true)
            }
          }

          Core.GroupSlot {
            id: groupSlot
            bar: horizontalCell.lifecycleBar
            groupId: horizontalCell.modelData
            screenName: root ? root.screenName : ""
            availableWidth: root ? root.availableWidth : 0
            enabled: root ? !root.slotEditing : false
            x: horizontalCell.leadingGap
            anchors.verticalCenter: parent.verticalCenter
            opacity: root && root.layoutSession && root.layoutSession.active
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
            width: root && horizontalCell.placeholderSlot
              ? root.slotVisualSize : 0
            height: root && horizontalCell.placeholderSlot
              ? root.slotVisualSize : 0
            visible: root ? horizontalCell.placeholderSlot : false
            opacity: root && root.layoutSession && root.layoutSession.active
              && root.layoutSession.sourceGroupId === horizontalCell.modelData
              ? 0.28 : 1
            radius: root ? root.slotVisualRadius : 0
            color: root
              ? removeEmptyMouse.containsMouse
                ? Qt.rgba(root.bar.urgent.r, root.bar.urgent.g,
                    root.bar.urgent.b, 0.14)
                : Qt.rgba(root.bar.foreground.r, root.bar.foreground.g,
                    root.bar.foreground.b, 0.04)
              : "transparent"
            border.width: 1
            border.color: root
              ? removeEmptyMouse.containsMouse
                ? root.bar.urgent
                : root.tokenColor("pillBorder", root.bar.foreground)
              : "transparent"

            Text {
              anchors.centerIn: parent
              text: horizontalCell.removableEmptySlot ? "×" : "·"
              color: root
                ? removeEmptyMouse.containsMouse
                  ? root.bar.urgent
                  : root.tokenColor("sumi", root.bar.foreground)
                : "transparent"
              font.family: root ? root.bar.fontFamily : ""
              font.pixelSize: 12
            }

            MouseArea {
              id: removeEmptyMouse
              anchors.fill: parent
              hoverEnabled: true
              acceptedButtons: Qt.LeftButton
              enabled: root ? horizontalCell.removableEmptySlot : false
              cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
              onClicked: {
                if (!root) return
                if (root.v2Mode)
                  root.bar.layoutController.removeV2SlotAt(
                    root.region, horizontalCell.index)
                else root.bar.layoutController.removeV1SlotAt(
                  root.region, horizontalCell.index)
              }
            }
          }

          Rectangle {
            x: horizontalCell.targetVisual.x - 2
            y: horizontalCell.targetVisual.y - 2
            width: horizontalCell.targetVisual.width + 4
            height: horizontalCell.targetVisual.height + 4
            visible: root && root.layoutSession && root.layoutSession.editing
              && root.layoutSession.active
              && root.layoutSession.targetItem === horizontalCell.targetVisual
            color: root ? Qt.rgba(root.bar.urgent.r, root.bar.urgent.g,
              root.bar.urgent.b, 0.18) : "transparent"
            border.width: 2
            border.color: root ? root.bar.urgent : "transparent"
            radius: root ? root.bar.visualTokens.pillRadius : 0
            z: 20
          }

          MouseArea {
            id: dragMouse

            x: horizontalCell.targetVisual.x
            y: horizontalCell.targetVisual.y
            width: horizontalCell.targetVisual.width
            height: horizontalCell.targetVisual.height
            enabled: root && root.layoutSession && root.layoutSession.editing
              && horizontalCell.modelData !== ""
              && horizontalCell.effectiveHasContent
            visible: enabled
            acceptedButtons: Qt.LeftButton
            hoverEnabled: enabled
            preventStealing: true
            cursorShape: enabled
              ? (pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor)
              : Qt.ArrowCursor
            z: 30

            function windowPoint(mouse) {
              return mapToItem(null, mouse.x, mouse.y)
            }

            onPressed: mouse => {
              if (!root || !root.layoutSession) return
              const point = windowPoint(mouse)
              root.layoutSession.begin(horizontalCell.modelData,
                horizontalCell.targetVisual,
                point.x, point.y)
            }
            onPositionChanged: mouse => {
              if (!pressed || !root || !root.layoutSession
                  || !root.layoutSession.active) return
              const point = windowPoint(mouse)
              root.layoutSession.move(point.x, point.y)
            }
            onReleased: {
              if (root && root.layoutSession && root.layoutSession.active)
                root.layoutSession.drop()
            }
            onCanceled: {
              if (root && root.layoutSession) root.layoutSession.cancel()
            }
          }

          Item {
            id: splitMarker

            readonly property bool hasFollowingGroup: root && horizontalRow
              && horizontalCell.contentShown
              && (root.v2Mode
                ? horizontalRow.hasContentAfter(horizontalCell.index)
                : horizontalCell.nextShownIndex > horizontalCell.index)
            x: groupSlot.x + groupSlot.width
              + (root
                ? root.separatorCenterOffset(horizontalCell.separated) : 0)
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
              visible: root && horizontalCell.separated
                && root.persistentSeparators
              color: root
                ? root.hoveredSeparatorGroupId === horizontalCell.modelData
                  ? root.bar.urgent
                  : root.tokenColor("separator", root.bar.visualTokens.sumi)
                : "transparent"
              opacity: 0.62

              Behavior on color { ColorAnimation { duration: 120 } }
            }

            Text {
              anchors.centerIn: parent
              visible: root ? root.persistentSeparators
                ? !horizontalCell.separated : !root.v2Mode : false
              text: root
                ? root.persistentSeparators || !horizontalCell.separated
                  ? "•" : "│"
                : ""
              color: root
                ? root.hoveredSeparatorGroupId === horizontalCell.modelData
                    || horizontalCell.separated
                  ? root.bar.urgent : root.bar.visualTokens.sumi
                : "transparent"
              font.pixelSize: 10
              font.family: root ? root.bar.fontFamily : ""
              opacity: root
                ? root.persistentSeparators && root.v2Editing
                  ? root.hoveredSeparatorGroupId === horizontalCell.modelData
                    ? 0.95 : 0.34
                  : root.hoveredSeparatorGroupId === horizontalCell.modelData
                    ? 0.9 : 0
                : 0

              Behavior on opacity { NumberAnimation { duration: 120 } }
            }

          }
        }
      }

      Item {
        id: addSlotTarget

        width: root && root.canAddSlot ? root.slotVisualSize : 0
        height: root && root.canAddSlot
          ? root.v1Editing ? 32 : root.tokenNumber("slotHeight", 28) : 0
        visible: root ? root.canAddSlot : false

        Rectangle {
          x: root ? root.groupSpacing : 0
          anchors.verticalCenter: parent.verticalCenter
          width: root ? root.slotVisualSize : 0
          height: root ? root.slotVisualSize : 0
          radius: root ? root.slotVisualRadius : 0
          color: root
            ? addSlotMouse.containsMouse
              ? Qt.rgba(root.bar.urgent.r, root.bar.urgent.g,
                  root.bar.urgent.b, 0.14)
              : Qt.rgba(root.bar.foreground.r, root.bar.foreground.g,
                  root.bar.foreground.b, 0.04)
            : "transparent"
          border.width: 1
          border.color: root
            ? addSlotMouse.containsMouse
              ? root.bar.urgent
              : root.tokenColor("pillBorder", root.bar.foreground)
            : "transparent"

          Text {
            anchors.centerIn: parent
            text: "+"
            color: root
              ? addSlotMouse.containsMouse
                ? root.bar.urgent
                : root.tokenColor("sumi", root.bar.foreground)
              : "transparent"
            font.family: root ? root.bar.fontFamily : ""
            font.pixelSize: 14
          }

          MouseArea {
            id: addSlotMouse
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton
            enabled: root !== null
            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: {
              if (!root) return
              if (root.v2Mode)
                root.bar.layoutController.addV2Slot(root.region)
              else root.bar.layoutController.addV1Slot(root.region)
            }
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
        model: stableGroupModel

        delegate: Item {
          id: verticalCell
          required property string groupId
          required property int index
          readonly property string modelData: groupId
          property var lifecycleBar: root ? root.bar : null
          readonly property bool groupHasContent: groupSlot.hasContent
          readonly property int leadingGap: root && verticalColumn
            && groupHasContent && verticalColumn.hasContentBefore(index)
            ? root.groupSpacing : 0
          readonly property bool separated: root && verticalColumn
            && groupHasContent && index < verticalColumn.lastVisibleIndex
            ? root.splitAfter(index) : false
          implicitWidth: groupHasContent ? groupSlot.implicitWidth : 0
          implicitHeight: root && groupHasContent
            ? leadingGap + groupSlot.implicitHeight
              + (separated ? root.splitGrow : 0)
            : 0
          width: implicitWidth
          height: implicitHeight

          Component.onCompleted: {
            const currentBar = lifecycleBar
            lifecycleBar = currentBar
          }

          Core.GroupSlot {
            id: groupSlot
            bar: verticalCell.lifecycleBar
            groupId: verticalCell.modelData
            screenName: root ? root.screenName : ""
            availableWidth: root ? root.availableWidth : 0
            y: verticalCell.leadingGap
          }
        }
      }
    }
  }

}
