pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "hancore.shibumi.network" as Network

ShellRoot {
  id: host

  property int registryRevision: 0
  property var helperMarks: []
  property var barMarks: []
  property int ownerCreated: 0
  property int ownerReleased: 0
  property int providerCreated: 0
  property int providerDestroyed: 0
  property int providerDetached: 0
  property int networkCreated: 0
  property int networkDestroyed: 0
  property int networkBarRevoked: 0
  property int networkServiceRevoked: 0
  property bool networkRevokedWithReady: false
  property var currentNetworkWidget: null
  property alias networkService: controlledNetworkService
  property bool statusEnabled: true
  property bool statusEntryEnabled: true
  property string slotRegion: "left"
  property var currentProviders: ({})
  property var cachedProviders: []
  property var cachedCatalogs: []
  property var events: []
  property var initialProviders: ({})
  property var oldBar: null
  property int initialHelperCalls: 0
  property int phase: 0

  function allocateBarSerial() {
    barMarks.push("bar")
    return barMarks.length
  }

  function recordProviderCreated(kind, item) {
    providerCreated++
    const next = Object.assign({}, currentProviders)
    next[kind] = item
    currentProviders = next
    cachedProviders = cachedProviders.concat([item])
    events.push("provider-created:" + kind)
  }

  function recordProviderDetached(kind, ownerCount) {
    providerDetached++
    events.push("provider-detached:" + kind + ":owners=" + ownerCount)
  }

  function recordProviderDestroyed(kind, item) {
    providerDestroyed++
    const next = Object.assign({}, currentProviders)
    if (next[kind] === item) next[kind] = null
    currentProviders = next
    events.push("provider-destroyed:" + kind)
  }

  function fail(message) {
    console.error("bar-context-lifecycle-regression: " + message)
    Qt.exit(1)
  }

  function require(condition, message) {
    if (!condition) fail(message)
  }

  component ProviderBase: Item {
    id: provider
    required property string kind
    property var bar: null
    property string moduleName: ""
    property var settings: ({})
    property real availableWidth: 0
    property var cachedBar: null
    property int cachedBarSerial: -1
    property var lifecycleChild: null

    function registeredComponent(pluginId) {
      void(host.registryRevision)
      if (bar && typeof bar.registeredWidgetComponent === "function")
        return bar.registeredWidgetComponent(pluginId)
      const registry = bar ? bar.barWidgetRegistry : null
      if (registry) void(registry.revision)
      const widgets = registry && registry.widgets ? registry.widgets : ({})
      const entry = widgets[pluginId]
      return entry ? entry.component : null
    }

    function registeredSource(pluginId) {
      void(host.registryRevision)
      if (bar && typeof bar.registeredWidgetSource === "function")
        return bar.registeredWidgetSource(pluginId)
      const registry = bar && bar.shell && "pluginRegistry" in bar.shell
        ? bar.shell.pluginRegistry : null
      const manifest = registry && registry.installedPlugins
        ? registry.installedPlugins[String(pluginId || "")] : null
      return registry && typeof registry.entryPointUrl === "function"
        ? registry.entryPointUrl(manifest, "barWidget") : ""
    }

    onBarChanged: {
      if (bar) {
        cachedBar = bar
        cachedBarSerial = Number(bar.creationId)
        if (lifecycleChild) lifecycleChild.bar = bar
        host.events.push("provider-attached:" + kind + ":bar=" + cachedBarSerial)
      } else if (cachedBar) {
        if (cachedBar.tearingDown === true && lifecycleChild) {
          lifecycleChild.registeredBar = null
          lifecycleChild.bar = null
          host.events.push("status-child-detached-during-bar-teardown")
        }
        host.recordProviderDetached(kind, cachedBar.loadedOwners.length)
      }
    }
    Component.onCompleted: {
      if (lifecycleChild) lifecycleChild.bar = bar
      host.recordProviderCreated(kind, provider)
    }
    Component.onDestruction: {
      if (lifecycleChild) {
        if (cachedBar && cachedBar.tearingDown === true)
          lifecycleChild.registeredBar = null
        lifecycleChild.bar = null
      }
      host.recordProviderDestroyed(kind, provider)
    }
  }

  component StatusProvider: ProviderBase {
    id: statusProvider
    kind: "status"
    lifecycleChild: Item {
      id: statusLifecycleChild
      property var bar: statusProvider.bar
      property var registeredBar: null

      function syncClickRegistration() {
        if (registeredBar)
          registeredBar.unregisterClickTarget(statusLifecycleChild)
        registeredBar = bar
        if (registeredBar)
          registeredBar.registerClickTarget(statusLifecycleChild)
      }

      onBarChanged: syncClickRegistration()
      Component.onDestruction: if (registeredBar)
        registeredBar.unregisterClickTarget(statusLifecycleChild)
    }
    readonly property url updateSource: registeredSource("hancore.shibumi.update-center")
    readonly property url traySource: registeredSource("omarchy.tray")
    readonly property Component updateComponent: String(updateSource) ? null
      : registeredComponent("hancore.shibumi.update-center")
    readonly property Component trayComponent: String(traySource) ? null
      : registeredComponent("omarchy.tray")
  }

  component CenterProvider: ProviderBase {
    kind: "center"
    readonly property url updateSource: registeredSource("omarchy.system-update")
    readonly property Component updateComponent: String(updateSource) ? null
      : registeredComponent("omarchy.system-update")
  }

  component AudioProvider: ProviderBase {
    kind: "audio"
    readonly property url backendPanelSource: registeredSource("omarchy.audio")
    readonly property Component panelComponent: String(backendPanelSource) ? null
      : registeredComponent("omarchy.audio")
  }

  QtObject {
    id: controlledNetworkService
    property bool ready: true
    property bool backendAvailable: true
    property string kind: "wifi"
    property string label: "Lifecycle Network"
    property int signalStrength: 77
    property real downloadRate: 4096
    property real uploadRate: 2048
  }

  component NetworkProvider: Network.BarWidget {
    id: networkWidget
    property bool serviceAttached: false
    Component.onCompleted: {
      host.networkCreated++
      host.currentNetworkWidget = networkWidget
      host.events.push("network-created")
    }
    Component.onDestruction: {
      host.networkDestroyed++
      if (host.currentNetworkWidget === networkWidget)
        host.currentNetworkWidget = null
      host.events.push("network-destroyed")
    }
    onBarChanged: {
      if (bar !== null) serviceAttached = true
      else if (serviceAttached) host.networkBarRevoked++
    }
    onNetworkServiceChanged: {
      if (serviceAttached && networkService === null && bar === null) {
        host.networkServiceRevoked++
        host.networkRevokedWithReady = networkReady === true
        host.events.push("network-service-revoked:ready=" + networkReady
          + ":rates=" + networkWidget.downloadRate
          + "/" + networkWidget.uploadRate)
      }
    }
  }

  component CatalogProvider: ProviderBase {
    id: catalogProvider
    kind: "control-center"
    property QtObject controller: QtObject {
      property var bar: catalogProvider.bar
      onBarChanged: host.events.push("catalog-controller-bar:" + (bar ? "set" : "null"))
    }
    readonly property var unplacedPluginIds: {
      void(host.registryRevision)
      const candidate = controller && "bar" in controller ? controller.bar : null
      const layout = candidate && "layoutController" in candidate
        ? candidate.layoutController : null
      if (!candidate || typeof candidate.activePluginSpecs !== "function"
          || !layout || typeof layout.unplacedPluginIdsFor !== "function") return []
      const specs = candidate.activePluginSpecs()
      if (!Array.isArray(specs)) return []
      const providers = !layout.v2Mode && "v1FamilySlotBindings" in candidate
        ? Object.values(candidate.v1FamilySlotBindings || {}) : []
      return layout.unplacedPluginIdsFor(specs.filter(function(spec) {
        return !spec || providers.indexOf(spec.pluginId) < 0
      }))
    }
    Component.onCompleted: host.cachedCatalogs = host.cachedCatalogs.concat([controller])
  }

  Component { id: statusHostComponent; StatusProvider {} }
  Component { id: centerHostComponent; CenterProvider {} }
  Component { id: audioHostComponent; AudioProvider {} }
  Component { id: networkHostComponent; NetworkProvider {} }
  Component { id: catalogHostComponent; CatalogProvider {} }

  Component.onCompleted: barLoader.setSource("PrivateLifecycleBar.qml", {
    hostState: host,
    statusComponent: statusHostComponent,
    centerComponent: centerHostComponent,
    audioComponent: audioHostComponent,
    networkComponent: networkHostComponent,
    catalogComponent: catalogHostComponent
  })

  Loader {
    id: barLoader
    active: true
    onLoaded: {
      host.events.push("bar-loaded:" + item.creationId)
      lifecycleTimer.restart()
    }
  }

  Timer {
    id: lifecycleTimer
    interval: 25
    repeat: true
    onTriggered: {
      if (phase === 0) {
        require(providerCreated === 4, "initial providers did not load")
        require(barLoader.item && barLoader.item.loadedOwners.length === 5,
          "initial owner sentinels missing")
        require(barLoader.item.clickTargets.length === 2,
          "status lifecycle child registration count="
            + barLoader.item.clickTargets.length + ":child="
            + !!currentProviders.status.lifecycleChild + ":bar="
            + !!currentProviders.status.lifecycleChild.bar + ":registered="
            + !!currentProviders.status.lifecycleChild.registeredBar)
        require(networkCreated === 1 && currentNetworkWidget
          && currentNetworkWidget.networkService === networkService
          && currentNetworkWidget.networkReady
          && currentNetworkWidget.mode === "wifi"
          && currentNetworkWidget.label === "Lifecycle Network"
          && currentNetworkWidget.signal === 77
          && currentNetworkWidget.downloadRate === 4096
          && currentNetworkWidget.uploadRate === 2048,
          "actual Network widget did not bind the controlled service")
        initialProviders = Object.assign({}, currentProviders)
        initialHelperCalls = helperMarks.length
        events.push("registry-update-live")
        registryRevision++
        phase++
        return
      }
      if (phase === 1) {
        require(helperMarks.length > initialHelperCalls,
          "live registry change did not reevaluate provider bindings")
        for (const kind of ["status", "center", "audio", "control-center"])
          require(currentProviders[kind] === initialProviders[kind],
            "live registry change replaced " + kind)
        slotRegion = "right"
        phase++
        return
      }
      if (phase === 2) {
        for (const kind of ["status", "center", "audio", "control-center"])
          require(currentProviders[kind] === initialProviders[kind],
            "slot move replaced " + kind)
        events.push("status-entry-enabled-false")
        statusEntryEnabled = false
        phase++
        return
      }
      if (phase === 3) {
        require(!currentProviders.status, "disabled status provider stayed live")
        require(barLoader.item.clickTargets.length === 1,
          "live Bar unload did not unregister the status lifecycle child")
        require(barLoader.item.loadedOwners.length === 4,
          "disabled provider owner sentinel was not released on destruction")
        const detachedIndex = events.indexOf(
          "provider-detached:status:owners=5")
        const destroyedIndex = events.indexOf("provider-destroyed:status")
        require(detachedIndex >= 0,
          "entry.enabled=false did not detach the resident Bar")
        require(destroyedIndex > detachedIndex,
          "entry.enabled=false destroyed the provider before Bar detach: "
            + JSON.stringify(events))
        statusEntryEnabled = true
        phase++
        return
      }
      if (phase === 4) {
        require(currentProviders.status
          && currentProviders.status !== initialProviders.status,
          "status provider did not reload")
        require(barLoader.item.loadedOwners.length === 5,
          "reloaded provider owner sentinel missing")
        require(barLoader.item.clickTargets.length === 2,
          "reloaded status lifecycle child did not register")
        oldBar = barLoader.item
        // The private staged widget makes this binding writable so the fixture
        // deterministically holds the incident's stale-ready intermediate state.
        currentNetworkWidget.networkReady = true
        events.push("host-reload-revoke")
        barLoader.active = false
        events.push("bar-loader-inactive")
        require(providerDetached >= 5,
          "resident providers were not detached synchronously: "
            + providerDetached + " " + JSON.stringify(events))
        require(networkBarRevoked === 1 && networkServiceRevoked === 1
          && networkRevokedWithReady,
          "Network service revoke did not expose the old ready state: "
            + JSON.stringify(events))
        events.push("registry-update-after-revoke")
        registryRevision++
        phase++
        return
      }
      if (phase === 5) {
        require(providerDestroyed >= 5,
          "old providers survived bar Loader teardown")
        const barDestructionIndex = events.indexOf("bar-destruction:1")
        const childDetachIndex = events.indexOf(
          "status-child-detached-during-bar-teardown")
        require(barDestructionIndex >= 0 && childDetachIndex > barDestructionIndex,
          "Bar teardown flag was not visible before Status revoke: "
            + JSON.stringify(events))
        require(ownerReleased >= 6,
          "owner sentinels released before actual item destruction")
        require(networkDestroyed === 1,
          "old Network widget survived bar Loader teardown")
        for (let index = 0; index < cachedCatalogs.length; index++) {
          const controller = cachedCatalogs[index]
          if (controller && controller.bar != null)
            fail("cached Control Center controller retained the old bar")
        }
        oldBar = null
        barLoader.active = true
        phase++
        return
      }
      if (phase === 6) {
        require(barLoader.item && barLoader.item.creationId === 2,
          "replacement bar did not load")
        require(barLoader.item.loadedOwners.length === 5,
          "replacement owner sentinels missing")
        require(networkCreated === 2 && currentNetworkWidget
          && currentNetworkWidget.networkService === networkService
          && currentNetworkWidget.networkReady,
          "replacement Network widget did not bind the controlled service")
        for (const kind of ["status", "center", "audio", "control-center"])
          require(currentProviders[kind]
            && currentProviders[kind].cachedBarSerial === 2,
            "provider did not attach to replacement bar: " + kind)
        events.push("registry-update-new-bar")
        registryRevision++
        phase++
        return
      }
      if (phase === 7) {
        lifecycleTimer.stop()
        console.log("BAR_CONTEXT_TIMING " + JSON.stringify(events))
        console.log("BAR_CONTEXT_COUNTS created=" + providerCreated
          + " destroyed=" + providerDestroyed
          + " detached=" + providerDetached
          + " ownersCreated=" + ownerCreated
          + " ownersReleased=" + ownerReleased
          + " helperCalls=" + helperMarks.length)
        console.log("bar context lifecycle regression passed")
        Qt.exit(0)
      }
    }
  }
}
