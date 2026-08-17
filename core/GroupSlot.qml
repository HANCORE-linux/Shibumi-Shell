pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import "GroupRegistry.js" as GroupRegistry

Item {
  id: root

  required property var bar
  required property string groupId
  property string screenName: ""
  property real availableWidth: 0
  readonly property var stateService: bar && bar.shell
    && typeof bar.shell.serviceFor === "function"
    ? bar.shell.serviceFor("hancore.shibumi.state") : null
  readonly property var stateConfig: stateService && stateService.config
    ? stateService.config : ({})
  readonly property int stateRevision: stateService
    && "revision" in stateService
      ? Number(stateService.revision) || 0 : 0
  readonly property bool v2Shell: !!(bar.visualTokens
    && bar.visualTokens.v2Shell === true)
  readonly property var groupSettings: {
    // Calls across the plugin-service boundary do not reliably retain nested
    // config dependencies. Observe both published invalidation surfaces before
    // resolving variant-local settings and explicit WidgetSlot overrides.
    void(stateConfig)
    void(stateRevision)
    return stateService
      && typeof stateService.groupSettingsForVariant === "function"
      ? stateService.groupSettingsForVariant(groupId,
          v2Shell ? "v2" : "v1")
      : stateConfig.widgets ? stateConfig.widgets[groupId] || ({}) : ({})
  }
  readonly property bool groupEnabled: {
    // Calls across the plugin-service boundary do not reliably retain nested
    // config dependencies. Observe the published config/revision explicitly
    // so an optional group enabled after startup actually creates its slot.
    void(stateConfig)
    void(stateRevision)
    return stateService
      && typeof stateService.groupEnabledForVariant === "function"
        ? stateService.groupEnabledForVariant(
            groupId, v2Shell ? "v2" : "v1")
        : groupSettings.enabled !== false
  }
  readonly property string dynamicModuleId:
    GroupRegistry.dynamicModuleIdForGroup(groupId)
  readonly property bool dynamicV1Group: !v2Shell && dynamicModuleId !== ""
  // These optional suite widgets already own a native PillSurface. Keep the
  // compatibility wrapper only for external dynamic widgets so inherited and
  // custom fills both composite exactly once.
  readonly property bool dynamicV1WidgetOwnsSurface: dynamicV1Group
    && [
      "hancore.shibumi.temperature",
      "hancore.shibumi.gpu",
      "hancore.shibumi.storage"
    ].indexOf(dynamicModuleId) >= 0
  readonly property bool dynamicV1CustomFill: dynamicV1WidgetOwnsSurface
    && !!(bar.visualTokens
      && typeof bar.visualTokens.widgetHasFill === "function"
      && bar.visualTokens.widgetHasFill(groupSettings))
  // Per-group fill, border, radius, and padding belong to V2. V1 preserves
  // the original widget-owned pill recipe independently of these settings.
  readonly property bool appearanceFill: v2Shell && !!(bar.visualTokens
    && typeof bar.visualTokens.widgetHasFill === "function"
    && bar.visualTokens.widgetHasFill(groupSettings))
  readonly property bool appearanceBorder: v2Shell && !!(bar.visualTokens
    && typeof bar.visualTokens.widgetHasBorder === "function"
    && bar.visualTokens.widgetHasBorder(groupSettings))
  readonly property bool decorated: appearanceFill || appearanceBorder
  readonly property real appearancePadding: v2Shell && bar.visualTokens
    && typeof bar.visualTokens.widgetPadding === "function"
    ? bar.visualTokens.widgetPadding(groupSettings, decorated)
    : decorated ? 3 : 0
  readonly property real appearancePaddingX: appearancePadding
  readonly property real appearancePaddingY: appearancePadding > 0
    ? Math.max(1, appearancePadding - 1) : 0
  // Keep the Repeater model independent from widget settings. Replacing this
  // model for a value-only settings update destroys the live widget and any
  // open panel it owns.
  readonly property var moduleIds: GroupRegistry.moduleIdsFor(
    groupId, bar.layoutConfig)
  readonly property int moduleCount: moduleIds.length
  readonly property var contentItem: content.item
  readonly property real v2SurfaceHeight: bar.visualTokens
    && bar.visualTokens.pillHeight !== undefined
    ? Number(bar.visualTokens.pillHeight) || 24 : 24
  readonly property real v1SlotHeight: bar.visualTokens
    && bar.visualTokens.slotHeight !== undefined
    ? Number(bar.visualTokens.slotHeight) || 28 : 28
  readonly property Item visualSurfaceItem: widgetSurface
  readonly property bool dynamicShadowLoaded:
    dynamicShadowLoader.item !== null
  readonly property bool hasContent: implicitWidth > 0.5 && implicitHeight > 0.5
  readonly property real minimumResponsiveWidth: contentItem
    && "minimumResponsiveWidth" in contentItem
      ? Math.max(0, Number(contentItem.minimumResponsiveWidth) || 0)
      : implicitWidth

  implicitWidth: contentItem
    ? contentItem.implicitWidth + appearancePaddingX * 2 : 0
  implicitHeight: contentItem
    ? v2Shell
      ? Math.max(contentItem.implicitHeight,
          decorated ? v2SurfaceHeight : 0)
      : contentItem.implicitHeight + appearancePaddingY * 2
    : 0
  width: implicitWidth
  height: implicitHeight

  function resolvedEntry(moduleId) {
    return GroupRegistry.entryFor(groupId, moduleId, groupSettings,
      bar.layoutConfig)
  }

  Rectangle {
    id: widgetSurface

    anchors.verticalCenter: parent.verticalCenter
    width: parent.width
    height: root.v2Shell || root.dynamicV1Group
      ? Math.min(parent.height, root.v2SurfaceHeight) : parent.height
    visible: root.decorated
      || (root.dynamicV1Group && !root.dynamicV1WidgetOwnsSurface)
    radius: root.dynamicV1Group && root.bar.visualTokens
      && root.bar.visualTokens.pillRadius !== undefined
      ? root.bar.visualTokens.pillRadius : root.bar.visualTokens
      && typeof root.bar.visualTokens.widgetRadius === "function"
      ? root.bar.visualTokens.widgetRadius(root.groupSettings)
      : root.bar.visualTokens
        && root.bar.visualTokens.tileRadius !== undefined
        ? root.bar.visualTokens.tileRadius : 0
    opacity: root.dynamicV1Group ? 1 : root.bar.visualTokens
      && typeof root.bar.visualTokens.widgetSurfaceOpacity === "function"
      ? root.bar.visualTokens.widgetSurfaceOpacity(root.groupSettings) : 1
    color: root.dynamicV1Group && root.bar.visualTokens
      && root.bar.visualTokens.pill !== undefined
      ? root.bar.visualTokens.pill : root.appearanceFill
      && typeof root.bar.visualTokens.widgetFillColor === "function"
      ? root.bar.visualTokens.widgetFillColor(root.groupSettings)
      : "transparent"
    border.width: root.dynamicV1Group && root.bar.visualTokens
      && root.bar.visualTokens.pillBorderWidth !== undefined
      ? root.bar.visualTokens.pillBorderWidth
      : root.appearanceBorder && root.bar.visualTokens
      && typeof root.bar.visualTokens.widgetBorderWidth === "function"
      ? root.bar.visualTokens.widgetBorderWidth(root.groupSettings)
      : root.appearanceBorder ? 1 : 0
    border.color: root.dynamicV1Group && root.bar.visualTokens
      && root.bar.visualTokens.pillBorder !== undefined
      ? root.bar.visualTokens.pillBorder : root.appearanceBorder
      && typeof root.bar.visualTokens.widgetBorderColor === "function"
      ? root.bar.visualTokens.widgetBorderColor(root.groupSettings)
      : "transparent"

    Loader {
      id: dynamicShadowLoader

      anchors.fill: parent
      active: root.dynamicV1Group && !root.dynamicV1WidgetOwnsSurface
        && root.bar.visualTokens
        && root.bar.visualTokens.shadowEnabled === true
      sourceComponent: active ? dynamicV1Shadow : null
      z: -1
    }

    Component {
      id: dynamicV1Shadow

      RectangularShadow {
        anchors.fill: parent
        radius: widgetSurface.radius
        blur: 8
        spread: 0
        offset: Qt.vector2d(0,
          root.bar && root.bar.position === "bottom" ? -1 : 1)
        color: root.bar.visualTokens
          && root.bar.visualTokens.pillShadow !== undefined
          ? root.bar.visualTokens.pillShadow : Qt.rgba(0, 0, 0, 0.55)
      }
    }
  }

  Loader {
    id: content
    x: root.appearancePaddingX
    y: root.v2Shell
      ? Math.round((root.height - (root.contentItem
          ? root.contentItem.implicitHeight : 0)) / 2)
      : root.appearancePaddingY
    active: root.groupEnabled
    sourceComponent: !active ? null
      : root.bar.vertical ? verticalContent : horizontalContent
  }

  Component {
    id: horizontalContent

    Item {
      id: horizontalRoot

      readonly property real minimumResponsiveWidth: {
        void(moduleRow.implicitWidth)
        var total = 0
        for (var i = 0; i < moduleRepeater.count; i++) {
          var item = moduleRepeater.itemAt(i)
          if (item) total += Number(item["minimumResponsiveWidth"]) || 0
        }
        return total
      }

      function siblingWidth(excludedIndex) {
        // Re-evaluate when any asynchronously loaded sibling changes size.
        void(moduleRow.implicitWidth)
        var total = 0
        for (var i = 0; i < moduleRepeater.count; i++) {
          if (i === excludedIndex) continue
          var item = moduleRepeater.itemAt(i)
          if (item) total += item.implicitWidth
        }
        return total
      }

      implicitWidth: moduleRow.childrenRect.width
      implicitHeight: moduleRow.childrenRect.height

      Row {
        id: moduleRow

        Repeater {
          id: moduleRepeater
          model: root.moduleIds
          WidgetSlot {
            required property string modelData
            required property int index
            bar: root.bar
            entry: root.resolvedEntry(modelData)
            hostEntry: GroupRegistry.hostEntryFor(
              modelData, root.bar.layoutConfig)
            settingsOverrides: GroupRegistry.settingsOverridesFor(
              root.groupId, modelData, root.groupSettings,
              root.bar.layoutConfig)
            region: root.groupId
            screenName: root.screenName
            availableWidth: root.availableWidth > 0
              ? Math.max(0, root.availableWidth - horizontalRoot.siblingWidth(index)) : 0
            horizontalHostHeight: root.v2Shell ? 0 : root.v1SlotHeight
          }
        }
      }
    }
  }

  Component {
    id: verticalContent

    Item {
      implicitWidth: moduleColumn.childrenRect.width
      implicitHeight: moduleColumn.childrenRect.height

      Column {
        id: moduleColumn

        Repeater {
          id: moduleRepeater
          model: root.moduleIds
          WidgetSlot {
            required property string modelData
            bar: root.bar
            entry: root.resolvedEntry(modelData)
            hostEntry: GroupRegistry.hostEntryFor(
              modelData, root.bar.layoutConfig)
            settingsOverrides: GroupRegistry.settingsOverridesFor(
              root.groupId, modelData, root.groupSettings,
              root.bar.layoutConfig)
            region: root.groupId
            screenName: root.screenName
            availableWidth: root.availableWidth
          }
        }
      }
    }
  }
}
