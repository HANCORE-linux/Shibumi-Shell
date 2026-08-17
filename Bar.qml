pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Commons
import "core" as Core
import "core/GroupRegistry.js" as GroupRegistry
import "core/PanelRouting.js" as PanelRouting
import "core/WidgetFamilies.js" as WidgetFamilies
import "services" as Services
import "styles" as Styles

Item {
  id: root

  // Third-party bars are loaded asynchronously and wired after construction.
  // Keep host-injected properties optional at creation time.
  property string omarchyPath: ""
  property var shell: null
  property var manifest: null
  property var pluginRegistry: null
  property var barWidgetRegistry: null
  property var barConfig: ({})
  readonly property int shibumiHostContractVersion: 1
  readonly property string pluginSourceDir: manifest
    ? String(manifest.__sourceDir || "") : ""
  property string suitePayloadDigest: ""
  property bool suitePayloadLoaded: false
  property bool hostReady: false
  property bool outputWindowsEnabled: true

  property string home: Quickshell.env("HOME")
  property var fallbackBarConfig: ({
    position: "top",
    style: "shibumi",
    centerAnchor: "omarchy.clock",
    layout: { left: [], center: [], right: [] }
  })
  property var layoutConfig: fallbackBarConfig.layout
  property string centerAnchor: ""
  property string position: "top"
  // Quattro keeps this facade surface for stock-widget compatibility, but
  // barConfig.transparent belongs exclusively to the stock Omarchy bar.
  readonly property bool requestedTransparent: false
  readonly property bool transparent: false
  property bool barToggledOff: false
  property bool barToggleStateLoaded: false
  readonly property var idleService: root.shell
    && typeof root.shell.firstPartyServiceFor === "function"
    ? root.shell.firstPartyServiceFor("omarchy.idle") : null
  readonly property bool screensaverPreHidden: !!(idleService
    && idleService.screensaverStartedThisCycle)
  readonly property bool barHidden: barToggledOff || screensaverPreHidden
  property bool foregroundAnimationEnabled: true
  property bool centerSectionRevealHeld: false
  property bool centerHoverRevealSuppressed: false
  property string requestedStyleId: "shibumi"
  property bool styleReady: false
  readonly property var activeStyle: styleLoader.item
  readonly property var visualTokens: styleReady ? activeStyle.visualTokens : null
  readonly property var hostWidgetResolver: hostWidgetResolverService
  readonly property var layoutController: layoutStateController
  readonly property string styleId: styleRegistry.resolvedId
  readonly property var availableStyleIds: styleRegistry.availableIds
  property color foreground: styleReady ? activeStyle.foreground : Color.bar.text
  property color barForeground: styleReady ? activeStyle.barForeground : Color.bar.text
  property color background: styleReady ? activeStyle.background : Color.bar.background
  property color urgent: styleReady ? activeStyle.urgent : Color.bar.active
  property string fontFamily: styleReady ? activeStyle.fontFamily : Style.font.family
  readonly property bool injectionComplete: omarchyPath !== ""
    && shell !== null
    && manifest !== null
    && pluginRegistry !== null
    && barWidgetRegistry !== null
    && Util.isPlainObject(barConfig)
  readonly property bool vertical: position === "left" || position === "right"
  readonly property int barSize: styleReady
    ? (vertical ? activeStyle.sizeVertical : activeStyle.sizeHorizontal)
    : (vertical ? Style.bar.sizeVertical : Style.bar.sizeHorizontal)
  readonly property int barExclusiveSize: styleReady && !vertical
    ? activeStyle.exclusiveSizeHorizontal : barSize

  // Popout ownership is output-local. `activePopout` remains a compatibility
  // view of the most recently touched owner for host panels that do not yet
  // pass an output identity explicitly.
  property var activePopouts: ({})
  property var activePopout: null
  // V2 panels publish their connector geometry per output. The scalar fields
  // remain a compatibility view of the most recently updated record.
  property var connectedPanels: ({})
  property var connectedPanelOwner: null
  property string connectedPanelScreenName: ""
  property real connectedPanelX: 0
  property real connectedPanelReveal: 0
  property bool connectedPanelHostCaret: false
  property real connectedPanelCardX: 0
  property real connectedPanelCardY: 0
  property real connectedPanelCardWidth: 0
  property real connectedPanelCardHeight: 0
  property var moduleSlots: []
  property var clickTargets: []
  property var layoutSessions: []
  property var tooltipTarget: null
  property string tooltipText: ""
  property var pendingTooltipTarget: null
  property string pendingTooltipText: ""
  property bool tooltipShown: false
  // Restore records are output-local. A V1/V2 owner handoff on one output
  // must not suppress or overwrite a value-only mutation on another output.
  property var pendingWidgetRestores: []
  property string controlCenterWidgetDetailGroup: ""
  property string controlCenterWidgetDetailPlugin: ""

  function normalizePosition(value) {
    const candidate = String(value || "").trim()
    return /^(top|bottom|left|right)$/.test(candidate) ? candidate : "top"
  }

  function captureSuiteMarker(raw) {
    suitePayloadDigest = ""
    suitePayloadLoaded = false
    try {
      const marker = JSON.parse(String(raw || ""))
      const digest = String(marker.suitePayloadDigest || "")
      if (marker.suiteId === "hancore.shibumi" && /^[0-9a-f]{64}$/.test(digest)) {
        suitePayloadDigest = digest
        suitePayloadLoaded = true
      }
    } catch (error) {}
  }

  function registeredWidgetComponent(widgetId) {
    return hostWidgetResolverService.componentFor(widgetId)
  }

  function registeredWidgetSource(widgetId) {
    return hostWidgetResolverService.entryPointUrl(widgetId)
  }

  function pluginService(pluginId) {
    const id = String(pluginId || "")
    return id && shell && typeof shell.serviceFor === "function"
      ? shell.serviceFor(id) : null
  }

  function setWidgetAppearance(groupId, key, valueJson) {
    const name = String(key || "")
    // The legacy endpoint only owns appearance shared by both variants.
    // Variant-scoped values must never report success after writing a
    // top-level fallback that the active renderer may ignore.
    if (name !== "separator") return "variant-required"
    const state = pluginService("hancore.shibumi.state")
    if (!state || typeof state.setGroupSetting !== "function")
      return "not-ready"
    let value = String(valueJson || "")
    try {
      value = JSON.parse(value)
    } catch (error) {
      return "invalid-value"
    }
    if (typeof value !== "boolean") return "invalid-value"
    return state.setGroupSetting(String(groupId || ""), name, value)
      ? "ok" : "rejected"
  }

  function setWidgetAppearanceForVariant(groupId, variantValue, key,
      valueJson) {
    const variant = String(variantValue || "").toLowerCase()
    if (["v1", "v2"].indexOf(variant) < 0) return "invalid-variant"
    const state = pluginService("hancore.shibumi.state")
    if (!state
        || typeof state.setGroupAppearanceSettingForVariant !== "function")
      return "not-ready"
    const name = String(key || "")
    if (Array.isArray(state.appearanceKeys)
        && state.appearanceKeys.indexOf(name) < 0) return "invalid-key"
    let value = String(valueJson || "")
    try {
      value = JSON.parse(value)
    } catch (error) {
      // Plain strings remain convenient for CLI callers.
    }
    return state.setGroupAppearanceSettingForVariant(
      String(groupId || ""), variant, name, value) ? "ok" : "rejected"
  }

  function inlineSettingsDelta(current, next) {
    if (!Util.isPlainObject(current) || !Util.isPlainObject(next)) return null
    const regions = ["left", "center", "right"]
    const counts = Object.create(null)
    for (let regionIndex = 0; regionIndex < regions.length; regionIndex++) {
      const entries = Array.isArray(next[regions[regionIndex]])
        ? next[regions[regionIndex]] : []
      for (let entryIndex = 0; entryIndex < entries.length; entryIndex++) {
        const id = entryId(entries[entryIndex])
        counts[id] = (counts[id] || 0) + 1
      }
    }

    const changes = []
    for (let regionIndex = 0; regionIndex < regions.length; regionIndex++) {
      const region = regions[regionIndex]
      const currentEntries = Array.isArray(current[region])
        ? current[region] : []
      const nextEntries = Array.isArray(next[region]) ? next[region] : []
      if (currentEntries.length !== nextEntries.length) return null
      for (let entryIndex = 0; entryIndex < currentEntries.length;
          entryIndex++) {
        const currentId = entryId(currentEntries[entryIndex])
        const nextId = entryId(nextEntries[entryIndex])
        if (currentId !== nextId) return null
        if (JSON.stringify(currentEntries[entryIndex])
            === JSON.stringify(nextEntries[entryIndex])) continue
        const currentEntry = Util.isPlainObject(currentEntries[entryIndex])
          ? currentEntries[entryIndex] : ({})
        const nextEntry = Util.isPlainObject(nextEntries[entryIndex])
          ? nextEntries[entryIndex] : ({})
        // These values determine slot ownership or Loader activation rather
        // than provider state. They require the structural reconciliation path.
        if ((currentEntry.shibumiModule === true)
              !== (nextEntry.shibumiModule === true)
            || (currentEntry.enabled !== false)
              !== (nextEntry.enabled !== false)) return null
        // Without stable per-entry identities, repeated providers cannot be
        // patched safely. Fall back to the normal structural rebuild.
        if (counts[nextId] > 1) return null
        changes.push({
          region: region,
          index: entryIndex,
          entry: nextEntries[entryIndex]
        })
      }
    }
    return changes
  }

  function applyInlineSettingsDelta(changes) {
    // Composite-consumed entries (clock, weather, tray, and similar) have no
    // same-ID WidgetSlot to invalidate. If any changed entry lacks a live slot,
    // use the structural path rather than leaving that consumer stale.
    for (let changeIndex = 0; changeIndex < changes.length; changeIndex++) {
      const id = entryId(changes[changeIndex].entry)
      let found = false
      for (let slotIndex = 0; slotIndex < moduleSlots.length; slotIndex++) {
        const slot = moduleSlots[slotIndex]
        if (slot && slot.moduleName === id
            && typeof slot.applyInlineSettings === "function") {
          found = true
          break
        }
      }
      if (!found) return false
    }

    for (let changeIndex = 0; changeIndex < changes.length; changeIndex++) {
      const change = changes[changeIndex]
      layoutConfig[change.region][change.index] = change.entry
      const id = entryId(change.entry)
      // One logical slot may be rendered on multiple outputs or as a
      // zero-size anchor placeholder. Patch every live copy in place so
      // state persistence cannot destroy an open third-party panel. Keep the
      // delegate-owned entry binding intact; later group updates still need it.
      for (let slotIndex = 0; slotIndex < moduleSlots.length; slotIndex++) {
        const slot = moduleSlots[slotIndex]
        if (slot && slot.moduleName === id
            && typeof slot.applyInlineSettings === "function")
          slot.applyInlineSettings(change.entry)
      }
    }
    return true
  }

  function applyBarConfig() {
    const config = Util.isPlainObject(barConfig) ? barConfig : fallbackBarConfig
    position = normalizePosition(config.position)
    requestedStyleId = String(config.style || "shibumi")
    centerAnchor = Util.canonicalWidgetId(config.centerAnchor || "")
    const nextLayout = Util.normalizeLayout(config.layout)
    // QML cannot diff reassigned JavaScript layout arrays: replacing one for
    // an inline setting (for example a saved game score) recreates every
    // widget and closes its panel. Match Omarchy's stock host by updating
    // shape-stable, uniquely identified entries and their live slots in place.
    const delta = inlineSettingsDelta(layoutConfig, nextLayout)
    if (delta !== null && applyInlineSettingsDelta(delta)) return
    for (let slotIndex = 0; slotIndex < moduleSlots.length; slotIndex++) {
      const slot = moduleSlots[slotIndex]
      if (slot && typeof slot.clearInlineSettings === "function")
        slot.clearInlineSettings()
    }
    layoutConfig = nextLayout
  }

  function setBarPosition(value, ownerValue, screenName) {
    const next = String(value || "")
    if (["top", "bottom"].indexOf(next) < 0 || !shell
        || typeof shell.mutateShellConfig !== "function") return false
    root.scheduleOpenControlCenterRestores(
      "bars", false, ownerValue, screenName)
    shell.mutateShellConfig(function(config) {
      if (!Util.isPlainObject(config.bar)) config.bar = {}
      config.bar.position = next
    })
    return true
  }

  function setAllSplits(value) {
    return typeof value === "boolean"
      ? layoutStateController.setAllSplits(value) : false
  }

  function toggleGroupSeparator(groupId, editingValue) {
    const state = pluginService("hancore.shibumi.state")
    return layoutStateController.v2Mode
      && layoutStateController.interactiveMutationAllowed(editingValue)
      && state && typeof state.toggleGroupSeparator === "function"
      ? state.toggleGroupSeparator(String(groupId || "")) : false
  }

  function resetBarLayout() {
    const reset = layoutStateController.resetLayout()
    if (reset && !layoutStateController.v2Mode)
      v1PluginReconcileTimer.restart()
    return reset
  }

  function addV2Slot(region) {
    return layoutStateController.addV2Slot(region)
  }

  function removeV2Slot(region) {
    return layoutStateController.removeV2Slot(region)
  }

  function addV1Slot(region) {
    return layoutStateController.addV1Slot(region)
  }

  function removeV1Slot(region) {
    return layoutStateController.removeV1Slot(region)
  }

  function widgetSettings(groupId, moduleId) {
    const state = pluginService("hancore.shibumi.state")
    const config = state && state.config ? state.config : ({})
    const group = config.widgets
      ? config.widgets[String(groupId || "")] || ({}) : ({})
    return GroupRegistry.childSettingsFor(group, layoutConfig,
      String(moduleId || ""))
  }

  function validateStyle(item) {
    if (!item) return false
    if (!("bar" in item) || Number(item.contractVersion) !== 1) return false
    if (String(item.styleId || "") !== styleRegistry.resolvedId) return false
    if (Number(item.sizeHorizontal) <= 0 || Number(item.sizeVertical) <= 0) return false
    if (Number(item.exclusiveSizeHorizontal) < Number(item.sizeHorizontal)) return false
    if (!item.visualTokens) return false
    if (!item.barSurfaceComponent || !item.tooltipSurfaceComponent) return false
    return true
  }

  function setStyle(value) {
    const next = styleRegistry.normalizeId(value)
    if (!styleRegistry.hasStyle(next)) return false

    if (shell && typeof shell.mutateShellConfig === "function") {
      shell.mutateShellConfig(function(config) {
        if (!Util.isPlainObject(config.bar)) config.bar = {}
        config.bar.style = next
      })
    } else {
      requestedStyleId = next
    }
    return true
  }

  function setRequestedTransparency(value) {
    // Compatibility no-op: Shibumi V1/V2 are always opaque and must neither
    // apply nor rewrite the stock Omarchy bar's saved preference.
    return false
  }

  function layoutEntries(region) {
    const entries = layoutConfig ? layoutConfig[region] : null
    return Array.isArray(entries) ? entries : []
  }

  function isV1AdditionalSuiteWidget(widgetId) {
    return [
      "hancore.shibumi.temperature",
      "hancore.shibumi.gpu",
      "hancore.shibumi.storage"
    ].indexOf(String(widgetId || "")) >= 0
  }

  function deduplicatedUnassignedEntries(entries) {
    const seen = ({})
    return entries.filter(function(entry) {
      const id = entryId(entry)
      if (widgetAllowsMultiple(id)) return true
      if (seen[id] === true) return false
      seen[id] = true
      return true
    })
  }

  function unassignedLayoutEntries(region) {
    const entries = GroupRegistry.unassignedEntries(layoutConfig, region)
    if (layoutStateController.v2Mode) {
      // G16-G18 use V1 extension slots but remain native fixed groups in V2.
      // Keep their persisted V1 provider entries out of V2's unassigned deck,
      // otherwise the same widget would be rendered twice after a switch.
      return deduplicatedUnassignedEntries(entries.filter(function(entry) {
        return !isV1AdditionalSuiteWidget(entryId(entry))
      }))
    }
    return deduplicatedUnassignedEntries(entries.filter(function(entry) {
      const groupId = GroupRegistry.dynamicGroupIdForModule(entryId(entry))
      return groupId === "" || !layoutStateController.groupLocation(groupId)
    }))
  }

  function v1PluginSpecsForLayout(layoutValue, excludeValue, includeSpec) {
    const excluded = Array.isArray(excludeValue)
      ? excludeValue.map(function(value) { return String(value || "") })
      : [String(excludeValue || "")]
    const source = Util.isPlainObject(layoutValue) ? layoutValue : ({})
    const specs = []
    const seen = ({})
    for (const region of ["left", "center", "right"]) {
      const entries = Array.isArray(source[region]) ? source[region] : []
      for (let index = 0; index < entries.length; index++) {
        const entry = entries[index]
        const id = entryId(entry)
        if (id === "" || excluded.indexOf(id) >= 0 || seen[id]
            || !Util.isPlainObject(entry)
            || entry.shibumiModule !== true
            || widgetAllowsMultiple(id)) continue
        seen[id] = true
        specs.push({ pluginId: id, region: region })
      }
    }
    if (includeSpec && Util.isPlainObject(includeSpec)) {
      const id = entryId(includeSpec)
      if (id !== "" && !seen[id] && !widgetAllowsMultiple(id))
        specs.push({
          pluginId: id,
          region: ["left", "center", "right"].indexOf(
            String(includeSpec.region || "")) >= 0
              ? String(includeSpec.region) : "right"
        })
    }
    return specs
  }

  function v1PluginSpecs(excludeValue, includeSpec) {
    return v1PluginSpecsForLayout(layoutConfig, excludeValue, includeSpec)
  }

  function reconcileV1PluginGroups() {
    if (!layoutStateController.reconcileV1PluginGroups(v1PluginSpecs()))
      return false
    return reconcileWidgetFamilyProviders()
  }

  function layoutContains(widgetId) {
    const id = String(widgetId || "")
    if (!id) return false
    for (const region of ["left", "center", "right"]) {
      const entries = layoutEntries(region)
      for (let index = 0; index < entries.length; index++) {
        if (entryId(entries[index]) !== id) continue
        const entry = entries[index]
        if (!GroupRegistry.isAssignedModule(id)
            || GroupRegistry.isOptionalModule(id)
            || (Util.isPlainObject(entry) && entry.shibumiModule === true))
          return true
      }
    }
    return false
  }

  function hasBarWidgetEntryPoint(widgetId) {
    const id = String(widgetId || "")
    const installed = pluginRegistry && pluginRegistry.installedPlugins
      ? pluginRegistry.installedPlugins : null
    const candidate = installed ? installed[id] : null
    if (!id || !candidate) return false
    if (pluginRegistry
        && typeof pluginRegistry.entryPointUrl === "function")
      return String(pluginRegistry.entryPointUrl(
        candidate, "barWidget") || "") !== ""
    const entryPoints = candidate.entryPoints
    return Util.isPlainObject(entryPoints)
      && String(entryPoints.barWidget || "") !== ""
  }

  function widgetAllowsMultiple(widgetId) {
    const id = String(widgetId || "")
    const installed = pluginRegistry && pluginRegistry.installedPlugins
      ? pluginRegistry.installedPlugins : null
    const candidate = installed ? installed[id] : null
    return !!(candidate && candidate.barWidget
      && candidate.barWidget.allowMultiple === true)
  }

  function widgetFamilyGroups(widgetId) {
    return WidgetFamilies.familiesForPlugin(
      String(widgetId || ""), pluginRegistry).map(function(family) {
        return String(family.group || "")
      }).filter(function(groupId, index, values) {
        return GroupRegistry.GroupIds.indexOf(groupId) >= 0
          && values.indexOf(groupId) === index
      })
  }

  function widgetCapabilities(widgetId) {
    return WidgetFamilies.capabilitiesForPlugin(
      String(widgetId || ""), pluginRegistry)
  }

  function widgetsShareCapability(leftId, rightId) {
    const left = widgetCapabilities(leftId)
    if (left.length === 0) return false
    const right = widgetCapabilities(rightId)
    return left.some(function(capability) {
      return right.indexOf(capability) >= 0
    })
  }

  function renderedProviderEntries(layoutValue, region) {
    return GroupRegistry.unassignedEntries(layoutValue, region)
  }

  function providerFamilyGroupsInLayout(layoutValue) {
    const groups = []
    for (const region of ["left", "center", "right"]) {
      const entries = renderedProviderEntries(layoutValue, region)
      for (let index = 0; index < entries.length; index++) {
        const familyGroups = widgetFamilyGroups(entryId(entries[index]))
        for (let groupIndex = 0; groupIndex < familyGroups.length;
             groupIndex++) {
          const group = familyGroups[groupIndex]
          if (groups.indexOf(group) < 0) groups.push(group)
        }
      }
    }
    return groups
  }

  function conflictingLayoutProviderIds(widgetId) {
    const id = String(widgetId || "")
    const result = id !== "" ? [id] : []
    for (const region of ["left", "center", "right"]) {
      const entries = renderedProviderEntries(layoutConfig, region)
      for (let index = 0; index < entries.length; index++) {
        const candidateId = entryId(entries[index])
        if (candidateId === "" || result.indexOf(candidateId) >= 0)
          continue
        if (widgetsShareCapability(id, candidateId)) result.push(candidateId)
      }
    }
    return result
  }

  function conflictingProviderIdsInLayout(layoutValue) {
    const capabilityOwners = ({})
    const removed = []
    for (const region of ["left", "center", "right"]) {
      const entries = renderedProviderEntries(layoutValue, region)
      for (let index = 0; index < entries.length; index++) {
        const id = entryId(entries[index])
        if (id === "" || removed.indexOf(id) >= 0) continue
        const capabilities = widgetCapabilities(id)
        const conflict = capabilities.some(function(capability) {
          return Object.prototype.hasOwnProperty.call(
            capabilityOwners, capability)
            && capabilityOwners[capability] !== id
        })
        if (conflict) {
          removed.push(id)
          continue
        }
        for (let capabilityIndex = 0;
             capabilityIndex < capabilities.length; capabilityIndex++)
          capabilityOwners[capabilities[capabilityIndex]] = id
      }
    }
    return removed
  }

  function conflictingLayoutProviderGroups(widgetId) {
    const id = String(widgetId || "")
    const providerIds = conflictingLayoutProviderIds(id)
    const groups = []
    for (let index = 0; index < providerIds.length; index++) {
      if (providerIds[index] === id) continue
      const providerGroups = widgetFamilyGroups(providerIds[index])
      for (let groupIndex = 0; groupIndex < providerGroups.length;
           groupIndex++) {
        const group = providerGroups[groupIndex]
        if (groups.indexOf(group) < 0) groups.push(group)
      }
    }
    return groups
  }

  function currentLayoutSnapshot() {
    return JSON.parse(JSON.stringify({
      left: layoutEntries("left"),
      center: layoutEntries("center"),
      right: layoutEntries("right")
    }))
  }

  function providerLayoutSnapshot(groupValues) {
    const groups = normalizedProviderGroups(groupValues)
    const states = groups.length > 0 ? widgetGroupVariantStates(groups) : ({})
    if (groups.length > 0 && !states) return null
    return {
      layout: currentLayoutSnapshot(),
      groupStates: states || ({})
    }
  }

  function restoreProviderLayoutSnapshot(snapshotValue) {
    if (!Util.isPlainObject(snapshotValue)
        || !Util.isPlainObject(snapshotValue.layout)
        || !Util.isPlainObject(snapshotValue.groupStates)) return false
    const layout = snapshotValue.layout
    for (const region of ["left", "center", "right"]) {
      if (!Array.isArray(layout[region])) return false
    }
    return applyProviderLayoutTransaction(
      JSON.parse(JSON.stringify(layout)),
      v1PluginSpecsForLayout(layout),
      JSON.parse(JSON.stringify(snapshotValue.groupStates)))
  }

  function layoutWithoutProviderIds(layoutValue, providerIds) {
    const source = Util.isPlainObject(layoutValue) ? layoutValue : ({})
    const ids = Array.isArray(providerIds) ? providerIds : []
    const result = { left: [], center: [], right: [] }
    for (const region of ["left", "center", "right"]) {
      const entries = Array.isArray(source[region]) ? source[region] : []
      result[region] = entries.filter(function(entry) {
        return ids.indexOf(entryId(entry)) < 0
      })
    }
    return result
  }

  function normalizedProviderGroups(groupValues) {
    const source = Array.isArray(groupValues) ? groupValues : []
    const result = []
    for (let index = 0; index < source.length; index++) {
      const group = String(source[index] || "")
      if (GroupRegistry.GroupIds.indexOf(group) >= 0
          && result.indexOf(group) < 0) result.push(group)
    }
    return result
  }

  function widgetGroupVariantStates(groupValues) {
    const groups = normalizedProviderGroups(groupValues)
    const stateService = shell && typeof shell.serviceFor === "function"
      ? shell.serviceFor("hancore.shibumi.state") : null
    if (groups.length === 0 || !stateService
        || typeof stateService.groupEnabledForVariant !== "function")
      return null
    const states = ({})
    for (let index = 0; index < groups.length; index++) {
      const group = groups[index]
      states[group] = {
        v1: stateService.groupEnabledForVariant(group, "v1"),
        v2: stateService.groupEnabledForVariant(group, "v2")
      }
    }
    return states
  }

  function setWidgetGroupVariantStates(stateValues) {
    if (!Util.isPlainObject(stateValues)) return false
    const sourceGroups = Object.keys(stateValues)
    const groups = normalizedProviderGroups(sourceGroups)
    if (groups.length === 0 || groups.length !== sourceGroups.length)
      return false
    for (let index = 0; index < groups.length; index++) {
      const states = stateValues[groups[index]]
      if (!Util.isPlainObject(states)
          || typeof states.v1 !== "boolean"
          || typeof states.v2 !== "boolean") return false
    }
    const stateService = shell && typeof shell.serviceFor === "function"
      ? shell.serviceFor("hancore.shibumi.state") : null
    if (!stateService) return false
    let called = false
    if (typeof stateService.setGroupVariantStates === "function") {
      called = true
      stateService.setGroupVariantStates(stateValues)
    } else if (typeof stateService.setGroupEnabledForVariant === "function") {
      called = true
      for (let index = 0; index < groups.length; index++) {
        const group = groups[index]
        stateService.setGroupEnabledForVariant(
          group, "v1", stateValues[group].v1)
        stateService.setGroupEnabledForVariant(
          group, "v2", stateValues[group].v2)
      }
    } else if (typeof stateService.setGroupSetting === "function") {
      called = true
      for (let index = 0; index < groups.length; index++) {
        const group = groups[index]
        stateService.setGroupSetting(
          group, "enabledV1", stateValues[group].v1)
        stateService.setGroupSetting(
          group, "enabledV2", stateValues[group].v2)
      }
    }
    if (!called) return false
    if (typeof stateService.groupEnabledForVariant !== "function") return true
    return groups.every(function(group) {
      return stateService.groupEnabledForVariant(group, "v1")
          === stateValues[group].v1
        && stateService.groupEnabledForVariant(group, "v2")
          === stateValues[group].v2
    })
  }

  function setWidgetGroupsEnabledForAllVariants(groupValues, enabled) {
    const groups = normalizedProviderGroups(groupValues)
    if (groups.length === 0 || typeof enabled !== "boolean") return false
    const states = ({})
    for (let index = 0; index < groups.length; index++)
      states[groups[index]] = { v1: enabled, v2: enabled }
    return setWidgetGroupVariantStates(states)
  }

  function reconcileWidgetFamilyProviders() {
    const currentLayout = currentLayoutSnapshot()
    const removedProviderIds = conflictingProviderIdsInLayout(currentLayout)
    const nextLayout = layoutWithoutProviderIds(
      currentLayout, removedProviderIds)
    const ownedGroups = providerFamilyGroupsInLayout(nextLayout)
    const displacedGroups = []
    for (let index = 0; index < removedProviderIds.length; index++) {
      const groups = widgetFamilyGroups(removedProviderIds[index])
      for (let groupIndex = 0; groupIndex < groups.length; groupIndex++) {
        if (displacedGroups.indexOf(groups[groupIndex]) < 0)
          displacedGroups.push(groups[groupIndex])
      }
    }
    const stateValues = ({})
    for (let index = 0; index < ownedGroups.length; index++)
      stateValues[ownedGroups[index]] = { v1: false, v2: false }
    for (let index = 0; index < displacedGroups.length; index++) {
      const group = displacedGroups[index]
      if (ownedGroups.indexOf(group) < 0)
        stateValues[group] = { v1: true, v2: true }
    }
    if (removedProviderIds.length > 0)
      return applyProviderLayoutTransaction(nextLayout,
        v1PluginSpecs(removedProviderIds), stateValues)
    const groups = Object.keys(stateValues)
    return groups.length === 0 || setWidgetGroupVariantStates(stateValues)
  }

  function setBarWidgetInstalled(widgetId, installed, region) {
    const id = String(widgetId || "")
    const targetRegion = WidgetFamilies.targetRegion(
      id, region, pluginRegistry)
    const familyGroups = widgetFamilyGroups(id)
    if (!id || !shell || typeof shell.mutateShellConfig !== "function")
      return false
    if (installed === true && !hasBarWidgetEntryPoint(id))
      return false

    const previousSpecs = v1PluginSpecs()
    const previousLayout = currentLayoutSnapshot()
    const replacedProviderIds = installed === true
      ? conflictingLayoutProviderIds(id) : [id]
    const displacedGroups = []
    for (let index = 0; index < replacedProviderIds.length; index++) {
      const replacedId = replacedProviderIds[index]
      if (replacedId === id) continue
      const groups = widgetFamilyGroups(replacedId)
      for (let groupIndex = 0; groupIndex < groups.length; groupIndex++) {
        if (displacedGroups.indexOf(groups[groupIndex]) < 0)
          displacedGroups.push(groups[groupIndex])
      }
    }
    const nextLayout = layoutWithoutProviderIds(
      previousLayout, replacedProviderIds)
    if (installed === true)
      nextLayout[targetRegion].push({ id: id, shibumiModule: true })
    else if (isV1AdditionalSuiteWidget(id))
      nextLayout[targetRegion].push({ id: id })
    const nextOwnedGroups = providerFamilyGroupsInLayout(nextLayout)
    const stateValues = ({})
    if (installed === true) {
      for (let index = 0; index < familyGroups.length; index++)
        stateValues[familyGroups[index]] = { v1: false, v2: false }
      for (let index = 0; index < displacedGroups.length; index++) {
        const group = displacedGroups[index]
        if (nextOwnedGroups.indexOf(group) < 0)
          stateValues[group] = { v1: true, v2: true }
      }
    }
    const stateGroups = Object.keys(stateValues)
    const stateService = stateGroups.length > 0 && shell
      && typeof shell.serviceFor === "function"
      ? shell.serviceFor("hancore.shibumi.state") : null
    const canSetFamilyState = stateService
      && (typeof stateService.setGroupVariantStates === "function"
        || typeof stateService.setGroupEnabledForVariant === "function"
        || typeof stateService.setGroupSetting === "function")
    const previousFamilyStates = stateGroups.length > 0
      ? widgetGroupVariantStates(stateGroups) : null
    const registryWasEnabled = pluginRegistry
      && typeof pluginRegistry.isEnabled === "function"
      ? pluginRegistry.isEnabled(id) : null
    const desiredSpecs = v1PluginSpecs(replacedProviderIds,
      installed === true ? { id: id, region: targetRegion } : null)
    if (!layoutStateController.reconcileV1PluginGroups(desiredSpecs))
      return false

    if (installed === true && pluginRegistry
        && typeof pluginRegistry.setEnabled === "function")
      pluginRegistry.setEnabled(id, true)
    shell.mutateShellConfig(function(config) {
      if (!Util.isPlainObject(config.bar)) config.bar = {}
      config.bar.layout = JSON.parse(JSON.stringify(nextLayout))
      // Test/minimal hosts may not expose the state-service mutation facade.
      // The live shell always uses that facade because it is authoritative and
      // prevents a stale config binding from restoring displaced providers.
      if (stateGroups.length > 0 && !canSetFamilyState) {
        if (!Util.isPlainObject(config.bar.shibumi))
          config.bar.shibumi = {}
        if (!Util.isPlainObject(config.bar.shibumi.widgets))
          config.bar.shibumi.widgets = {}
        for (let index = 0; index < stateGroups.length; index++) {
          const group = stateGroups[index]
          const currentGroup = Util.isPlainObject(
            config.bar.shibumi.widgets[group])
            ? config.bar.shibumi.widgets[group] : {}
          currentGroup.enabledV1 = stateValues[group].v1
          currentGroup.enabledV2 = stateValues[group].v2
          config.bar.shibumi.widgets[group] = currentGroup
        }
      }
    })
    // Persist the provider choice last. mutateShellConfig may publish its
    // snapshot asynchronously, so writing this state before the layout would
    // let that older snapshot re-enable the Shibumi provider.
    if (stateGroups.length > 0 && canSetFamilyState
        && !setWidgetGroupVariantStates(stateValues)) {
      shell.mutateShellConfig(function(config) {
        if (!Util.isPlainObject(config.bar)) config.bar = {}
        config.bar.layout = JSON.parse(JSON.stringify(previousLayout))
      })
      layoutStateController.reconcileV1PluginGroups(previousSpecs)
      if (registryWasEnabled === false && pluginRegistry
          && typeof pluginRegistry.setEnabled === "function")
        pluginRegistry.setEnabled(id, false)
      if (previousFamilyStates)
        setWidgetGroupVariantStates(previousFamilyStates)
      return false
    }
    return true
  }

  function applyProviderLayoutTransaction(nextLayout, desiredSpecs,
      stateValues) {
    if (!shell || typeof shell.mutateShellConfig !== "function") return false
    const previousSpecs = v1PluginSpecs()
    const previousLayout = currentLayoutSnapshot()
    const groups = Util.isPlainObject(stateValues)
      ? Object.keys(stateValues) : []
    const previousStates = groups.length > 0
      ? widgetGroupVariantStates(groups) : null
    if (!layoutStateController.reconcileV1PluginGroups(desiredSpecs))
      return false
    shell.mutateShellConfig(function(config) {
      if (!Util.isPlainObject(config.bar)) config.bar = {}
      config.bar.layout = JSON.parse(JSON.stringify(nextLayout))
    })
    if (groups.length === 0 || setWidgetGroupVariantStates(stateValues))
      return true
    shell.mutateShellConfig(function(config) {
      if (!Util.isPlainObject(config.bar)) config.bar = {}
      config.bar.layout = JSON.parse(JSON.stringify(previousLayout))
    })
    layoutStateController.reconcileV1PluginGroups(previousSpecs)
    if (previousStates) setWidgetGroupVariantStates(previousStates)
    return false
  }

  function widgetFamilyAlternativeIds(groupValues) {
    const groups = normalizedProviderGroups(groupValues)
    const result = []
    for (let index = 0; index < groups.length; index++) {
      const family = WidgetFamilies.familyForGroup(
        groups[index], pluginRegistry)
      if (!family) continue
      for (let alternativeIndex = 0;
           alternativeIndex < family.alternatives.length;
           alternativeIndex++) {
        const id = String(family.alternatives[alternativeIndex] || "")
        if (id !== "" && result.indexOf(id) < 0) result.push(id)
      }
    }
    return result
  }

  function widgetFamilyAlternativesInstalled(groupId) {
    const group = String(groupId || "")
    if (GroupRegistry.GroupIds.indexOf(group) < 0) return false
    for (const region of ["left", "center", "right"]) {
      const entries = renderedProviderEntries(layoutConfig, region)
      for (let index = 0; index < entries.length; index++) {
        if (widgetFamilyGroups(entryId(entries[index])).indexOf(group) >= 0)
          return true
      }
    }
    return false
  }

  function restoreWidgetFamilyProviderStates(stateValues) {
    if (!Util.isPlainObject(stateValues)) return false
    const groups = normalizedProviderGroups(Object.keys(stateValues))
    if (groups.length === 0
        || groups.length !== Object.keys(stateValues).length) return false
    const alternatives = widgetFamilyAlternativeIds(groups)
    const nextLayout = layoutWithoutProviderIds(
      currentLayoutSnapshot(), alternatives)
    const ownedGroups = providerFamilyGroupsInLayout(nextLayout)
    const effectiveStates = JSON.parse(JSON.stringify(stateValues))
    for (let index = 0; index < alternatives.length; index++) {
      const alternativeGroups = widgetFamilyGroups(alternatives[index])
      for (let groupIndex = 0; groupIndex < alternativeGroups.length;
           groupIndex++) {
        const group = alternativeGroups[groupIndex]
        if (ownedGroups.indexOf(group) < 0
            && !Object.prototype.hasOwnProperty.call(effectiveStates, group))
          effectiveStates[group] = { v1: true, v2: true }
      }
    }
    return applyProviderLayoutTransaction(
      nextLayout, v1PluginSpecs(alternatives), effectiveStates)
  }

  function restoreWidgetFamilyProviders(groupValues) {
    const groups = normalizedProviderGroups(groupValues)
    if (groups.length === 0) return false
    const states = ({})
    for (let index = 0; index < groups.length; index++)
      states[groups[index]] = { v1: true, v2: true }
    return restoreWidgetFamilyProviderStates(states)
  }

  function removeBarWidgetAndRestoreFamilies(widgetId, groupValues) {
    const id = String(widgetId || "")
    if (id === "") return false
    const groups = normalizedProviderGroups(groupValues)
    const nextLayout = layoutWithoutProviderIds(
      currentLayoutSnapshot(), [id])
    const states = ({})
    const ownedGroups = providerFamilyGroupsInLayout(nextLayout)
    for (let groupIndex = 0; groupIndex < groups.length; groupIndex++) {
      const group = groups[groupIndex]
      if (ownedGroups.indexOf(group) < 0)
        states[group] = { v1: true, v2: true }
    }
    return applyProviderLayoutTransaction(
      nextLayout, v1PluginSpecs([id]), states)
  }

  function removeWidgetFamilyAlternatives(groupId) {
    const family = WidgetFamilies.familyForGroup(groupId, pluginRegistry)
    if (!family || !shell || typeof shell.mutateShellConfig !== "function")
      return false
    let changed = false
    shell.mutateShellConfig(function(config) {
      if (!Util.isPlainObject(config.bar)
          || !Util.isPlainObject(config.bar.layout)) return
      for (const section of ["left", "center", "right"]) {
        const source = Array.isArray(config.bar.layout[section])
          ? config.bar.layout[section] : []
        const filtered = source.filter(function(entry) {
          const entryValue = Util.isPlainObject(entry) ? entry.id : entry
          return family.alternatives.indexOf(
            Util.canonicalWidgetId(entryValue || "")) < 0
        })
        if (filtered.length !== source.length) changed = true
        config.bar.layout[section] = filtered
      }
    })
    return changed
  }

  function widgetReplacementLabel(widgetId) {
    return WidgetFamilies.replacementLabel(widgetId, pluginRegistry)
  }

  function widgetReplacementGroups(widgetId) {
    return widgetFamilyGroups(widgetId)
  }

  function widgetReplacementGroup(widgetId) {
    const groups = widgetReplacementGroups(widgetId)
    return groups.length > 0 ? groups[0] : ""
  }

  function widgetReplacementTarget(widgetId) {
    return WidgetFamilies.joinedLabels(
      WidgetFamilies.replacementTargets(
        String(widgetId || ""), pluginRegistry))
  }

  function entryId(entry) {
    if (typeof entry === "string") return Util.canonicalWidgetId(entry)
    if (Util.isPlainObject(entry)) return Util.canonicalWidgetId(entry.id || "")
    return ""
  }

  function entrySettings(entry) {
    if (!Util.isPlainObject(entry)) return ({})
    const settings = ({})
    for (const key in entry) {
      if (key !== "id") settings[key] = entry[key]
    }
    return settings
  }

  function entryIndex(entries, id) {
    if (!Array.isArray(entries)) return -1
    for (let i = 0; i < entries.length; i++) {
      if (entryId(entries[i]) === id) return i
    }
    return -1
  }

  function run(command) {
    const text = String(command || "").trim()
    if (!text) return
    if (typeof Util.execDetached === "function") Util.execDetached(text)
    else Quickshell.execDetached(["bash", "-lc", text])
  }

  function resolvedPopoutScreenName(owner, screenName) {
    const explicitName = String(screenName || "").trim()
    if (explicitName) return explicitName
    if (owner && "popoutScreenName" in owner) {
      const ownerName = String(owner.popoutScreenName || "").trim()
      if (ownerName) return ownerName
    }
    const ownerWindow = owner && owner.QsWindow
      ? owner.QsWindow.window : null
    const ownerScreen = ownerWindow ? ownerWindow.screen : null
    return ownerScreen ? String(ownerScreen.name || "").trim() : ""
  }

  function popoutScreenKey(screenName) {
    const value = String(screenName || "").trim()
    return value || "__global__"
  }

  function activePopoutForScreen(screenName) {
    return activePopouts[popoutScreenKey(screenName)] || null
  }

  function remainingPopout(next) {
    let result = null
    for (const key in next) result = next[key]
    return result
  }

  function requestPopout(owner, screenName) {
    if (!owner) return
    const key = popoutScreenKey(resolvedPopoutScreenName(owner, screenName))
    const previous = activePopouts[key] || null
    if (previous === owner) {
      activePopout = owner
      return
    }
    const next = ({})
    for (const existingKey in activePopouts)
      next[existingKey] = activePopouts[existingKey]
    next[key] = owner
    activePopouts = next
    activePopout = owner
    if (!previous) return
    if (typeof previous.closeForPopoutSwitch === "function")
      previous.closeForPopoutSwitch()
    else if (typeof previous.close === "function") previous.close()
  }

  function releasePopout(owner, screenName) {
    if (!owner) return
    const resolvedScreenName = resolvedPopoutScreenName(owner, screenName)
    const constrained = resolvedScreenName !== ""
    const requestedKey = popoutScreenKey(resolvedScreenName)
    const next = ({})
    let removed = false
    for (const key in activePopouts) {
      if (activePopouts[key] === owner && (!constrained || key === requestedKey))
        removed = true
      else
        next[key] = activePopouts[key]
    }
    if (!removed) return
    activePopouts = next
    if (activePopout === owner) activePopout = remainingPopout(next)
  }

  function releasePopoutsForScreen(screenName) {
    const key = popoutScreenKey(screenName)
    const owner = activePopouts[key] || null
    if (!owner) return false
    const next = ({})
    for (const existingKey in activePopouts) {
      if (existingKey !== key) next[existingKey] = activePopouts[existingKey]
    }
    activePopouts = next
    if (activePopout === owner) activePopout = remainingPopout(next)
    clearConnectedPanel(owner)
    if (typeof owner.close === "function") owner.close()
    return true
  }

  function dismissActivePopout(screenName) {
    const constrained = String(screenName || "").trim() !== ""
    if (constrained) return releasePopoutsForScreen(screenName)
    const owners = []
    for (const key in activePopouts) {
      const owner = activePopouts[key]
      if (owner && owners.indexOf(owner) < 0) owners.push(owner)
    }
    if (owners.length === 0) return false
    activePopouts = ({})
    activePopout = null
    for (const owner of owners) {
      clearConnectedPanel(owner)
      if (typeof owner.close === "function") owner.close()
    }
    return true
  }

  onBarHiddenChanged: {
    if (barHidden) dismissActivePopout()
  }

  function emptyConnectedPanel() {
    return ({
      owner: null,
      screenName: "",
      x: 0,
      reveal: 0,
      hostCaret: false,
      cardX: 0,
      cardY: 0,
      cardWidth: 0,
      cardHeight: 0
    })
  }

  function connectedPanelForScreen(screenName) {
    return connectedPanels[popoutScreenKey(screenName)] || emptyConnectedPanel()
  }

  function syncConnectedPanelCompatibility(record) {
    const value = record || emptyConnectedPanel()
    connectedPanelOwner = value.owner || null
    connectedPanelScreenName = String(value.screenName || "")
    connectedPanelX = Number(value.x) || 0
    connectedPanelReveal = Number(value.reveal) || 0
    connectedPanelHostCaret = value.hostCaret === true
    connectedPanelCardX = Number(value.cardX) || 0
    connectedPanelCardY = Number(value.cardY) || 0
    connectedPanelCardWidth = Math.max(0, Number(value.cardWidth) || 0)
    connectedPanelCardHeight = Math.max(0, Number(value.cardHeight) || 0)
  }

  function remainingConnectedPanel(next) {
    let result = null
    for (const key in next) result = next[key]
    return result
  }

  function publishConnectedPanel(owner, screenName, resolvedX, reveal,
      options) {
    if (!owner) return false
    const name = String(screenName || "").trim()
    const progress = Math.max(0, Math.min(1, Number(reveal) || 0))
    const x = Number(resolvedX) || 0
    if (progress <= 0.001)
      return clearConnectedPanel(owner, name)
    if (x <= 0 || !name) return false
    const key = popoutScreenKey(name)
    const current = connectedPanels[key] || null
    if (current && current.owner !== owner
        && activePopoutForScreen(name) !== owner) return false
    const geometry = options && typeof options === "object" ? options : null
    const record = {
      owner: owner,
      screenName: name,
      x: x,
      reveal: progress,
      hostCaret: !!(geometry && geometry.hostCaret === true),
      cardX: geometry ? Number(geometry.cardX) || 0 : 0,
      cardY: geometry ? Number(geometry.cardY) || 0 : 0,
      cardWidth: geometry
        ? Math.max(0, Number(geometry.cardWidth) || 0) : 0,
      cardHeight: geometry
        ? Math.max(0, Number(geometry.cardHeight) || 0) : 0
    }
    const next = ({})
    for (const existingKey in connectedPanels)
      next[existingKey] = connectedPanels[existingKey]
    next[key] = record
    connectedPanels = next
    syncConnectedPanelCompatibility(record)
    return true
  }

  function clearConnectedPanel(owner, screenName) {
    const constrained = String(screenName || "").trim() !== ""
    const requestedKey = popoutScreenKey(screenName)
    const next = ({})
    let removed = false
    for (const key in connectedPanels) {
      const record = connectedPanels[key]
      if ((!owner || record.owner === owner)
          && (!constrained || key === requestedKey))
        removed = true
      else
        next[key] = record
    }
    if (!removed) return false
    connectedPanels = next
    if (!connectedPanelOwner || !owner || connectedPanelOwner === owner
        || constrained && connectedPanelScreenName === String(screenName))
      syncConnectedPanelCompatibility(remainingConnectedPanel(next))
    return true
  }

  function showTooltip(target, text) {
    const nextText = String(text || "")
    if (!target || !nextText) {
      hideTooltip(target)
      return
    }
    pendingTooltipTarget = target
    pendingTooltipText = nextText
    tooltipDelay.restart()
  }

  function hideTooltip(target) {
    if (target && target !== tooltipTarget && target !== pendingTooltipTarget) return
    tooltipDelay.stop()
    pendingTooltipTarget = null
    pendingTooltipText = ""
    tooltipTarget = null
    tooltipText = ""
    tooltipShown = false
  }

  function targetWindow(target) {
    return target && target.QsWindow ? target.QsWindow.window : null
  }

  function targetBelongsToWindow(target, window) {
    return !!target && !!window && targetWindow(target) === window
  }

  function registerModuleSlot(slot) {
    if (!slot || moduleSlots.indexOf(slot) !== -1) return
    const next = moduleSlots.slice()
    next.push(slot)
    moduleSlots = next
  }

  function unregisterModuleSlot(slot) {
    moduleSlots = moduleSlots.filter(item => item !== slot)
  }

  function registerClickTarget(target) {
    if (!target || clickTargets.indexOf(target) !== -1) return
    const next = clickTargets.slice()
    next.push(target)
    clickTargets = next
  }

  function unregisterClickTarget(target) {
    clickTargets = clickTargets.filter(item => item !== target)
  }

  function registerLayoutSession(session) {
    if (session && layoutSessions.indexOf(session) < 0)
      layoutSessions = layoutSessions.concat([session])
  }

  function unregisterLayoutSession(session) {
    layoutSessions = layoutSessions.filter(item => item !== session)
  }

  function setLayoutEditing(enabled, screenName) {
    const requested = String(screenName || "") || focusedOutputName()
    let changed = false
    for (let index = 0; index < layoutSessions.length; index++) {
      const session = layoutSessions[index]
      if (!session || (requested !== ""
          && String(session.screenName || "") !== requested)) continue
      if (typeof session.setEditing === "function")
        changed = session.setEditing(enabled === true) || changed
    }
    return changed
  }

  function panelSlotsFor(owner) {
    const ownerWindow = targetWindow(owner)
    return moduleSlots.filter(slot => {
      if (!slot || !slot.activeItem || !slot.visible) return false
      if (ownerWindow && targetWindow(slot.activeItem) !== ownerWindow) return false
      const item = slot.activeItem
      return typeof item.open === "function"
        && typeof item.close === "function"
        && item.opened !== undefined
    })
  }

  function switchPanelFrom(owner, direction) {
    const slots = panelSlotsFor(owner)
    if (slots.length < 2) return false
    const current = slots.findIndex(slot => slot.activeItem === owner)
    if (current < 0) return false
    const step = direction < 0 ? -1 : 1
    const next = slots[(current + step + slots.length) % slots.length]
    next.activeItem.open()
    return true
  }

  function focusedOutputName() {
    const monitor = Hyprland.focusedMonitor
    return monitor ? String(monitor.name || "") : ""
  }

  function findPanelWidget(pluginId, screenName) {
    const requested = String(screenName || "") || focusedOutputName()
    return PanelRouting.findPanelWidgetForScreen(moduleSlots, pluginId, requested)
  }

  function findPanelWidgetOnScreen(pluginId, screenName) {
    const id = String(pluginId || "")
    const requested = String(screenName || "")
    if (requested === "") return findPanelWidget(id)
    for (let index = 0; index < moduleSlots.length; index++) {
      const slot = moduleSlots[index]
      if (!slot || String(slot.screenName || "") !== requested) continue
      const panel = PanelRouting.panelForSlot(slot, id)
      if (panel) return panel
    }
    return null
  }

  function panelWidgets(pluginId) {
    return PanelRouting.panelWidgets(moduleSlots, pluginId)
  }

  function screenForName(value) {
    const requested = String(value || "")
    let fallback = null
    for (let i = 0; i < moduleSlots.length; i++) {
      const slot = moduleSlots[i]
      if (!slot || !slot.activeItem) continue
      const window = targetWindow(slot.activeItem)
      const candidate = window && window.screen ? window.screen : null
      if (!candidate || String(candidate.name || "") === "") continue
      if (!fallback) fallback = candidate
      if (requested !== "" && String(candidate.name || "") === requested)
        return candidate
    }
    return fallback
  }

  function summonBarWidget(pluginId, screenName) {
    const item = findPanelWidget(pluginId, screenName)
    if (!item) return false
    item.open()
    return true
  }

  function hideBarWidget(pluginId) {
    const items = panelWidgets(pluginId)
    if (items.length === 0) return false
    for (let i = 0; i < items.length; i++) {
      if (items[i].opened === true) items[i].close()
    }
    return true
  }

  function isBarWidgetOpen(pluginId) {
    const items = panelWidgets(pluginId)
    for (let i = 0; i < items.length; i++) {
      if (items[i].opened === true) return true
    }
    return false
  }

  function barWidgetPage(pluginId, fallbackPage) {
    const widget = findPanelWidget(pluginId)
    return widget && widget.panelLoaded === true && widget.panelItem
      && widget.panelItem.settingsPage !== undefined
      ? String(widget.panelItem.settingsPage || fallbackPage || "")
      : String(fallbackPage || "")
  }

  function scheduleOpenControlCenterRestores(page, needsReplacement,
      preferredOwner, preferredScreenName) {
    const id = "hancore.shibumi.control-center"
    const owners = panelWidgets(id).filter(function(owner) {
      return owner && owner.opened === true
    })
    if (preferredOwner && preferredOwner.opened === true
        && owners.indexOf(preferredOwner) < 0) owners.push(preferredOwner)
    const created = []
    for (let index = 0; index < owners.length; index++) {
      const owner = owners[index]
      const preferred = owner === preferredOwner
        ? String(preferredScreenName || "") : ""
      const screenName = restoreScreenName(owner, preferred)
      const alreadyPending = widgetRestorePendingForOutput(
        id, owner, screenName)
      const requestedPage = owner.panelLoaded === true && owner.panelItem
        ? String(owner.panelItem.settingsPage || page || "")
        : String(page || "")
      scheduleWidgetRestore(id, requestedPage, needsReplacement,
        owner, screenName)
      if (!alreadyPending) created.push({
        id: id, owner: owner, screenName: screenName
      })
    }
    return created
  }

  function cancelCreatedWidgetRestores(records) {
    const values = Array.isArray(records) ? records : []
    let changed = false
    for (let index = 0; index < values.length; index++) {
      const record = values[index]
      if (!record) continue
      changed = cancelWidgetRestore(
        record.id, record.owner, record.screenName) || changed
    }
    return changed
  }

  function openConfigPanel() {
    return summonBarWidget("hancore.shibumi.control-center")
  }

  function openConfigPage(page) {
    const widget = findPanelWidget("hancore.shibumi.control-center")
    return widget && typeof widget.openPage === "function"
      ? widget.openPage(String(page || "")) : false
  }

  function restoreScreenName(owner, screenName) {
    const explicit = String(screenName || "")
    if (explicit !== "") return explicit
    const window = targetWindow(owner)
    return window && window.screen ? String(window.screen.name || "") : ""
  }

  function widgetRestoreIndex(pluginId, owner, screenName) {
    const id = String(pluginId || "")
    const requestedScreen = restoreScreenName(owner, screenName)
    for (let index = 0; index < pendingWidgetRestores.length; index++) {
      const record = pendingWidgetRestores[index]
      if (record && record.id === id
          && String(record.screenName || "") === requestedScreen) return index
    }
    return -1
  }

  function widgetRestorePendingForOutput(pluginId, owner, screenName) {
    return widgetRestoreIndex(pluginId, owner, screenName) >= 0
  }

  function widgetRestorePendingForOwner(pluginId, owner, screenName) {
    const index = widgetRestoreIndex(pluginId, owner, screenName)
    if (index < 0) return false
    const record = pendingWidgetRestores[index]
    return record.owner === owner || record.activeOwner === owner
  }

  function scheduleWidgetRestore(pluginId, page, needsReplacement,
      ownerValue, screenName) {
    const id = String(pluginId || "")
    if (id === "") return false
    const owner = ownerValue || findPanelWidget(id, screenName)
    const outputName = restoreScreenName(owner, screenName)
    const index = widgetRestoreIndex(id, owner, outputName)
    const next = pendingWidgetRestores.slice()
    if (index >= 0) {
      const current = next[index]
      next[index] = {
        id: id,
        page: String(page || current.page || ""),
        attempts: Number(current.attempts || 0),
        owner: current.owner || owner,
        activeOwner: current.activeOwner || null,
        needsReplacement: current.needsReplacement === true
          || needsReplacement === true,
        screenName: outputName
      }
    } else {
      next.push({
        id: id,
        page: String(page || ""),
        attempts: 0,
        owner: owner,
        activeOwner: null,
        needsReplacement: needsReplacement === true,
        screenName: outputName
      })
    }
    pendingWidgetRestores = next
    if (!widgetRestoreTimer.running) widgetRestoreTimer.start()
    return true
  }

  function removeWidgetRestoreAt(index) {
    if (index < 0 || index >= pendingWidgetRestores.length) return false
    const next = pendingWidgetRestores.slice()
    next.splice(index, 1)
    pendingWidgetRestores = next
    if (next.length === 0) widgetRestoreTimer.stop()
    return true
  }

  function trackWidgetRestorePage(pluginId, page, ownerValue, screenName) {
    const id = String(pluginId || "")
    const requestedPage = String(page || "")
    const owner = ownerValue || findPanelWidget(id, screenName)
    const index = widgetRestoreIndex(id, owner, screenName)
    if (id === "" || requestedPage === "" || index < 0) return false
    const next = pendingWidgetRestores.slice()
    const record = next[index]
    // Navigation issued while the layout is rebuilding is newer than the
    // page captured at mutation time. Preserve that intent even when the
    // click still lands on the outgoing owner.
    record.page = requestedPage
    next[index] = record
    pendingWidgetRestores = next
    return true
  }

  function cancelWidgetRestore(pluginId, ownerValue, screenName) {
    const id = String(pluginId || "")
    const owner = ownerValue || findPanelWidget(id, screenName)
    return removeWidgetRestoreAt(widgetRestoreIndex(id, owner, screenName))
  }

  function trackControlCenterWidgetDetail(groupId, pluginId) {
    const group = String(groupId || "")
    if (group === "") return false
    controlCenterWidgetDetailGroup = group
    controlCenterWidgetDetailPlugin = String(pluginId || "")
    return true
  }

  function clearControlCenterWidgetDetail() {
    controlCenterWidgetDetailGroup = ""
    controlCenterWidgetDetailPlugin = ""
    return true
  }

  function widgetRestoreSatisfied(record, widget) {
    if (!record || !widget || widget.opened !== true) return false
    // A V1/V2 change replaces the WidgetSlot owner. The outgoing owner can
    // remain alive long enough to satisfy an early timer tick, then disappear
    // after the restore has already stopped. Only the replacement owner may
    // complete a variant-switch restore.
    if (record.needsReplacement && widget === record.owner) return false
    // Once the replacement owner is established, navigation belongs to the
    // user. Follow its current page instead of forcing the page captured at
    // switch time; if this owner is replaced again, that latest page becomes
    // the handoff target for its successor.
    if (widget === record.activeOwner) {
      if (record.id === "hancore.shibumi.control-center"
          && widget.panelLoaded === true && widget.panelItem) {
        const currentPage = String(widget.panelItem.settingsPage || "")
        if (currentPage !== "") record.page = currentPage
      }
      return true
    }
    if (record.id !== "hancore.shibumi.control-center"
        || String(record.page || "") === "") {
      record.activeOwner = widget
      return true
    }
    const pageReady = widget.panelLoaded === true && widget.panelItem
      && String(widget.panelItem.settingsPage || "") === record.page
    if (pageReady) record.activeOwner = widget
    return pageReady
  }

  Timer {
    id: widgetRestoreTimer
    interval: 80
    repeat: true

    onTriggered: {
      const next = []
      const records = root.pendingWidgetRestores.slice()
      for (let index = 0; index < records.length; index++) {
        const record = records[index]
        record.attempts = Number(record.attempts || 0) + 1
        // Never let a missing replacement owner fall back to another output.
        const widget = root.findPanelWidgetOnScreen(
          record.id, record.screenName)
        const satisfied = root.widgetRestoreSatisfied(record, widget)
        if (!satisfied && record.id
            === "hancore.shibumi.control-center"
            && String(record.page || "") !== "") {
          if (widget && typeof widget.openPage === "function")
            widget.openPage(record.page)
        } else if (!satisfied) {
          root.summonBarWidget(record.id, record.screenName)
        }
        // Filesystem-backed config publication and the layout delegate rebuild
        // can replace the panel owner more than once. Keep each output-local
        // handoff alive for its full 1.6 s window.
        if (record.attempts < 20) next.push(record)
      }
      root.pendingWidgetRestores = next
      if (next.length === 0) stop()
    }
  }

  function debugBarGeometry() {
    const geometry = []
    const focused = focusedOutputName()
    for (let i = 0; i < moduleSlots.length; i++) {
      const slot = moduleSlots[i]
      if (!slot || !slot.activeItem) continue
      let point = { x: slot.x, y: slot.y }
      try { point = slot.mapToItem(null, 0, 0) } catch (error) {}
      const window = targetWindow(slot.activeItem)
      let groupSection = slot
      for (let depth = 0; groupSection && depth < 16; depth++) {
        if ("separatorGeometry" in groupSection
            && "groupGeometry" in groupSection
            && "separatorHitTargetCount" in groupSection) break
        groupSection = groupSection.parent || null
      }
      let groupLayout = ({})
      if (groupSection && "separatorHitTargetCount" in groupSection) {
        let sectionPoint = { x: 0, y: 0 }
        try { sectionPoint = groupSection.mapToItem(null, 0, 0) }
        catch (error) {}
        groupLayout = {
          region: String(groupSection.region || ""),
          x: Math.round(sectionPoint.x),
          y: Math.round(sectionPoint.y),
          width: Math.round(Number(groupSection.width) || 0),
          height: Math.round(Number(groupSection.height) || 0),
          hitTargets: Number(groupSection.separatorHitTargetCount) || 0,
          groups: (groupSection.groupGeometry || []).map(function(entry) {
            return {
              groupId: String(entry.groupId || ""),
              index: Number(entry.index),
              left: Math.round(sectionPoint.x + Number(entry.left || 0)),
              right: Math.round(sectionPoint.x + Number(entry.right || 0))
            }
          }),
          separators: (groupSection.separatorGeometry || []).map(
            function(entry) {
              const center = sectionPoint.x + Number(entry.markerCenter || 0)
              return {
                groupId: String(entry.groupId || ""),
                index: Number(entry.index),
                center: Math.round(center),
                hitLeft: Math.round(center - 7),
                hitRight: Math.round(center + 7)
              }
            })
        }
      }
      geometry.push({
        id: slot.moduleName,
        section: slot.region,
        screen: window && window.screen ? window.screen.name : "",
        slotScreen: String(slot.screenName || ""),
        focusedScreen: focused,
        selectedForFocus: findPanelWidget(slot.moduleName, focused)
          === slot.activeItem,
        windowWidth: window ? Math.round(Number(window.width) || 0) : 0,
        surfaceWidth: window && "surfaceWidth" in window
          ? Math.round(Number(window.surfaceWidth) || 0) : 0,
        responsiveStage: window && "responsiveStage" in window
          ? Number(window.responsiveStage) || 0 : 0,
        responsiveProbe: window && "responsiveProbe" in window
          ? window.responsiveProbe : ({}),
        x: Math.round(point.x),
        y: Math.round(point.y),
        width: Math.round(slot.width),
        height: Math.round(slot.height),
        visible: slot.visible === true && slot.width > 0 && slot.height > 0,
        opened: slot.activeItem.opened === true,
        panelLoaded: slot.activeItem.panelLoaded === true,
        groupLayout: groupLayout
      })
    }
    return geometry
  }

  onBarConfigChanged: {
    applyBarConfig()
  }
  onLayoutConfigChanged: v1PluginReconcileTimer.restart()
  onInjectionCompleteChanged: {
    if (injectionComplete) {
      hostReadyDelay.restart()
      v1PluginReconcileTimer.restart()
    } else {
      hostReadyDelay.stop()
      hostReady = false
    }
  }
  Component.onCompleted: {
    applyBarConfig()
    v1PluginReconcileTimer.restart()
  }

  Timer {
    id: v1PluginReconcileTimer
    interval: 1
    repeat: false
    onTriggered: root.reconcileV1PluginGroups()
  }

  Connections {
    target: root.pluginRegistry
    ignoreUnknownSignals: true

    function onPluginsChanged() {
      v1PluginReconcileTimer.restart()
    }
  }

  Behavior on barForeground {
    enabled: root.foregroundAnimationEnabled
    ColorAnimation {
      duration: root.styleReady ? root.activeStyle.colorTransitionDuration : 160
      easing.type: Easing.OutCubic
    }
  }

  Behavior on background {
    ColorAnimation {
      duration: root.styleReady ? root.activeStyle.colorTransitionDuration : 160
      easing.type: Easing.OutCubic
    }
  }

  Styles.StyleRegistry {
    id: styleRegistry
    requestedId: root.requestedStyleId
  }

  Services.HostWidgetResolver {
    id: hostWidgetResolverService
    bar: root
  }

  Core.LayoutController {
    id: layoutStateController
    bar: root
    stateService: root.pluginService("hancore.shibumi.state")
  }

  Loader {
    id: styleLoader

    active: true
    visible: false
    source: styleRegistry.source

    onSourceChanged: root.styleReady = false
    onLoaded: {
      if (item && "bar" in item) item.bar = root
      root.styleReady = root.validateStyle(item)
      if (!root.styleReady)
        console.warn("Shibumi rejected invalid bar style:", styleRegistry.resolvedId)
      else if (styleRegistry.fallbackUsed)
        console.warn("Shibumi unknown bar style; using shibumi:", root.requestedStyleId)
    }
    onStatusChanged: {
      if (status === Loader.Error) {
        root.styleReady = false
        console.warn("Shibumi could not load bar style:", styleRegistry.resolvedId)
      }
    }
  }

  IpcHandler {
    target: "shibumi-suite"

    function openControlCenter(): string {
      return root.openConfigPanel() ? "ok" : "not-ready"
    }

    function closeControlCenter(): string {
      return root.hideBarWidget("hancore.shibumi.control-center")
        ? "ok" : "not-ready"
    }

    function openWidgetPanel(pluginId: string, screenName: string): string {
      return root.summonBarWidget(String(pluginId || ""), screenName)
        ? "ok" : "not-ready"
    }

    function closeWidgetPanel(pluginId: string): string {
      return root.hideBarWidget(String(pluginId || ""))
        ? "ok" : "not-ready"
    }

    function openStatusTray(screenName: string): string {
      const widget = root.findPanelWidget(
        "hancore.shibumi.status", String(screenName || ""))
      return widget && typeof widget.openTrayDrawer === "function"
          && widget.openTrayDrawer()
        ? "ok" : "not-ready"
    }

    function openStatusNotifications(screenName: string): string {
      const widget = root.findPanelWidget(
        "hancore.shibumi.status", String(screenName || ""))
      return widget && typeof widget.open === "function" && widget.open()
        ? "ok" : "not-ready"
    }

    function connectedPanelState(): string {
      return JSON.stringify({
        active: root.connectedPanelOwner !== null
          && root.connectedPanelReveal > 0.001,
        screen: root.connectedPanelScreenName,
        x: Math.round(root.connectedPanelX * 100) / 100,
        reveal: Math.round(root.connectedPanelReveal * 1000) / 1000
      })
    }

    function openControlCenterPage(page: string): string {
      return root.openConfigPage(page) ? "ok" : "not-ready"
    }

    function setWidgetModule(widgetId: string, enabled: string): string {
      const value = String(enabled || "").toLowerCase()
      if (value !== "true" && value !== "false") return "invalid-enabled"
      return root.setBarWidgetInstalled(widgetId, value === "true", "right")
        ? "ok" : "rejected"
    }

    function setWidgetAppearance(groupId: string, key: string,
        valueJson: string): string {
      return root.setWidgetAppearance(groupId, key, valueJson)
    }

    function setWidgetAppearanceForVariant(groupId: string, variant: string,
        key: string, valueJson: string): string {
      return root.setWidgetAppearanceForVariant(
        groupId, variant, key, valueJson)
    }

    function setBarAppearance(key: string, valueJson: string): string {
      const name = String(key || "")
      const allowed = [
        "accent", "border", "panelBorder", "frost", "shadow",
        "radius", "shellStyle"
      ]
      if (allowed.indexOf(name) < 0) return "invalid-key"
      const state = root.pluginService("hancore.shibumi.state")
      if (!state || typeof state.setPresentationSetting !== "function")
        return "not-ready"
      let value = String(valueJson || "")
      try {
        value = JSON.parse(value)
      } catch (error) {
        // Plain strings remain convenient for CLI callers.
      }
      const scheduled = root.scheduleOpenControlCenterRestores(
        "bars", name === "shellStyle", null, "")
      const changed = state.setPresentationSetting(name, value)
      if (!changed) root.cancelCreatedWidgetRestores(scheduled)
      return changed ? "ok" : "rejected"
    }

    function setBarEditing(enabled: string, screenName: string): string {
      const value = String(enabled || "").toLowerCase()
      if (value !== "true" && value !== "false") return "invalid-enabled"
      return root.setLayoutEditing(value === "true", screenName)
        ? "ok" : "unchanged"
    }

    function addV1Slot(region: string): string {
      if (layoutStateController.v2Mode) return "wrong-style"
      return root.addV1Slot(String(region || "")) ? "ok" : "rejected"
    }

    function removeV1Slot(region: string): string {
      if (layoutStateController.v2Mode) return "wrong-style"
      return root.removeV1Slot(String(region || "")) ? "ok" : "rejected"
    }

    function moveV1GroupToSlot(groupId: string, region: string,
        index: string): string {
      if (layoutStateController.v2Mode) return "wrong-style"
      const targetIndex = Number(index)
      if (!Number.isInteger(targetIndex)) return "invalid-index"
      return layoutStateController.moveGroupToSlot(
          String(groupId || ""), String(region || ""), targetIndex)
        ? "ok" : "rejected"
    }

    function setAllSplits(enabled: string): string {
      const value = String(enabled || "").toLowerCase()
      if (value !== "true" && value !== "false") return "invalid-enabled"
      return root.setAllSplits(value === "true") ? "ok" : "rejected"
    }

    function setShellStyle(style: string): string {
      const value = String(style || "")
      const state = root.pluginService("hancore.shibumi.state")
      const scheduled = root.scheduleOpenControlCenterRestores(
        "bars", true, null, "")
      const changed = state
        && typeof state.setPresentationSetting === "function"
        && state.setPresentationSetting("shellStyle", value)
      if (!changed) root.cancelCreatedWidgetRestores(scheduled)
      return changed ? "ok" : "rejected"
    }

    function setBarPosition(position: string): string {
      return root.setBarPosition(String(position || ""))
        ? "ok" : "rejected"
    }

    function verifyPayload(expectedDigest: string): string {
      const expected = String(expectedDigest || "")
      return root.hostReady
          && root.styleReady
          && root.suitePayloadLoaded
          && expected.length === 64
          && expected === root.suitePayloadDigest
        ? "ok" : "not-ready"
    }

    function reloadPayload(): string {
      // Quattro's plugin rescan can recreate a Loader from a still-cached QML
      // component when its URL did not change. Reload the shell configuration
      // after the transactional payload swap so the accepted code is the code
      // currently executing, not merely the files currently on disk.
      Qt.callLater(function() { Quickshell.reload(false) })
      return "ok"
    }
  }


  FileView {
    id: suiteMarker
    path: root.pluginSourceDir !== ""
      ? root.pluginSourceDir + "/.shibumi-managed.json" : ""
    watchChanges: false
    printErrors: false
    onLoaded: root.captureSuiteMarker(text())
    onLoadFailed: {
      root.suitePayloadDigest = ""
      root.suitePayloadLoaded = false
    }
  }

  Process {
    id: barHiddenProbe
    running: root.hostReady
    command: ["bash", "-lc", "[[ -f $HOME/.local/state/omarchy/toggles/bar-off ]] && echo yes || echo no"]
    stdout: SplitParser {
      onRead: line => {
        root.barToggledOff = String(line).trim() === "yes"
        root.barToggleStateLoaded = true
      }
    }
  }

  FileView {
    path: root.hostReady ? root.home + "/.local/state/omarchy/toggles" : ""
    watchChanges: true
    printErrors: false
    onFileChanged: barHiddenProbe.running = true
  }

  Timer {
    id: tooltipDelay
    interval: 350
    onTriggered: {
      root.tooltipTarget = root.pendingTooltipTarget
      root.tooltipText = root.pendingTooltipText
      root.tooltipShown = root.tooltipTarget !== null && root.tooltipText !== ""
    }
  }

  Timer {
    id: hostReadyDelay
    interval: 0
    onTriggered: root.hostReady = root.injectionComplete
  }

  Variants {
    // Keep the host-native screen model so Variants receives output lifecycle
    // changes directly. BarPanel rejects incomplete placeholder screens.
    model: root.outputWindowsEnabled ? Quickshell.screens : []

    delegate: Component {
      Core.BarPanel {
        required property var modelData
        bar: root
        screen: modelData
      }
    }
  }
}
