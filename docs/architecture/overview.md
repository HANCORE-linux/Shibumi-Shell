# Architecture overview

Status: reference

The canonical product and architecture contract is
[`../../ARCHITECTURE.md`](../../ARCHITECTURE.md). This page is a short runtime
map; it does not redefine that contract.

## Runtime shape

Shibumi is a suite of 24 native Omarchy plugins loaded into the existing
Omarchy Shell process.

- `hancore.shibumi.bar` is the selectable full-bar host.
- `hancore.shibumi.state` owns validated Shibumi configuration.
- `hancore.shibumi.control-center` owns the G1 configuration surface.
- Omarchy remains the sole owner of the application launcher menu; Shibumi
  registers no `menu` entry point or application-menu service.
- `hancore.shibumi.reactor`, telemetry, power-state, and update-center services
  provide shared process-wide state.
- Feature plugins own their widget, panel, and narrow service adapters.
- Quattro and Quickshell remain authoritative for platform capabilities they
  already expose.

No plugin starts a second `ShellRoot` or Quickshell process.

## Host and feature boundary

The bar host owns:

- one bar window per valid output;
- layout, grouping, split, drag, tooltip, and panel routing;
- the versioned host facade used by feature plugins;
- bar presentation tokens and style selection.

Feature plugins own:

- their user-visible widget and panel;
- feature-specific presentation and transient UI state;
- validated actions that are not already owned by Quattro;
- cleanup when a panel closes or an output disappears.

Adding another Shibumi bar means adding another host implementation behind the
same facade. It must reuse the existing feature plugins and state owners.

## State and lifecycle

Omarchy's `shell.json` is the persistent user configuration. Shibumi's state
service normalizes `bar.shibumi`, while the suite adapter owns installation
metadata and transactional recovery.

One popout owner is active at a time for a bar context. Panels follow the
invoking widget and output, close when the bar is hidden for an idle or
screensaver transition, and release UI-only workers when closed.

Output hotplug, scale changes, DPMS, suspend, resume, and bar-host switching
must not leave duplicate windows, stale anchors, or orphan owners.

## Compatibility boundary

The supported host contract is checked against the exact package versions and
host-file hashes in the
[Shibumi host compatibility record](quattro-compatibility.md). Missing
stable host APIs and their bounded workarounds are tracked in
[Quattro contract gaps](../omarchy-quattro-contract-gaps.md).

The exact facade is machine-readable in
[`../../contracts/host-facade-v1.json`](../../contracts/host-facade-v1.json).
