.pragma library

const StockBarId = "omarchy.bar"

function isScopedStockBarApi(bar) {
  return !!bar
    && "pluginId" in bar
    && "moduleName" in bar
    && "foreignPopoutMarker" in bar
    && !("barConfig" in bar)
    && !("manifest" in bar)
}

function activeBarId(bar) {
  if (!bar) return ""
  // Omarchy's built-in bar alone hosts third-party widgets through this
  // capability-scoped PluginBarApi. It remains authoritative even when a
  // configured custom bar failed to load and barConfig still names it.
  if (isScopedStockBarApi(bar)) return StockBarId

  const shell = bar.shell
  if (shell && shell.activeBarId !== undefined
      && shell.activeBarId !== null) {
    const hostId = String(shell.activeBarId || "")
    if (hostId !== "") return hostId
  }

  const manifest = bar.manifest
  if (manifest && manifest.id !== undefined && manifest.id !== null) {
    const manifestId = String(manifest.id || "")
    if (manifestId !== "") return manifestId
  }

  const config = bar.barConfig
  if (config && typeof config === "object")
    return String(config.id || StockBarId)

  return ""
}

function isStockOmarchyHost(bar) {
  return activeBarId(bar) === "omarchy.bar"
}

function shellName(bar) {
  return isStockOmarchyHost(bar) ? "omarchy" : "shibumi"
}
