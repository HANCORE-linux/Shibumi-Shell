pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import "ReactorModel.js" as ReactorModel

Item {
  id: root

  required property var bar
  readonly property bool active: bar && bar.reactorMode === 7
  readonly property string home: Quickshell.env("HOME")
  readonly property var workspaceService: bar ? bar.workspaceService : null
  readonly property var statusService: bar ? bar.statusService : null
  readonly property var powerService: bar ? bar.powerService : null
  readonly property var aiUsageService: bar ? bar.aiUsageService : null
  readonly property var notificationService: statusService
    ? statusService.notificationService : null
  readonly property var mediaService: bar && bar.shell
    && typeof bar.shell.firstPartyServiceFor === "function"
    ? bar.shell.firstPartyServiceFor("omarchy.media") : null
  readonly property var networkWidget: moduleItem("hancore.shibumi.network")
  readonly property var audioWidget: moduleItem("hancore.shibumi.audio")
  readonly property var centerWidget: moduleItem("hancore.shibumi.center")
  readonly property var updateWidget: centerWidget ? centerWidget.updateWidget : null
  readonly property string networkMode: networkWidget
    ? String(networkWidget.mode || "none") : ""
  readonly property bool outputMuted: audioWidget
    ? audioWidget.muted === true : false
  readonly property bool updateAvailable: updateWidget
    ? updateWidget.updateAvailable === true : false
  readonly property int notificationCount: notificationService
    && notificationService.pendingModel
    ? Number(notificationService.pendingModel.count) || 0 : 0
  readonly property string mediaTitle: mediaService
    ? String(mediaService.title || "") : ""
  readonly property string mediaArtist: mediaService
    ? String(mediaService.artist || "") : ""
  readonly property string mediaAlbum: mediaService
    ? String(mediaService.album || "") : ""
  readonly property bool batteryLow: powerService
    && powerService.hasBattery && powerService.discharging
    && powerService.percent <= 20

  property bool armed: false
  property int serial: 0
  property var eventHistory: []
  property double lastExternalTimestamp: 0
  property string lastThemeName: ""
  property string lastNetworkMode: ""
  property bool muteBaselined: false
  property bool dndBaselined: false
  property bool updateBaselined: false
  property int lastNotificationCount: -1
  property string lastTrackSignature: ""
  property var recentOpen: ({})
  property string activeAddress: ""
  property string pendingUrgentAddress: ""
  property string pendingUrgentClass: ""
  property string urgentAddress: ""
  property string urgentClass: ""
  property int urgentRepeats: 0
  property var warningNext: ({ offline: 0, battery: 0, urgent: 0 })
  property var quotaState: ({})
  property var warningQueue: []

  signal eventRaised(var event)
  signal cleared()

  visible: false
  width: 0
  height: 0

  function moduleItem(moduleName) {
    const slots = bar && Array.isArray(bar.moduleSlots) ? bar.moduleSlots : []
    for (let index = 0; index < slots.length; index++) {
      const slot = slots[index]
      if (slot && String(slot.moduleName || "") === moduleName && slot.activeItem)
        return slot.activeItem
    }
    return null
  }

  function publish(kind, options) {
    if (!active) return false
    const source = options || ({})
    const event = {
      serial: ++serial,
      timestamp: Date.now(),
      kind: String(kind || "text"),
      direction: Number(source.direction) < 0 ? -1 : 1,
      left: ReactorModel.sanitize(source.left, 64),
      right: ReactorModel.sanitize(source.right, 28),
      profile: ReactorModel.profile(source.profile),
      screen: String(source.screen || ""),
      count: Math.max(1, Math.min(36, Number(source.count) || 1)),
      gain: Math.max(0.1, Math.min(1, Number(source.gain) || 1))
    }
    if (event.kind === "text" && !event.left && !event.right) return false
    eventHistory = ReactorModel.boundedAppend(eventHistory, event, 8)
    eventRaised(event)
    return true
  }

  function pushText(left, right, profile, force, screen) {
    if (!active || (!force && statusService
        && statusService.notificationsSilenced)) return false
    return publish("text", {
      left: left,
      right: right,
      profile: profile || "long",
      screen: screen || ""
    })
  }

  function pushPulse(kind, direction, screen, options) {
    const source = options || ({})
    return publish(kind, {
      direction: direction,
      screen: screen || "",
      count: source.count,
      gain: source.gain,
      profile: "short"
    })
  }

  function clear() {
    eventHistory = []
    warningQueue = []
    warningDrain.stop()
    clearUrgent()
    serial++
    cleared()
  }

  function workspaceChanged() {
    if (!armed || !workspaceService) return
    const id = Number(workspaceService.focusedId) || 0
    if (id <= 0) return
    const state = workspaceService.workspaceState(id)
    pushText("WS " + id, ReactorModel.workspaceLabel(state.windowCount),
      "short", true, focusedScreenName())
  }

  function focusedScreenName() {
    const monitor = Hyprland.focusedMonitor
    return monitor ? String(monitor.name || "") : ""
  }

  function classForAddress(address) {
    const target = String(address || "")
    if (!target) return ""
    try {
      const toplevels = Hyprland.toplevels.values || []
      for (let index = 0; index < toplevels.length; index++) {
        const object = toplevels[index] ? toplevels[index].lastIpcObject : null
        const candidate = ReactorModel.parseAddress(object ? object.address : "")
        if (candidate === target)
          return String(object.class || object.initialClass || "")
      }
    } catch (_error) {}
    return ""
  }

  function rememberOpen(address) {
    if (!address) return
    const next = recentOpen
    const now = Date.now()
    next[address] = now
    for (const key in next) {
      if (now - next[key] > 5000) delete next[key]
    }
    recentOpen = next
  }

  function commitUrgent() {
    const address = pendingUrgentAddress
    let appClass = pendingUrgentClass
    pendingUrgentAddress = ""
    pendingUrgentClass = ""
    if (!armed || !active || !address || address === activeAddress) return
    const openedAt = recentOpen[address] || 0
    if (openedAt > 0 && Date.now() - openedAt < 2500) {
      const next = recentOpen
      delete next[address]
      recentOpen = next
      return
    }
    appClass = appClass || classForAddress(address)
    if (!appClass) return
    urgentAddress = address
    urgentClass = ReactorModel.sanitize(appClass, 28)
    urgentRepeats = 0
    const nextWarning = warningNext
    nextWarning.urgent = 0
    warningNext = nextWarning
    checkWarnings()
  }

  function clearUrgent() {
    urgentAddress = ""
    urgentClass = ""
    urgentRepeats = 0
    const next = warningNext
    next.urgent = 0
    warningNext = next
  }

  function handleHyprlandEvent(event) {
    if (!active || !event) return
    const name = String(event.name || "")
    const address = ReactorModel.parseAddress(event.data)
    if (name === "openwindow") {
      rememberOpen(address)
      pushPulse("win", 1, focusedScreenName())
    } else if (name === "closewindow") {
      pushPulse("win", -1, "")
      const next = recentOpen
      if (address && next[address] !== undefined) delete next[address]
      recentOpen = next
      if (address && address === urgentAddress) clearUrgent()
      if (address && address === pendingUrgentAddress) {
        pendingUrgentAddress = ""
        pendingUrgentClass = ""
        urgentDelay.stop()
      }
    } else if (name === "fullscreen") {
      pushText("FULLSCREEN", String(event.data).trim() === "1" ? "ON" : "OFF",
        "short", false, focusedScreenName())
    } else if (name === "urgent" && address) {
      pendingUrgentAddress = address
      pendingUrgentClass = classForAddress(address)
      urgentDelay.restart()
    } else if (name === "activewindowv2") {
      activeAddress = address
      if (address && address === urgentAddress) clearUrgent()
      if (address && address === pendingUrgentAddress) {
        pendingUrgentAddress = ""
        pendingUrgentClass = ""
        urgentDelay.stop()
      }
    }
  }

  function themeChanged() {
    themeNameReader.reload()
    themeDelay.restart()
  }

  function handleThemeText() {
    const name = String(themeNameReader.text() || "").trim()
    if (!lastThemeName) {
      lastThemeName = name
      return
    }
    if (!armed || !name || name === lastThemeName) return
    lastThemeName = name
    pushText(name, "THEME LOADED", "long", false, "")
  }

  function baselineExternal() {
    if (lastExternalTimestamp > 0) return
    let parsed = null
    try { parsed = ReactorModel.parseExternal(externalEventReader.text(), 0, Date.now()) }
    catch (_error) {}
    lastExternalTimestamp = parsed ? Math.min(parsed.timestamp, Date.now()) : Date.now()
  }

  function handleExternal() {
    if (lastExternalTimestamp <= 0) {
      baselineExternal()
      return
    }
    let parsed = null
    try {
      parsed = ReactorModel.parseExternal(externalEventReader.text(),
        lastExternalTimestamp, Date.now())
    } catch (_error) {}
    if (!parsed) return
    lastExternalTimestamp = parsed.timestamp
    if (parsed.left === "AI") return
    pushText(parsed.left, parsed.right, "long", false, "")
  }

  function announceNotification() {
    if (!armed || !notificationService || notificationCount <= lastNotificationCount
        || (statusService && statusService.notificationsSilenced)) {
      lastNotificationCount = notificationCount
      return
    }
    lastNotificationCount = notificationCount
    const model = notificationService.pendingModel
    if (!model || model.count < 1) return
    const entry = model.get(0)
    if (!entry) return
    const summary = String(entry.summary || "")
    const body = String(entry.body || "")
    const message = summary && body && body !== summary
      ? summary + " - " + body : summary || body
    pushText(message, entry.app || "NOTIFY", "long", false, "")
  }

  function scheduleTrack() {
    if (armed) trackDelay.restart()
  }

  function announceTrack() {
    if (!armed || !mediaTitle) return
    const signature = mediaTitle + "|" + mediaArtist + "|" + mediaAlbum
    if (signature === lastTrackSignature) return
    if (pushText(mediaTitle,
        mediaArtist + (mediaAlbum ? " - " + mediaAlbum : ""),
        "long", false, "")) lastTrackSignature = signature
  }

  function handleNetwork() {
    const current = networkMode
    if (!lastNetworkMode) {
      lastNetworkMode = current
      return
    }
    if (!armed || !current || current === lastNetworkMode) return
    if (current === "none") checkWarnings()
    else if (lastNetworkMode === "none")
      pushText("ONLINE", "NETWORK", "short", false, "")
    lastNetworkMode = current
  }

  function handleMute() {
    if (!muteBaselined) {
      muteBaselined = true
      return
    }
    if (armed) pushText("VOLUME", outputMuted ? "MUTED" : "UNMUTED",
      "short", false, "")
  }

  function handleDnd() {
    if (!dndBaselined) {
      dndBaselined = true
      return
    }
    if (armed) pushText(statusService.notificationsSilenced ? "DND ON" : "DND OFF",
      "", "short", true, "")
  }

  function handleUpdate() {
    if (!updateBaselined) {
      updateBaselined = true
      return
    }
    if (armed && updateAvailable)
      pushText("UPDATE READY", "OMARCHY", "long", false, "")
  }

  function queueWarning(left, right) {
    if (!armed || !active) return false
    for (let index = 0; index < warningQueue.length; index++) {
      if (warningQueue[index].left === left && warningQueue[index].right === right)
        return false
    }
    const next = warningQueue.slice(-4)
    next.push({ left: left, right: right })
    warningQueue = next
    if (!warningDrain.running) warningDrain.restart()
    return true
  }

  function checkQuotaWarnings(now) {
    if (!aiUsageService) return
    const providers = aiUsageService.providers || []
    const state = quotaState
    for (let index = 0; index < providers.length; index++) {
      const provider = providers[index]
      const id = String(provider.providerId || "ai")
      const percent = aiUsageService.usagePercent(provider)
      const previous = state[id] || ({ hot: false, next: 0 })
      if (percent < 75) previous.hot = false
      if (percent >= 80) {
        previous.hot = true
        if (now >= previous.next && queueWarning(
            String(provider.providerName || id) + " " + percent, "AI QUOTA!"))
          previous.next = now + 300000
      } else if (!previous.hot) previous.next = 0
      state[id] = previous
    }
    quotaState = state
  }

  function checkWarnings() {
    if (!armed || !active) return
    const now = Date.now()
    const next = warningNext
    if (networkMode === "none") {
      if (now >= next.offline && queueWarning("OFFLINE!", "NETWORK"))
        next.offline = now + 120000
    } else next.offline = 0
    if (batteryLow) {
      if (now >= next.battery && queueWarning(
          "BATTERY " + powerService.percent, "PLUG IN!"))
        next.battery = now + 120000
    } else next.battery = 0
    if (urgentAddress && urgentClass && now >= next.urgent && urgentRepeats < 3
        && queueWarning(urgentClass, "WANTS YOU!")) {
      next.urgent = now + 60000 * Math.pow(3, urgentRepeats)
      urgentRepeats++
    }
    checkQuotaWarnings(now)
    warningNext = next
  }

  function runTest(kindValue, argumentValue) {
    if (!active) return false
    const kind = String(kindValue || "").toLowerCase()
    const argument = String(argumentValue || "")
    const parts = argument.split("|")
    if (kind === "text" || kind === "text-long")
      return pushText(parts[0] || "THIS IS A LONG REACTOR TEST MESSAGE",
        parts.slice(1).join("|") || "SOURCE", "long", true, "")
    if (kind === "text-short")
      return pushText(parts[0] || "REACTOR", parts.slice(1).join("|") || "TEST",
        "short", true, "")
    if (kind === "warn" || kind === "text-warn")
      return pushText(parts[0] || "OFFLINE!", parts.slice(1).join("|") || "NETWORK",
        "warn", true, "")
    if (kind === "win" || kind === "win-open")
      return pushPulse("win", argument === "-1" || argument === "close" ? -1 : 1,
        focusedScreenName())
    if (kind === "win-close") return pushPulse("win", -1, focusedScreenName())
    if (kind === "monsweep" || kind === "sweep")
      return pushPulse("monsweep", argument === "-1" ? -1 : 1,
        focusedScreenName(), { count: 36, gain: 0.82 })
    if (kind === "workspace" || kind === "ws") {
      const workspace = Math.max(1, Number(argument) || 1)
      return pushText("WS " + workspace, "TEST APPS", "short", true, "")
    }
    if (kind === "clear") {
      clear()
      return true
    }
    return pushText("REACTOR TEST", kind || "EVENT", "short", true, "")
  }

  onNetworkModeChanged: handleNetwork()
  onOutputMutedChanged: handleMute()
  onUpdateAvailableChanged: handleUpdate()
  onNotificationCountChanged: announceNotification()
  onMediaTitleChanged: scheduleTrack()
  onMediaArtistChanged: scheduleTrack()
  onMediaAlbumChanged: scheduleTrack()
  onBatteryLowChanged: if (batteryLow) checkWarnings()

  Connections {
    target: Hyprland
    function onFocusedMonitorChanged() {
      if (root.armed) root.pushPulse("monsweep", 1, root.focusedScreenName(),
        { count: 36, gain: 0.82 })
    }
    function onRawEvent(event) { root.handleHyprlandEvent(event) }
  }

  Connections {
    target: root.workspaceService
    function onFocusedIdChanged() { root.workspaceChanged() }
  }

  Connections {
    target: root.statusService
    function onNotificationsSilencedChanged() { root.handleDnd() }
    function onVoxtypeStateChanged() {
      if (root.armed && root.statusService.voxtypeState === "recording")
        root.pushText("VOXTYPE", "REC", "short", false, "")
    }
  }

  FileView {
    id: themeNameReader
    path: root.home + "/.local/state/omarchy/current/theme.name"
    watchChanges: true
    printErrors: false
    onFileChanged: root.themeChanged()
    onLoaded: root.handleThemeText()
  }

  Timer {
    id: themeDelay
    interval: 180
    onTriggered: root.handleThemeText()
  }

  FileView {
    id: externalEventReader
    path: root.home + "/.cache/qs-reactor-event"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.handleExternal()
    onLoadFailed: root.baselineExternal()
  }

  Timer {
    id: urgentDelay
    interval: 700
    onTriggered: root.commitUrgent()
  }

  Timer {
    id: trackDelay
    interval: 800
    onTriggered: root.announceTrack()
  }

  Timer {
    id: warningDrain
    interval: 1
    onTriggered: {
      if (root.warningQueue.length === 0) return
      const next = root.warningQueue.slice()
      const warning = next.shift()
      root.warningQueue = next
      root.pushText(warning.left, warning.right, "warn", true, "")
      if (next.length > 0) {
        interval = 4200
        warningDrain.restart()
      } else interval = 1
    }
  }

  Timer {
    interval: 30000
    repeat: true
    running: root.armed
    onTriggered: root.checkWarnings()
  }

  Process {
    id: pacmanTail
    property int changedPackages: 0
    running: root.active
    command: ["bash", "-c", "exec tail -n 0 -F /var/log/pacman.log 2>/dev/null"]
    stdout: SplitParser {
      onRead: function(line) {
        if (line.indexOf("transaction started") >= 0) pacmanTail.changedPackages = 0
        else if (line.indexOf("] upgraded ") >= 0
            || line.indexOf("] installed ") >= 0
            || line.indexOf("] removed ") >= 0) pacmanTail.changedPackages++
        else if (line.indexOf("transaction completed") >= 0
            && pacmanTail.changedPackages > 0) {
          const count = pacmanTail.changedPackages
          root.pushText(count + (count === 1 ? " PACKAGE" : " PACKAGES")
            + " CHANGED", "PACMAN", "long", false, "")
          pacmanTail.changedPackages = 0
        }
      }
    }
  }

  Timer {
    interval: 3000
    running: true
    onTriggered: {
      root.lastNetworkMode = root.networkMode
      root.lastNotificationCount = root.notificationCount
      root.lastTrackSignature = root.mediaTitle + "|" + root.mediaArtist
        + "|" + root.mediaAlbum
      root.muteBaselined = true
      root.dndBaselined = true
      root.updateBaselined = true
      root.armed = true
      root.checkWarnings()
      root.pushText("REACTOR", "ARMED", "short", true, "")
    }
  }
}
