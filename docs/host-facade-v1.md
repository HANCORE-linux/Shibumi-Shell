# Shibumi host facade V1

> **Document status: Normative supporting contract.** This document defines
> the versioned interface between feature plugins and selectable Shibumi bar
> hosts. `../ARCHITECTURE.md` remains authoritative for product behavior.

## Scope

Every Shibumi bar variant implements this facade on the object injected as
`bar` into Omarchy bar widgets. Feature plugins target this contract, not
`hancore.shibumi.bar` or any future bar implementation.

The machine-readable source is `contracts/host-facade-v1.json`.

This is the complete contract for Shibumi-owned bar hosts. It is broader than
Omarchy's standard Quattro bar-widget contract. A compatibility adapter lets
feature widgets run on the stock bar without claiming that the stock bar
implements Shibumi-only split, style, or layout-control methods. See
[cross-bar plugin compatibility](plugin-compatibility.md).

## Host Injection

Omarchy may assign `omarchyPath`, `shell`, `manifest`, `pluginRegistry`,
`barWidgetRegistry`, and `barConfig` after constructing a third-party bar.
Those properties remain optional at QML construction time. The bar exposes
`hostReady` only after every required injection is valid. The injected
`barConfig.transparent` field is stock-bar state, not a Shibumi input.

## Public Shibumi Surface

The facade includes:

- contract identity through `shibumiHostContractVersion == 1`;
- top/bottom position, orientation, bar size and output resolution;
- visual tokens, font and semantic foreground/background/urgent colors;
- tooltip and one-popout-at-a-time routing;
- screen-local sibling-panel navigation;
- registered Omarchy widget resolution and summon/hide routing;
- click-target registration required by transparent input masks; and
- host layout operations used by the Control Center.

Configuration and feature state are deliberately absent. Plugins read
`hancore.shibumi.state`, `hancore.shibumi.telemetry`,
`hancore.shibumi.power-state`, or their own service through
`bar.shell.serviceFor(pluginId)`.

## Omarchy Compatibility

`run(command)` remains on the selected bar for compatibility with official
Omarchy widgets. Shibumi feature plugins must not use it as a generic command
escape hatch. Platform actions belong to their owning feature service or an
official Omarchy contract.

The bar continues to expose the standard Omarchy color, font, position,
tooltip, shell and bar-widget-registry properties consumed by official
components. `requestedTransparent` and `transparent` remain on the facade with
fixed value `false`, and `setRequestedTransparency()` is a compatibility no-op.
This does not alter the host-owned preference: V1 and V2 always render opaque,
while switching back to `omarchy.bar` reactivates its saved value.
Compatibility is verified against the supported Quattro commit and the
validation system; it is not inferred from successful QML parsing.

## Internal State

Slot arrays, active popout, tooltip backing state and the layout controller are
bar internals. They may appear on the QML object but are not safe plugin APIs.
Feature plugins use the public methods instead.

The facade explicitly forbids feature owners such as `systemTelemetry`,
`powerService`, `networkService`, `pickerService`, `workspaceService`, and
`shibumiConfig`. Keeping those properties on a bar would couple every widget to
one implementation and duplicate services when the active bar changes.

## Panel And Output Rules

- The invoking widget determines the target output.
- A plugin panel never falls back to a global last-used output when its owner
  has a valid `QsWindow`.
- Opening one popout closes the previous popout on the same host.
- Sibling navigation stays within the same physical output.
- Top and bottom positioning use the same plugin panel implementation; the bar
  supplies direction and anchor context.
- Bar variants do not persist feature-panel open state.

## Settings Rules

- `hancore.shibumi.state` owns normalized Shibumi settings and persistence.
- The active bar owns layout mutation semantics such as split, reset, style and
  position.
- Shibumi never mutates or normalizes `bar.transparent`; lifecycle and migration
  operations preserve both an existing `true` and an existing `false`, and do
  not generate the field when it is absent.
- The Control Center calls facade methods for bar-host changes and state-service
  methods for feature settings.
- A feature plugin never mutates another feature plugin's settings.
- A bar switch must preserve the installed feature services and their state.

## Versioning

Adding an optional property or method does not change the version. Removing or
renaming a required member, changing its meaning, or changing output/panel
ownership requires a new host-facade version and an explicit compatibility
adapter.

`HostTokens.qml` and the standard registry-resolution fallback are that
adapter for non-Shibumi Quattro hosts. They don't expand or weaken this
contract.

## Acceptance

Before a bar plugin is eligible for a profile:

1. its manifest declares only `kinds: ["bar"]`;
2. the host injects it successfully with delayed property assignment;
3. the facade validator finds every required v1 member;
4. it contains none of the forbidden feature owners;
5. the stock compatibility widget smoke passes;
6. top/bottom, split, drag-and-drop and multi-output panel routing pass; and
7. switching to another compliant bar does not restart or duplicate feature
   services.
