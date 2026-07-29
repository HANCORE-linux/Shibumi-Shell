# Bar Style Contract

> **Document status: Normative supporting contract.** This file defines how a
> selectable bar presentation may extend Shibumi without duplicating feature
> ownership. `../ARCHITECTURE.md` remains authoritative.

A bar style is a presentation package, not a second implementation of Shibumi.
Adding a style must not copy services, widget behavior, panel state, output
lifecycle, split logic, drag-and-drop, or persistence.

Each production style lives under `styles/<id>/` and provides:

```text
Style.qml
BarSurface.qml
TooltipSurface.qml
```

`Style.qml` implements contract version 1 and exposes:

```text
styleId
displayName
sizeHorizontal
sizeVertical
tooltipGap
colorTransitionDuration
fontFamily
foreground
barForeground
background
urgent
exclusiveSizeHorizontal
visualTokens
barSurfaceComponent
tooltipSurfaceComponent
```

The style root receives the shared `bar` facade. Surfaces may render shared
widgets and components through that facade, but they must not own a
`PanelWindow`, `Variants`, `Process`, service singleton, or host configuration
writer.

`visualTokens` is the presentation contract consumed by shared widget views.
It owns density, typography, pill/chrome geometry, motion durations, and
theme-derived colors. Runtime services and widget behavior must not depend on
the active style.

To add a style:

1. Add its directory and the three contract files.
2. Register its id, display name, and `Style.qml` source in
   `StyleRegistry.qml`.
3. Run `tests/style-contract-regression.sh` and the normal contract suite.
4. Execute the full position, scaling, multi-monitor, panel, and lifecycle
   matrix for the new style.

Unknown configured style ids resolve to `shibumi`. Only the active style is
loaded.
