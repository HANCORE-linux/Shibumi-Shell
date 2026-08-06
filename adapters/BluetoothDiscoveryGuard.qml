pragma Singleton

import QtQuick

QtObject {
  id: root

  readonly property int initialRetryInterval: 250
  readonly property int maximumRetryInterval: 4000
  readonly property int settledStopInterval: 100
  property var guards: []

  function guardIndex(adapter) {
    for (let index = 0; index < guards.length; index++)
      if (guards[index].adapter === adapter) return index
    return -1
  }

  function isArmed(adapter) {
    return guardIndex(adapter) >= 0
  }

  function guardCount() {
    return guards.length
  }

  function removeGuard(entry) {
    if (!entry) return
    const index = guards.indexOf(entry)
    if (index < 0) return
    guards.splice(index, 1)
    const adapter = entry.adapter
    entry.adapter = null
    if (adapter) {
      try {
        adapter.discoveringChanged.disconnect(entry.handler)
      } catch (_error) {
        // The native adapter may disappear with the QML engine. There is then
        // no BlueZ session left for this guard to reconcile.
      }
    }
    const timer = entry.retryTimer
    entry.retryTimer = null
    if (timer) timer.destroy()
    const watcher = entry.adapterWatcher
    entry.adapterWatcher = null
    if (watcher) {
      watcher.armed = false
      watcher.destroy()
    }
  }

  function disarm(adapter) {
    const index = guardIndex(adapter)
    if (index < 0) return false
    removeGuard(guards[index])
    return true
  }

  function adapterDestroyed(entry) {
    if (!entry || guards.indexOf(entry) < 0) return
    entry.adapter = null
    entry.adapterWatcher = null
    removeGuard(entry)
  }

  function schedule(entry, interval) {
    if (!entry || guards.indexOf(entry) < 0) return
    const remaining = entry.expiresAt - Date.now()
    if (remaining <= 0) {
      removeGuard(entry)
      return
    }
    entry.retryTimer.interval = Math.max(1, Math.min(interval, remaining))
    entry.retryTimer.restart()
  }

  function reconcile(entry) {
    if (!entry || guards.indexOf(entry) < 0) return
    if (Date.now() >= entry.expiresAt) {
      removeGuard(entry)
      return
    }
    const adapter = entry.adapter
    if (!adapter) {
      removeGuard(entry)
      return
    }
    let discovering = false
    try {
      discovering = !!adapter.discovering
    } catch (_error) {
      entry.adapter = null
      removeGuard(entry)
      return
    }
    if (discovering) {
      entry.stopRequested = true
      entry.stopSettlePending = false
      try {
        adapter.discovering = false
        discovering = !!adapter.discovering
      } catch (_error) {
        entry.adapter = null
        removeGuard(entry)
        return
      }
      const retryInterval = entry.retryInterval
      entry.retryInterval = Math.min(maximumRetryInterval, retryInterval * 2)
      schedule(entry, discovering ? retryInterval : settledStopInterval)
    } else if (entry.stopRequested) {
      // StopDiscovery is asynchronous. Require the stopped state to survive a
      // later event-loop turn before releasing the guard.
      if (entry.stopSettlePending) removeGuard(entry)
      else {
        entry.stopSettlePending = true
        schedule(entry, settledStopInterval)
      }
    } else {
      // No delayed start has arrived yet. The signal handles it immediately;
      // this wakeup exists only to enforce the hard deadline.
      schedule(entry, entry.expiresAt - Date.now())
    }
  }

  function arm(adapter, timeoutMs) {
    if (!adapter || adapter.discovering === undefined
        || !adapter.discoveringChanged) return false
    disarm(adapter)

    const requestedInterval = Number(timeoutMs)
    const interval = isFinite(requestedInterval) && requestedInterval > 0
      ? requestedInterval : 30000
    const entry = {
      "adapter": adapter,
      "expiresAt": Date.now() + interval,
      "stopRequested": false,
      "stopSettlePending": false,
      "retryInterval": initialRetryInterval,
      "handler": null,
      "destroyedHandler": null,
      "retryTimer": null,
      "adapterWatcher": null
    }
    entry.handler = function() { root.reconcile(entry) }
    entry.destroyedHandler = function() { root.adapterDestroyed(entry) }
    entry.retryTimer = Qt.createQmlObject(
      'import QtQuick; Timer { running: false; repeat: false }',
      root,
      "ShibumiBluetoothDiscoveryGuardTimer"
    )
    entry.adapterWatcher = Qt.createQmlObject(
      'import QtQuick; QtObject {'
        + ' property bool armed: true; signal watchedDestroyed();'
        + ' Component.onDestruction: if (armed) watchedDestroyed() }',
      adapter,
      "ShibumiBluetoothDiscoveryAdapterWatcher"
    )
    entry.adapterWatcher.watchedDestroyed.connect(entry.destroyedHandler)
    entry.retryTimer.triggered.connect(function() { root.reconcile(entry) })
    guards.push(entry)
    adapter.discoveringChanged.connect(entry.handler)
    reconcile(entry)
    return true
  }
}
