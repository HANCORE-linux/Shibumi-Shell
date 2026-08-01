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
    transparent: false,
    style: "shibumi",
    centerAnchor: "omarchy.clock",
    layout: { left: [], center: [], right: [] }
  })
  property var layoutConfig: fallbackBarConfig.layout
  property string centerAnchor: ""
  property string position: "top"
  property bool requestedTransparent: false
  property bool transparent: false
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

  property var activePopout: null
  // V2 panels and the active bar edge share one animated connection contract.
  // Only one popout can be active, so a single owner-scoped geometry record is
  // sufficient and avoids stale per-screen anchors after hotplug/reload.
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
  property string pendingWidgetRestoreId: ""
  property string pendingWidgetRestorePage: ""
  property int pendingWidgetRestoreAttempts: 0

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

  function applyBarConfig() {
    const config = Util.isPlainObject(barConfig) ? barConfig : fallbackBarConfig
    position = normalizePosition(config.position)
    setRequestedTransparency(config.transparent === true)
    requestedStyleId = String(config.style || "shibumi")
    centerAnchor = Util.canonicalWidgetId(config.centerAnchor || "")
    const nextLayout = Util.normalizeLayout(config.layout)
    if (JSON.stringify(layoutConfig) !== JSON.stringify(nextLayout))
      layoutConfig = nextLayout
  }

  function setBarPosition(value) {
    const next = String(value || "")
    if (["top", "bottom"].indexOf(next) < 0 || !shell
        || typeof shell.mutateShellConfig !== "function") return false
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

  function toggleGroupSeparator(groupId) {
    const state = pluginService("hancore.shibumi.state")
    return layoutStateController.v2Mode && state
      && typeof state.toggleGroupSeparator === "function"
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
    requestedTransparent = value === true
    transparent = requestedTransparent
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

  function unassignedLayoutEntries(region) {
    const entries = GroupRegistry.unassignedEntries(layoutConfig, region)
    if (layoutStateController.v2Mode) {
      // G16-G18 use V1 extension slots but remain native fixed groups in V2.
      // Keep their persisted V1 provider entries out of V2's unassigned deck,
      // otherwise the same widget would be rendered twice after a switch.
      return entries.filter(function(entry) {
        return !isV1AdditionalSuiteWidget(entryId(entry))
      })
    }
    return entries.filter(function(entry) {
      const groupId = GroupRegistry.dynamicGroupIdForModule(entryId(entry))
      return groupId === "" || !layoutStateController.groupLocation(groupId)
    })
  }

  function v1PluginSpecs(excludeId, includeSpec) {
    const excluded = String(excludeId || "")
    const specs = []
    const seen = ({})
    for (const region of ["left", "center", "right"]) {
      const entries = layoutEntries(region)
      for (let index = 0; index < entries.length; index++) {
        const entry = entries[index]
        const id = entryId(entry)
        if (id === "" || id === excluded || seen[id]
            || !Util.isPlainObject(entry)
            || entry.shibumiModule !== true) continue
        seen[id] = true
        specs.push({ pluginId: id, region: region })
      }
    }
    if (includeSpec && Util.isPlainObject(includeSpec)) {
      const id = entryId(includeSpec)
      if (id !== "" && !seen[id])
        specs.push({
          pluginId: id,
          region: ["left", "center", "right"].indexOf(
            String(includeSpec.region || "")) >= 0
              ? String(includeSpec.region) : "right"
        })
    }
    return specs
  }

  function reconcileV1PluginGroups() {
    return layoutStateController.reconcileV1PluginGroups(v1PluginSpecs())
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

  function setBarWidgetInstalled(widgetId, installed, region) {
    const id = String(widgetId || "")
    const targetRegion = WidgetFamilies.targetRegion(
      id, region, pluginRegistry)
    const family = WidgetFamilies.familyForPlugin(id, pluginRegistry)
    const stateService = family && shell
      && typeof shell.serviceFor === "function"
      ? shell.serviceFor("hancore.shibumi.state") : null
    const canSetFamilyState = stateService
      && typeof stateService.setGroupSetting === "function"
    const activeVariant = layoutStateController.v2Mode ? "v2" : "v1"
    if (!id || !shell || typeof shell.mutateShellConfig !== "function")
      return false
    if (installed === true && !hasBarWidgetEntryPoint(id))
      return false

    const desiredSpecs = v1PluginSpecs(id, installed === true
      ? { id: id, region: targetRegion } : null)
    if (!layoutStateController.reconcileV1PluginGroups(desiredSpecs))
      return false

    if (installed === true && pluginRegistry
        && typeof pluginRegistry.setEnabled === "function")
      pluginRegistry.setEnabled(id, true)
    shell.mutateShellConfig(function(config) {
      if (!Util.isPlainObject(config.bar)) config.bar = {}
      if (!Util.isPlainObject(config.bar.layout))
        config.bar.layout = { left: [], center: [], right: [] }
      // Test/minimal hosts may not expose the state-service mutation facade.
      // The live shell always uses that facade above because it is the
      // authoritative owner and prevents a stale config binding from
      // restoring the replaced Shibumi group.
      if (installed === true && family && !canSetFamilyState) {
        if (!Util.isPlainObject(config.bar.shibumi))
          config.bar.shibumi = {}
        if (!Util.isPlainObject(config.bar.shibumi.widgets))
          config.bar.shibumi.widgets = {}
        const currentGroup = Util.isPlainObject(
          config.bar.shibumi.widgets[family.group])
          ? config.bar.shibumi.widgets[family.group] : {}
        currentGroup[activeVariant === "v2" ? "enabledV2" : "enabledV1"]
          = false
        config.bar.shibumi.widgets[family.group] = currentGroup
      }
      for (const section of ["left", "center", "right"]) {
        const source = Array.isArray(config.bar.layout[section])
          ? config.bar.layout[section] : []
        config.bar.layout[section] = source.filter(function(entry) {
          const entryValue = Util.isPlainObject(entry) ? entry.id : entry
          return Util.canonicalWidgetId(entryValue || "") !== id
        })
      }
      if (installed === true)
        config.bar.layout[targetRegion].push({
          id: id,
          shibumiModule: true
        })
      else if (isV1AdditionalSuiteWidget(id))
        config.bar.layout[targetRegion].push({ id: id })
    })
    // Persist the provider choice last. mutateShellConfig may publish its
    // snapshot asynchronously, so writing this state before the layout would
    // let that older snapshot re-enable the Shibumi provider.
    if (installed === true && family && canSetFamilyState) {
      if (typeof stateService.setGroupEnabledForVariant === "function")
        stateService.setGroupEnabledForVariant(
          family.group, activeVariant, false)
      else stateService.setGroupSetting(family.group, "enabled", false)
    }
    return true
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

  function widgetReplacementGroup(widgetId) {
    const family = WidgetFamilies.familyForPlugin(
      String(widgetId || ""), pluginRegistry)
    return family ? String(family.group || "") : ""
  }

  function widgetReplacementTarget(widgetId) {
    const family = WidgetFamilies.familyForPlugin(
      String(widgetId || ""), pluginRegistry)
    return family ? String(family.shibumi || "") : ""
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

  function requestPopout(owner) {
    if (!owner || activePopout === owner) return
    const previous = activePopout
    activePopout = owner
    if (!previous) return
    if (typeof previous.closeForPopoutSwitch === "function") previous.closeForPopoutSwitch()
    else if (typeof previous.close === "function") previous.close()
  }

  function releasePopout(owner) {
    if (activePopout === owner) activePopout = null
  }

  function dismissActivePopout() {
    const owner = activePopout
    if (!owner) return false
    activePopout = null
    clearConnectedPanel(owner)
    if (typeof owner.close === "function") owner.close()
    return true
  }

  onBarHiddenChanged: {
    if (barHidden) dismissActivePopout()
  }

  function publishConnectedPanel(owner, screenName, resolvedX, reveal,
      options) {
    if (!owner) return false
    const progress = Math.max(0, Math.min(1, Number(reveal) || 0))
    const x = Number(resolvedX) || 0
    if (progress <= 0.001) {
      if (connectedPanelOwner !== owner) return false
      connectedPanelOwner = null
      connectedPanelScreenName = ""
      connectedPanelX = 0
      connectedPanelReveal = 0
      connectedPanelHostCaret = false
      connectedPanelCardX = 0
      connectedPanelCardY = 0
      connectedPanelCardWidth = 0
      connectedPanelCardHeight = 0
      return true
    }
    if (x <= 0 || String(screenName || "") === "") return false
    if (connectedPanelOwner && connectedPanelOwner !== owner
        && activePopout !== owner) return false
    connectedPanelOwner = owner
    connectedPanelScreenName = String(screenName)
    connectedPanelX = x
    connectedPanelReveal = progress
    const geometry = options && typeof options === "object" ? options : null
    connectedPanelHostCaret = !!(geometry && geometry.hostCaret === true)
    connectedPanelCardX = geometry ? Number(geometry.cardX) || 0 : 0
    connectedPanelCardY = geometry ? Number(geometry.cardY) || 0 : 0
    connectedPanelCardWidth = geometry
      ? Math.max(0, Number(geometry.cardWidth) || 0) : 0
    connectedPanelCardHeight = geometry
      ? Math.max(0, Number(geometry.cardHeight) || 0) : 0
    return true
  }

  function clearConnectedPanel(owner) {
    if (owner && connectedPanelOwner !== owner) return false
    connectedPanelOwner = null
    connectedPanelScreenName = ""
    connectedPanelX = 0
    connectedPanelReveal = 0
    connectedPanelHostCaret = false
    connectedPanelCardX = 0
    connectedPanelCardY = 0
    connectedPanelCardWidth = 0
    connectedPanelCardHeight = 0
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

  function openConfigPanel() {
    return summonBarWidget("hancore.shibumi.control-center")
  }

  function openConfigPage(page) {
    const widget = findPanelWidget("hancore.shibumi.control-center")
    return widget && typeof widget.openPage === "function"
      ? widget.openPage(String(page || "")) : false
  }

  function scheduleWidgetRestore(pluginId, page) {
    const id = String(pluginId || "")
    if (id === "") return false
    pendingWidgetRestoreId = id
    pendingWidgetRestorePage = String(page || "")
    pendingWidgetRestoreAttempts = 0
    widgetRestoreTimer.restart()
    return true
  }

  function widgetRestoreSatisfied(pluginId, page) {
    const id = String(pluginId || "")
    const requestedPage = String(page || "")
    const widget = findPanelWidget(id)
    if (!widget || widget.opened !== true) return false
    if (id !== "hancore.shibumi.control-center"
        || requestedPage === "") return true
    return widget.panelLoaded === true && widget.panelItem
      && String(widget.panelItem.settingsPage || "") === requestedPage
  }

  Timer {
    id: widgetRestoreTimer
    interval: 80
    repeat: true

    onTriggered: {
      root.pendingWidgetRestoreAttempts++
      if (!root.widgetRestoreSatisfied(root.pendingWidgetRestoreId,
          root.pendingWidgetRestorePage)) {
        if (root.pendingWidgetRestoreId
            === "hancore.shibumi.control-center"
            && root.pendingWidgetRestorePage !== "") {
          root.openConfigPage(root.pendingWidgetRestorePage)
        } else {
          root.summonBarWidget(root.pendingWidgetRestoreId)
        }
      }
      // A shell-style change can rebuild the layout delegates over more than
      // one event-loop turn. Reassert the idempotent open request long enough
      // to reach the replacement owner without keeping a permanent poller.
      if (root.pendingWidgetRestoreAttempts < 4) return
      stop()
      root.pendingWidgetRestoreId = ""
      root.pendingWidgetRestorePage = ""
      root.pendingWidgetRestoreAttempts = 0
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
        panelLoaded: slot.activeItem.panelLoaded === true
      })
    }
    return geometry
  }

  onBarConfigChanged: {
    applyBarConfig()
  }
  onLayoutConfigChanged: v1PluginReconcileTimer.restart()
  onInjectionCompleteChanged: {
    if (injectionComplete) hostReadyDelay.restart()
    else {
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
      const state = root.pluginService("hancore.shibumi.state")
      if (!state || typeof state.setGroupSetting !== "function")
        return "not-ready"
      let value = String(valueJson || "")
      try {
        value = JSON.parse(value)
      } catch (error) {
        // Plain strings remain convenient for CLI callers.
      }
      return state.setGroupSetting(String(groupId || ""),
        String(key || ""), value) ? "ok" : "rejected"
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
      if (root.isBarWidgetOpen("hancore.shibumi.control-center"))
        root.scheduleWidgetRestore(
          "hancore.shibumi.control-center",
          root.barWidgetPage("hancore.shibumi.control-center", "bars"))
      return state.setPresentationSetting(name, value)
        ? "ok" : "rejected"
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
      if (root.isBarWidgetOpen("hancore.shibumi.control-center"))
        root.scheduleWidgetRestore(
          "hancore.shibumi.control-center",
          root.barWidgetPage("hancore.shibumi.control-center", "bars"))
      return state && typeof state.setPresentationSetting === "function"
          && state.setPresentationSetting("shellStyle", value)
        ? "ok" : "rejected"
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
