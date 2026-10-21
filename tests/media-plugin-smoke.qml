import QtQuick
import Quickshell
import "media" as Media

ShellRoot {
  id: root

  property int phase: 0
  property int waits: 0
  property int rebindPhase: 0
  property var openPanelReference: null
  property real activeWidth: 0
  property string mediaShellStyle: "shibumi"
  property var mediaSettings: ({ spectrum: false, mediaStyle: "default" })

  readonly property bool quiescenceCheck: Quickshell.env("SHIBUMI_MEDIA_QUIESCENCE") === "1"
  property int quietCase: 0
  property int quietTicks: 0
  property var quietObservers: []
  property var quietMeasurements: []
  property real quietStarted: 0
  property int positionReads: 0
  property int initialPositionReads: 0
  property var quietFailures: []
  property var quietPulse: null
  property var quietPulseStart: []
  property bool quietTailValid: true
  property real quietTransitionAt: 0
  readonly property var quietCases: [
    ["shibumi", "default", false, false], ["full", "default", false, false],
    ["shibumi", "full", false, false], ["full", "full", false, false],
    ["shibumi", "default", true, false], ["full", "default", true, false],
    ["shibumi", "default", false, true], ["full", "default", false, true],
    ["shibumi", "default", false, false, "paused"], ["full", "full", false, false, "paused"],
    ["shibumi", "default", false, false, "hidden"], ["full", "full", false, false, "hidden"],
    ["full", "full", false, true, "paused"], ["full", "full", false, true, "no-length"],
    ["full", "full", false, true, "hidden"]
  ]

  // Count synchronous geometry-change batches, not samples from the fixture
  // timer: all properties of a surface must change inside its one cadence step.
  // Hidden descendants are observed too, catching the old hidden marquee.
  function observeSurface(surface, excluded) {
    const measured = { batches: {}, events: 0, outside: 0, positions: [], fractional: false }
    function connect(signal, callback) {
      signal.connect(callback)
      quietObservers.push([signal, callback])
    }
    function changed() {
      measured.events++
      if (surface.motionStepping !== true) measured.outside++
      measured.batches[String(surface.motionStep)] = true
    }
    function visit(node) {
      if (node === excluded) return
      for (const key of ["x", "y", "width", "height", "rotation", "opacity", "text"]) {
        if (node[key + "Changed"]) connect(node[key + "Changed"], changed)
      }
      const children = node.children || []
      for (let i = 0; i < children.length; i++) visit(children[i])
    }
    visit(surface)
    if (surface.currentPositionChanged) connect(surface.currentPositionChanged, function() {
      measured.positions.push(Date.now())
      measured.fractional = measured.fractional || surface.currentPosition !== Math.floor(surface.currentPosition)
    })
    return measured
  }

  function checkDiscretePosition(media) {
    media.close()
    media.visible = true
    playerA.isPlaying = false
    playerA.length = 245
    playerA.position = 10.75
    media.toggle()
    const panel = media.panelItem
    if (!panel) return false
    let valid = panel.currentPosition === 10
    playerA.position = 20.75
    valid = valid && panel.currentPosition === 20
    playerA.length = 15.5
    valid = valid && panel.currentPosition === 15
    playerA.length = 245
    let reads = 0
    playerA.position = { valueOf: function() { reads++; return 30.9 } }
    const before = reads
    playerA.uniqueId++
    valid = valid && reads === before + 1 && panel.currentPosition === 30
    playerA.isPlaying = true
    valid = valid && reads === before + 2
    media.close()
    const closedReads = reads
    playerA.uniqueId++
    playerA.isPlaying = false
    valid = valid && reads === closedReads
    console.log("MEDIA_DISCRETE_POSITION", JSON.stringify({ valid: valid, reads: reads }))
    return valid
  }

  function visiblePulse(node) {
    if ("barH1" in node && node.visible) return node
    const children = node.children || []
    for (let i = 0; i < children.length; i++) {
      const found = visiblePulse(children[i])
      if (found) return found
    }
    return null
  }

  function checkPulseRevocation(media) {
    let valid = true
    for (const vertical of [false, true]) {
      fakeBar.vertical = vertical
      for (const panel of [false, true]) {
        playerA.isPlaying = true
        const pulse = visiblePulse(media)
        if (!pulse) return false
        pulse.elapsed = 0
        pulse.advance(200)
        playerA.isPlaying = false
        valid = valid && pulse.settling === true && media.motionRunning
        if (panel) media.toggle()
        else media.visible = false
        valid = valid && pulse.settling === false && !media.motionRunning
        if (panel) media.close()
        else media.visible = true
        valid = valid && pulse.settling === false && !media.motionRunning
      }
    }
    fakeBar.vertical = false
    console.log("MEDIA_PAUSE_REVOCATION", JSON.stringify({ valid: valid }))
    return valid
  }

  function checkQuiescence(media) {
    if (!media) return
    const scenario = quietCases[quietCase]
    if (quietTicks === 0) {
      media.close()
      media.visible = true
      mediaShellStyle = scenario[0]
      mediaSettings = ({ spectrum: false, mediaStyle: scenario[1] })
      fakeBar.vertical = scenario[2]
      playerA.length = scenario[4] === "no-length" ? 0 : 245
      quietPulse = null
      quietTailValid = true
      if (quietCase === 8) {
        playerA.isPlaying = true
        quietPulse = visiblePulse(media)
        if (quietPulse) {
          quietPulse.elapsed = 0
          quietPulse.advance(200)
          quietPulseStart = [quietPulse.barH1, quietPulse.barH2, quietPulse.barH3]
        }
      }
      playerA.isPlaying = scenario[4] !== "paused"
      quietTransitionAt = Date.now()
      if (quietCase === 8) quietTailValid = !!quietPulse
        && [quietPulse.barH1, quietPulse.barH2, quietPulse.barH3].every((value, i) => value === quietPulseStart[i] && value > 0.08)
      const epoch = Date.now()
      // Like the native computed getter: advances without position notifications.
      playerA.position = { valueOf: function() {
        root.positionReads++
        return 61 + (Date.now() - epoch) / 1000
      } }
      if (scenario[3]) media.toggle()
      if (scenario[4] === "hidden") media.visible = false
    }
    quietTicks++
    if (quietTicks === 3 && quietPulse) {
      const values = [quietPulse.barH1, quietPulse.barH2, quietPulse.barH3]
      quietTailValid = quietTailValid && values.every((value, i) => value > 0.08 && value < quietPulseStart[i]
        && Math.abs(value - (0.08 + (quietPulseStart[i] - 0.08) * Math.pow(1 - Math.min(1, quietPulse.restElapsed / [380, 430, 480][i]), 3))) < 1e-12)
      console.log("MEDIA_PAUSE_EASE", JSON.stringify({ values: values, from: quietPulseStart,
        elapsed: quietPulse.restElapsed, valid: quietTailValid }))
    }
    if (quietTicks === 9 && scenario[3] && scenario[4] === "hidden" && media.panelItem)
      media.panelItem.visible = false
    if (quietTicks === 10) {
      if (quietPulse) quietTailValid = quietTailValid && Date.now() - quietTransitionAt >= 500
        && !media.motionRunning && [quietPulse.barH1, quietPulse.barH2, quietPulse.barH3].every(value => value === 0.08)
        && checkPulseRevocation(media)
      quietMeasurements = [observeSurface(media, media.panelItem)]
      if (media.panelItem) quietMeasurements.push(observeSurface(media.panelItem))
      quietStarted = Date.now()
      initialPositionReads = positionReads
    }
    if (quietTicks > 10 && quietTicks < 40 && playerA.isPlaying && scenario[4] !== "hidden") {
      // Two event-fed frames between ticks: only the latest can be displayed.
      fakeSpectrum.levels = Array(24).fill(0.1)
      fakeSpectrum.levels = Array(24).fill(quietTicks % 2 ? 0.8 : 0.4)
    }
    if (quietTicks < 40) return
    for (const observer of quietObservers) observer[0].disconnect(observer[1])
    quietObservers = []
    const seconds = (Date.now() - quietStarted) / 1000
    const stopped = scenario[4] === "paused" || scenario[4] === "hidden"
    const rows = quietMeasurements.map(function(m, index) {
      const count = Object.keys(m.batches).length
      const shouldMove = !stopped && (index === 1 || !scenario[3])
      const gaps = m.positions.slice(1).map((time, i) => time - m.positions[i])
      return { batches: count, events: m.events, outside: m.outside,
        positions: m.positions, fractional: m.fractional,
        valid: m.outside === 0 && count <= Math.ceil(27.5 * seconds)
          && (shouldMove ? count > 0 : m.events === 0)
          && !m.fractional && gaps.every(gap => gap >= 1000)
          && m.positions.length <= Math.ceil(seconds) }
    })
    const reads = positionReads - initialPositionReads
    const expectReads = scenario[3] && !stopped && scenario[4] !== "no-length"
    const valid = quietTailValid && rows.every(row => row.valid) && (!scenario[3] || rows.length === 2)
      && (expectReads ? reads > 0 && reads <= Math.ceil(seconds) : reads === 0)
    if (!valid) quietFailures = quietFailures.concat([quietCase])
    console.log("MEDIA_CADENCE", JSON.stringify({ scenario: scenario, seconds: seconds,
      surfaces: rows, positionReads: reads, valid: valid }))
    if (++quietCase < quietCases.length) { quietTicks = 0; return }
    if (quietFailures.length !== 0 || !checkDiscretePosition(media)) return fail("media cadence/stop/position contract: " + JSON.stringify(quietFailures))
    console.log("media quiescence smoke passed")
    Qt.quit()
  }

  function fail(message) {
    console.error("media-plugin-smoke:", message)
    Qt.exit(1)
    throw new Error(message)
  }

  QtObject {
    id: playerA
    property string key: "player-a"
    property string identity: "Vesktop"
    property string desktopEntry: "vesktop"
    property string trackTitle: "A deliberately long track title for marquee validation"
    property string trackArtist: "Artist A"
    property string trackAlbum: "Album A"
    property string trackArtUrl: ""
    property bool isPlaying: true
    property bool canGoPrevious: true
    property bool canGoNext: true
    property bool canTogglePlaying: true
    property bool canPlay: true
    property bool canPause: true
    property bool canControl: true
    property bool shuffleSupported: true; property bool loopSupported: true
    property bool canSeek: true; property bool positionSupported: true; property bool lengthSupported: true
    property bool shuffle: false; property int loopState: 0; property int uniqueId: 1
    property var position: 61
    property real length: 245
  }

  QtObject {
    id: playerB
    property string key: "player-b"
    property string identity: "Firefox"
    property string desktopEntry: "firefox"
    property string trackTitle: "Track B"
    property string trackArtist: "Artist B"
    property string trackAlbum: ""
    property string trackArtUrl: ""
    property bool isPlaying: false
    property bool canGoPrevious: false
    property bool canGoNext: true
    property bool canTogglePlaying: true
    property bool canPlay: true
    property bool canPause: true
    property bool canControl: true
    property bool shuffleSupported: false; property bool loopSupported: false
    property bool canSeek: false; property bool positionSupported: true; property bool lengthSupported: true
    property bool shuffle: false; property int loopState: 0; property int uniqueId: 2
    property real position: 0
    property real length: 180
  }

  QtObject {
    id: mediaState
    property var activePlayer: playerA
    property var sourcePlayers: [playerA, playerB]
    // Deliberately no hasMedia property: the native 4.0.3 proxy omits it.
    property string lastAction: ""
    property string lastTarget: ""
    property string selectedKey: ""
    property int actionCount: 0

    function playerKey(player) { return player ? String(player.key || "") : "" }

    function runAction(action, showFeedback, targetKey) {
      if (showFeedback) root.fail("unexpected media OSD")
      lastAction = String(action || "")
      lastTarget = String(targetKey || "")
      actionCount++
      if (lastAction === "playPause" && activePlayer)
        activePlayer.isPlaying = !activePlayer.isPlaying
      return activePlayer !== null
    }

    function selectPlayer(key) {
      selectedKey = String(key || "")
      if (selectedKey === playerA.key) activePlayer = playerA
      else if (selectedKey === playerB.key) activePlayer = playerB
      else return false
      return true
    }
  }

  QtObject {
    id: fakeSpectrum
    property var clients: []
    property var levels: [
      0.04, 0.04, 0.04, 0.04, 0.04, 0.04,
      0.04, 0.04, 0.04, 0.04, 0.04, 0.04,
      0.04, 0.04, 0.04, 0.04, 0.04, 0.04,
      0.04, 0.04, 0.04, 0.04, 0.04, 0.04
    ]
    property var themeColors: []
    property string state: "running"
    property bool workerRunning: false
    readonly property int clientCount: clients.length

    function beginSpectrum(owner) {
      if (!owner || clients.indexOf(owner) >= 0) return false
      clients = clients.concat([owner])
      return true
    }

    function endSpectrum(owner) {
      if (!owner || clients.indexOf(owner) < 0) return false
      clients = clients.filter(function(candidate) { return candidate !== owner })
      return true
    }
  }

  QtObject {
    id: replacementSpectrum
    property var clients: []
    property var levels: fakeSpectrum.levels
    property var themeColors: []
    property string state: "running"
    property bool workerRunning: false
    readonly property int clientCount: clients.length
    function beginSpectrum(owner) {
      if (!owner || clients.indexOf(owner) >= 0) return false
      clients = clients.concat([owner]); return true
    }
    function endSpectrum(owner) {
      if (clients.indexOf(owner) < 0) return false
      clients = clients.filter(function(value) { return value !== owner }); return true
    }
  }

  QtObject {
    id: fakeShell
    property bool serviceAvailable: true
    property var spectrumBackend: fakeSpectrum
    function firstPartyServiceFor(id) {
      return serviceAvailable && String(id || "") === "omarchy.media"
        ? mediaState : null
    }
    function serviceFor(id) {
      return String(id || "") === "hancore.shibumi.media"
        ? spectrumBackend : null
    }
  }

  QtObject {
    id: fakeBar
    property bool vertical: false
    property int barSize: 28
    property string position: "top"
    property string fontFamily: "monospace"
    property color foreground: "#e8e8e8"
    property color barForeground: foreground
    property color background: "#181818"
    property color urgent: "#88bbee"
    property bool foregroundAnimationEnabled: false
    property var shell: fakeShell
    property var activePopout: null
    property var clickTargets: []
    property var visualTokens: ({
      pillHeight: 24,
      pillRadius: 12,
      pill: "#332f2f",
      pillBorder: "#555050",
      pillBorderWidth: 1,
      pillShadow: "#000000",
      shadowEnabled: false,
      pillPaddingX: 9,
      slotHeight: 28,
      contentGap: 5,
      compactGap: 4,
      labelSize: 12,
      iconSize: 15,
      shellStyle: root.mediaShellStyle,
      presentation: ({ radius: "large" })
    })

    function showTooltip(_target, _text) {}
    function hideTooltip(_target) {}
    function requestPopout(owner) { activePopout = owner }
    function releasePopout(owner) { if (activePopout === owner) activePopout = null }
    function switchPanelFrom(_owner, _direction) { return false }
    function targetBelongsToWindow(_target, _window) { return true }
    function registerClickTarget(target) {
      if (clickTargets.indexOf(target) < 0) clickTargets = clickTargets.concat([target])
    }
    function unregisterClickTarget(target) {
      clickTargets = clickTargets.filter(function(item) { return item !== target })
    }
  }

  Loader {
    id: mediaLoader
    active: true
    sourceComponent: Component {
      Media.BarWidget {
        bar: fakeBar
        settings: root.mediaSettings
      }
    }
  }

  Media.BarWidget {
    id: unavailableMedia
    bar: unavailableBar
    settings: ({ spectrum: false })
  }

  QtObject {
    id: unavailableBar
    property var shell: null
    property int barSize: 28
    property bool vertical: false
    property string fontFamily: "monospace"
    property color foreground: "#e8e8e8"
    property color barForeground: foreground
    property color background: "#181818"
    property color urgent: "#88bbee"
    property bool foregroundAnimationEnabled: false
    property var visualTokens: fakeBar.visualTokens
    property var clickTargets: []
    function showTooltip(_target, _text) {}
    function hideTooltip(_target) {}
    function registerClickTarget(target) {
      if (clickTargets.indexOf(target) < 0) clickTargets = clickTargets.concat([target])
    }
    function unregisterClickTarget(target) {
      clickTargets = clickTargets.filter(function(item) { return item !== target })
    }
  }

  Timer {
    interval: 60
    repeat: true
    running: true
    onTriggered: {
      const media = mediaLoader.item
      if (root.quiescenceCheck) { root.checkQuiescence(media); return }
      if (root.phase === 0) {
        if (!media || !media.mediaService || !media.active || !media.playing
            || media.trackLabel.indexOf("Artist A") < 0 || media.panelLoaded
            || media.fullMode || !media.defaultMode || !media.v1Presentation
            || !media.v1FullVisible || media.museVisible
            || media.museBandCount !== 24
            || fakeSpectrum.clientCount !== 0
            || unavailableMedia.visible || fakeBar.clickTargets.length !== 1)
          return root.fail("initial media service/presentation contract")
        root.activeWidth = media.implicitWidth
        media.interactionTarget.triggerPress(Qt.LeftButton)
        if (mediaState.lastAction !== "playPause" || playerA.isPlaying)
          return root.fail("play/pause action forwarding")
        media.interactionTarget.wheelMoved(120)
        if (mediaState.lastAction !== "previous")
          return root.fail("wheel previous action forwarding")
        root.mediaSettings = ({ spectrum: false, mediaStyle: "full" })
      } else if (root.phase === 1) {
        if (!media.fullMode || !media.museMode || !media.museVisible
            || !media.v1Presentation || fakeSpectrum.clientCount !== 1)
          return root.fail("V1 FULL muse presentation/lease")
        media.runMusePrimaryAction()
        if (mediaState.lastAction !== "playPause" || !playerA.isPlaying)
          return root.fail("FULL muse play/pause forwarding")
        media.runMuseWheel(120)
        if (mediaState.lastAction !== "next")
          return root.fail("FULL muse wheel-next forwarding")
        media.runMuseWheel(-120)
        if (mediaState.lastAction !== "previous")
          return root.fail("FULL muse wheel-previous forwarding")
        root.mediaShellStyle = "full"
      } else if (root.phase === 2) {
        if (!media.fullMode || !media.museMode || !media.museVisible
            || media.v1Presentation || fakeSpectrum.clientCount !== 1)
          return root.fail("V2 FULL muse presentation/lease")
        root.mediaSettings = ({ spectrum: false, mediaStyle: "default" })
      } else if (root.phase === 3) {
        if (media.fullMode || !media.defaultMode || !media.v1FullVisible
            || media.museVisible || fakeSpectrum.clientCount !== 0)
          return root.fail("shared default presentation")
        fakeShell.spectrumBackend = null
        media.interactionTarget.triggerPress(Qt.RightButton)
      } else if (root.phase === 4) {
        if (!media.opened || !media.panelLoaded || !media.panelItem) {
          if (++root.waits > 45) return root.fail("real media panel did not load")
          return
        }
        const panel = media.panelItem
        if (root.rebindPhase > 0 && panel !== root.openPanelReference)
          return root.fail("service refresh recreated the open media panel")
        if (root.rebindPhase === 0) {
          if (panel.spectrumService !== null)
            return root.fail("panel did not open without a spectrum provider")
          root.openPanelReference = panel
          root.mediaSettings = ({ spectrum: true, mediaStyle: "default" })
        } else if (root.rebindPhase === 1) {
          if (!panel.spectrumEnabled || fakeSpectrum.clientCount !== 0)
            return root.fail("open panel did not observe spectrum preference")
          fakeShell.spectrumBackend = fakeSpectrum
        } else if (root.rebindPhase === 2) {
          if (panel.spectrumService !== fakeSpectrum || fakeSpectrum.clientCount !== 1)
            return root.fail("open panel did not attach late spectrum provider")
          root.mediaSettings = ({ spectrum: false, mediaStyle: "default" })
        } else if (root.rebindPhase === 3) {
          if (panel.spectrumEnabled || fakeSpectrum.clientCount !== 0)
            return root.fail("open panel retained disabled spectrum lease")
          fakeShell.spectrumBackend = replacementSpectrum
          root.mediaSettings = ({ spectrum: true, mediaStyle: "default" })
        } else if (root.rebindPhase === 4) {
          if (panel.spectrumService !== replacementSpectrum
              || fakeSpectrum.clientCount !== 0 || replacementSpectrum.clientCount !== 1)
            return root.fail("open panel did not replace its spectrum provider")
          fakeShell.serviceAvailable = false
        } else if (root.rebindPhase === 5) {
          if (panel.mediaService !== null || replacementSpectrum.clientCount !== 0
              || ("vinylRotating" in panel && panel.vinylRotating))
            return root.fail("open panel retained revoked media authority")
          fakeShell.serviceAvailable = true
          fakeShell.spectrumBackend = null
        } else if (root.rebindPhase === 6) {
          if (panel.mediaService !== mediaState || panel.spectrumService !== null
              || replacementSpectrum.clientCount !== 0)
            return root.fail("open panel did not recover current media authority")
          root.mediaSettings = ({ spectrum: false, mediaStyle: "default" })
          fakeShell.spectrumBackend = fakeSpectrum
        }
        if (root.rebindPhase++ < 7) return
        if (typeof panel.directAction !== "function") return root.fail("direct MPRIS controls missing")
        const actionCount = mediaState.actionCount, direct = { supported: panel.shuffleControl.enabled && panel.repeatControl.enabled && panel.seekControl.enabled }
        panel.shuffleControl.clicked(); direct.shuffle = playerA.shuffle && panel.shuffleControl.checked
        direct.cycle = [1, 2, 0].every(state => { panel.repeatControl.clicked(); return playerA.loopState === state && panel.repeatControl.checked === (state !== 0) })
        direct.seek = panel.directAction("seek", playerA, -5, 1) && playerA.position === 0 && panel.directAction("seek", playerA, 80, 1) && playerA.position === 80 && panel.directAction("seek", playerA, 999, 1) && playerA.position === 245
        direct.invalid = !panel.directAction("seek", playerA, NaN, 1) && !panel.directAction("seek", playerB, 30, 2)
        panel.selectSource(1)
        direct.unsupported = !panel.shuffleControl.enabled && !panel.repeatControl.enabled && !panel.seekControl.enabled && !panel.directAction("shuffle", playerB) && !panel.directAction("repeat", playerB) && !panel.directAction("seek", playerB, 30, 2)
        playerB.shuffleSupported = true; playerB.loopSupported = true; playerB.canSeek = true
        panel.shuffleControl.clicked(); direct.selected = !panel.directAction("shuffle", playerA) && playerB.shuffle && playerA.shuffle && panel.directAction("repeat", playerB) && playerB.loopState === 1 && panel.directAction("seek", playerB, 50, 2) && playerB.position === 50
        playerB.uniqueId = 3; direct.stale = !panel.directAction("seek", playerB, 10, 2) && playerB.position === 50
        playerB.positionSupported = false; direct.noPosition = !panel.seekControl.enabled && !panel.directAction("seek", playerB, 10, 3); playerB.positionSupported = true
        playerB.lengthSupported = false; direct.noLength = !panel.seekControl.enabled && !panel.directAction("seek", playerB, 10, 3); playerB.lengthSupported = true
        playerB.canControl = false; direct.noControl = !panel.shuffleControl.enabled && !panel.repeatControl.enabled && !panel.seekControl.enabled && !panel.directAction("shuffle", playerB); playerB.canControl = true
        mediaState.sourcePlayers = [playerA]; direct.detached = !panel.shuffleControl.enabled && !panel.directAction("shuffle", playerB); mediaState.sourcePlayers = [playerA, playerB]
        panel.selectSource(0); direct.owner = mediaState.actionCount === actionCount && panel.runAction("next") && mediaState.actionCount === actionCount + 1 && mediaState.lastTarget === "player-a"
        console.log("243_MPRIS_CONTROLS", JSON.stringify(direct))
        if (Object.values(direct).some(value => !value)) return root.fail("direct MPRIS capability, target or owner path")
        if (media.panelItem.renderedSourceCount !== 2
            || media.panelItem.spectrumWorkerRunning
            || media.panelItem.formatTime(61) !== "1:01"
            || media.panelItem.currentLength !== 245)
          return root.fail("lazy panel/state contract")
        if (!media.panelItem.selectSource(1)
            || mediaState.selectedKey !== "player-b"
            || mediaState.activePlayer !== playerB)
          return root.fail("source selection forwarding")
        media.close()
      } else if (root.phase === 5) {
        if (media.opened || media.panelLoaded || media.activePlayer !== playerB)
          return root.fail("lazy panel close")
        mediaState.activePlayer = null
      } else if (root.phase === 6) {
        if (media.active || media.implicitWidth >= root.activeWidth)
          return root.fail("idle V1 presentation")
        media.interactionTarget.triggerPress(Qt.LeftButton)
      } else if (root.phase === 7) {
        if (!media.opened || !media.panelLoaded) return
        media.close()
        mediaLoader.active = false
      } else {
        if (fakeBar.clickTargets.length !== 0 || fakeBar.activePopout !== null
            || fakeSpectrum.clientCount !== 0 || replacementSpectrum.clientCount !== 0)
          return root.fail("media teardown")
        stop()
        console.log("media plugin smoke passed")
        Qt.quit()
      }
      root.phase++
    }
  }
}
