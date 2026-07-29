.pragma library

function activeBarId(bar) {
  if (!bar) return ""

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
    return String(config.id || "omarchy.bar")

  return ""
}

function isStockOmarchyHost(bar) {
  return activeBarId(bar) === "omarchy.bar"
}

function shellName(bar) {
  return isStockOmarchyHost(bar) ? "omarchy" : "shibumi"
}
