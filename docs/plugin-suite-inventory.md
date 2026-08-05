# QS Rise Plugin Suite Inventory

> **Document status: Historical migration ledger.** This document records the
> ownership inventory used to extract the independent plugin suite. Current
> manifests, source, and `release-readiness.md` supersede transitional status.

## Purpose

This inventory freezes the ownership of the current combined V2 scaffold before
runtime files are moved. It is the implementation ledger for Phases A through D
of `plugin-suite-migration-plan.md`.

The current root tree is not the release layout. Its root manifest still
combines a bar, menu, bar widget, and service as a migration scaffold. The
active `Bar.qml` has already been reduced to a registry/service-only host: all
fixed G1-G15 features and their state owners now load from independent plugin
entry points. Phase E must package the remaining root-owned bar files into the
self-contained bar plugin and exclude the combined manifest from release.

## Verified Runtime Rules

- Omarchy Quattro loads one third-party plugin from each direct child of
  `~/.config/omarchy/plugins/`.
- Each child has one `manifest.json`; every entry point must remain inside that
  plugin directory.
- An enabled third-party `service` is available through
  `shell.serviceFor(pluginId)`.
- An enabled `bar-widget` is registered under its manifest ID.
- Only one `bar` plugin is selected at a time.
- Omarchy does not currently enforce third-party dependency metadata.
- Runtime imports across sibling plugin directories are therefore prohibited.

## Target Plugin Set

The following IDs are the target ownership boundaries. A plugin directory is
created only when its complete runtime slice is ready to move.

| Plugin ID | Kinds | Owns | Required QS Rise dependencies |
| --- | --- | --- | --- |
| `hancore.qsrise.bar` | `bar` | Output windows, top/bottom geometry, G1-G15 composition, split state, drag-and-drop, panel/tooltip routing, style host | `state`; feature plugins are profile requirements, not runtime imports |
| `hancore.qsrise.state` | `service` | Normalized `bar.qsrise` configuration, theme palette, versioned state mutation API | none |
| `hancore.qsrise.control-center` | `bar-widget` | G1 wordmark/icon and complete QS Rise bar settings panel | `state` |
| `hancore.qsrise.menu` | `menu`, `service` | Application/command menu, app index, favorites, menu-only settings and actions | `state` |
| `hancore.qsrise.reactor` | `service` | Optional Reactor/quote event state; no bar layout ownership | `state` |
| `hancore.qsrise.telemetry` | `service` | One CPU/RAM `/proc` sampler shared by every output and bar variant | none |
| `hancore.qsrise.power-state` | `service` | One UPower/profile model and profile actions | none |
| `hancore.qsrise.workspaces` | `bar-widget`, `service` | Workspace model, preferences, actions, widget and panel | `state` |
| `hancore.qsrise.status` | `bar-widget`, `service` | G3 tray/notification composition and status adapter | `state`; official tray/notification owners |
| `hancore.qsrise.update-center` | `bar-widget`, `service` | G3 package/theme update state, manual checks, and delegated apply actions | official Omarchy update/theme commands |
| `hancore.qsrise.memory` | `bar-widget` | G4 memory widget and panel | `telemetry` |
| `hancore.qsrise.cpu` | `bar-widget`, `service` | G5 CPU widget/panel and one GPU sampler | `telemetry` |
| `hancore.qsrise.audio` | `bar-widget` | G6 audio widget, meter and mixer panel | official `omarchy.audio` and `omarchy.media` |
| `hancore.qsrise.ai` | `bar-widget`, `service` | G7 provider state, widget, panel and OpenCode helper | `state` |
| `hancore.qsrise.center` | `bar-widget`, `service` | G8 weather, clock, calendar, indicators and Omarchy update presentation | `state`; Quattro weather-location state and official idle/notification/update owners |
| `hancore.qsrise.media` | `bar-widget` | G9 media widget and detail panel | official `omarchy.media` |
| `hancore.qsrise.quick-access` | `bar-widget`, `service` | G10 idle inhibitor, picker controller, picker overlay and media/image helpers | `state`; official background/theme actions |
| `hancore.qsrise.network` | `bar-widget`, `service` | G11 network model, actions, widget and panel | official `omarchy.network` |
| `hancore.qsrise.battery` | `bar-widget` | G12 battery widget and panel | `power-state` |
| `hancore.qsrise.brightness` | `bar-widget`, `service` | G13 monitor model, actions, widget and panel | official `omarchy.monitor` |
| `hancore.qsrise.power-profile` | `bar-widget` | G14 profile widget and panel | `power-state` |
| `hancore.qsrise.bluetooth` | `bar-widget`, `service` | G15 Bluetooth model, actions, widget and panel | Quickshell Bluetooth/PipeWire; validated Omarchy device/audio helper commands |

`hancore.qsrise.notifications` and `hancore.qsrise.osd` are reserved future
replacement IDs. They are not part of the initial profile because Quattro
already owns those services and duplicate ownership would be unsafe.

## Current File Ownership

### Bar host

Target: `hancore.qsrise.bar`

```text
Bar.qml
core/BarPanel.qml
core/BarSection.qml
core/CenterSection.qml
core/DragSession.qml
core/GroupRegistry.js
core/GroupSlot.qml
core/LayoutController.qml
core/LayoutModel.js
core/PanelRouting.js
core/RunGeometry.js
core/WidgetSlot.qml
core/WindowRecovery.qml
services/HostWidgetResolver.qml
styles/StyleRegistry.qml
styles/qsrise/BarSurface.qml
styles/qsrise/DragGhost.qml
styles/qsrise/GapEffectsLayer.qml
styles/qsrise/GroupSection.qml
styles/qsrise/ReactorEventLayer.qml
styles/qsrise/RunChrome.qml
styles/qsrise/Style.qml
styles/qsrise/TooltipSurface.qml
styles/qsrise/VisualTokens.qml
```

`ReactorEventLayer.qml` remains a bar-owned renderer, but consumes the separate
Reactor service. The bar must not instantiate `ReactorService` or `QuoteService`.

### Shared state

Target: `hancore.qsrise.state`

```text
core/QsRiseConfig.js
services/ThemePalette.qml
services/ThemePaletteModel.js
```

The service becomes the only writer of `bar.qsrise`. Plugins consume a narrow
state API through `shell.serviceFor("hancore.qsrise.state")`; they do not import
`QsRiseConfig.js` from another plugin.

### Control Center

Target: `hancore.qsrise.control-center`

```text
hancore.shibumi.control-center/BarWidget.qml
hancore.shibumi.control-center/ControlCenterPanel.qml
assets/arch-header-arch.png
assets/arch-header-linux.png
assets/bob2.png
assets/bob3.png
assets/omacom-text.png
assets/logo-tint.frag.qsb
```

The extracted G1 widget opens only the Control Center. Omarchy owns the
application launcher menu.

### Application Menu

Retired from Shibumi. Omarchy is the sole application-menu owner. The former
prototype sources, manifest, service, workers, settings, and dedicated tests
are intentionally absent from the current tree.

### Reactor

Target: `hancore.qsrise.reactor`

```text
services/QuoteDefaults.js
services/QuoteService.qml
services/ReactorModel.js
services/ReactorService.qml
```

This service may observe official media, notification, power and workspace
services. It publishes event state to any compatible QS Rise bar through the
host facade and may not retain direct references to a specific bar's slots.

### Telemetry

Target: `hancore.qsrise.telemetry`

```text
services/SystemTelemetry.qml
```

`services/GpuTelemetry.qml` belongs to the CPU plugin because memory does not
consume it. System actions are shared helpers, not telemetry state.

### Power state

Target: `hancore.qsrise.power-state`

```text
services/PowerModel.js
services/PowerService.qml
```

This prevents G12 and G14, multiple outputs, or future bar variants from
creating competing UPower/profile owners.

### G2 Workspaces

Target: `hancore.qsrise.workspaces`

```text
adapters/WorkspaceActions.qml
services/WorkspaceModel.js
services/WorkspaceService.qml
widgets/WorkspacePanel.qml
widgets/WorkspacePanelContent.qml
widgets/WorkspaceWidget.qml
```

### G3 Status

Target: `hancore.qsrise.status`

```text
services/StatusService.qml
widgets/NotificationPanel.qml
widgets/NotificationStatusView.qml
widgets/StatusWidget.qml
widgets/TrayDrawerPanel.qml
widgets/TrayStatusView.qml
```

The official notification and tray plugins remain authoritative. This plugin
owns QS Rise composition, interaction routing, and V1-faithful presentation
over those service owners.

### G4 Memory

Target: `hancore.qsrise.memory`

```text
widgets/MemoryPanel.qml
widgets/MemoryRing.qml
widgets/MemoryWidget.qml
```

### G5 CPU

Target: `hancore.qsrise.cpu`

```text
services/GpuTelemetry.qml
widgets/CpuPanel.qml
widgets/CpuWave.qml
widgets/CpuWidget.qml
```

### G6 Audio

Target: `hancore.qsrise.audio`

```text
adapters/AudioPanelBridge.qml
widgets/AudioPanel.qml
widgets/AudioWidget.qml
```

### G7 AI usage

Target: `hancore.qsrise.ai`

```text
assets/codex.svg
assets/opencode-mark.svg
scripts/opencode-usage
services/AiUsageService.qml
services/OpenCodeProvider.qml
widgets/AiUsagePanel.qml
widgets/AiUsageWidget.qml
```

The current import from `widgets/AiUsageWidget.qml` into `menu/` is only for a
visual helper and must be replaced with a plugin-local vendored primitive.

### G8 Center

Target: `hancore.qsrise.center`

```text
services/ClockService.qml
services/WeatherService.qml
widgets/CalendarModel.js
widgets/CalendarPanel.qml
widgets/CenterLayout.js
widgets/CenterWidget.qml
widgets/ClockWidget.qml
widgets/StatusIndicators.qml
widgets/SystemUpdateWidget.qml
widgets/WeatherPanel.qml
widgets/WeatherWidget.qml
```

`ClockWidget.qml` remains an internal Center component unless a later product
decision introduces a separately selectable QS Rise clock plugin.

### G9 Media

Target: `hancore.qsrise.media`

```text
widgets/MediaPanel.qml
widgets/MediaPulse.qml
widgets/MediaSpectrum.qml
widgets/MediaWidget.qml
```

### G10 Quick access and picker

Target: `hancore.qsrise.quick-access`

```text
scripts/qsrise-picker
services/PickerModel.js
services/PickerService.qml
widgets/HearthstonePickerView.qml
widgets/PickerImage.qml
widgets/PickerOverlay.qml
widgets/QuickAccessWidget.qml
widgets/TanzakuPickerView.qml
```

The singleton service owns IPC, worker lifecycle and the overlay. Per-output
bar widgets only summon it with an explicit target screen.

### G11 Network

Target: `hancore.qsrise.network`

```text
adapters/NetworkPanelBridge.qml
services/NetworkService.qml
widgets/NetworkPanel.qml
widgets/NetworkWidget.qml
```

### G12 Battery

Target: `hancore.qsrise.battery`

```text
widgets/BatteryPanel.qml
widgets/BatteryWidget.qml
```

### G13 Brightness

Target: `hancore.qsrise.brightness`

```text
adapters/MonitorPanelBridge.qml
services/MonitorService.qml
widgets/BrightnessPanel.qml
widgets/BrightnessWidget.qml
```

### G14 Power profile

Target: `hancore.qsrise.power-profile`

```text
widgets/PowerProfilePanel.qml
widgets/PowerProfileWidget.qml
```

The direct import of `services/PowerModel.js` is replaced with the
`power-state` service contract.

### G15 Bluetooth

Target: `hancore.qsrise.bluetooth`

```text
adapters/BluetoothBackendAdapter.qml
adapters/BluetoothModel.js
services/BluetoothService.qml
widgets/BluetoothPanel.qml
widgets/BluetoothWidget.qml
```

### Vendored shared primitives

Canonical development owner: `shared/`

```text
adapters/SystemActions.qml
widgets/IconText.qml
widgets/PillSurface.qml
widgets/QsRisePanel.qml
```

These are small host-neutral helpers used by several feature plugins. Reviewed
copies are vendored into each consuming plugin and checked byte-for-byte by the
sync test. They are not runtime plugins and are never imported from `shared/`.

### Transitional files

```text
manifest.json                              combined root manifest; delete after
                                          independent manifests exist
widgets/WidgetRegistry.qml                 internal component switch; replace
                                          with Omarchy's BarWidgetRegistry
```

The root `README.md`, `ARCHITECTURE.md`, `LICENSE`, `config/`, `docs/`, and
repository scripts remain repository-level development and distribution files.
`styles/README.md` moves into the bar plugin's developer documentation; it is
not installed as a runtime dependency.

## Test Ownership

Tests move with their owning plugin while repository-wide contract tests stay at
the root. Paths in the table are relative to `tests/`.

| Owner | Current tests |
| --- | --- |
| Repository/installer | `contract-regression.sh`, future manifest/dependency/self-containment/install/rollback tests |
| Bar | `group-interaction-regression.qml`, `group-registry-regression.qml`, `group-renderer-regression.qml`, `host-widget-resolver-regression.qml`, `layout-controller-regression.qml`, `layout-model-regression.qml`, `panel-routing-regression.qml`, `qsrise-presentation-smoke.qml`, `reactor-renderer-regression.qml`, `run-geometry-regression.qml`, `style-contract-regression.sh`, `fixtures/ResolverTestWidget.qml` |
| State | `qsrise-config-regression.qml`, `theme-palette-model-regression.qml` |
| Reactor | `quote-service-smoke.qml`, `reactor-model-regression.qml` |
| Workspaces | `workspace-model-regression.qml`, `workspace-panel-smoke.qml`, `workspace-widget-smoke.qml`, `fixtures/WorkspaceTestPanel.qml` |
| Status | `status-widget-smoke.qml`, `fixtures/StatusTestWidget.qml`, `fixtures/TrayDrawerTestPanel.qml` |
| Memory | `memory-widget-smoke.qml` |
| Audio | `audio-widget-smoke.qml`, `fixtures/AudioTestPanel.qml`, `fixtures/AudioTestView.qml` |
| AI | `ai-usage-widget-smoke.qml`, `fixtures/AiTestPanel.qml` |
| Center | `center-model-regression.qml`, `center-widget-smoke.qml`, `clock-widget-smoke.qml`, `fixtures/CenterTestCalendar.qml` |
| Media | `media-widget-smoke.qml`, `fixtures/MediaTestPanel.qml` |
| Quick access | `picker-helper-regression.sh`, `picker-model-regression.qml` |
| Network | `network-widget-smoke.qml`, `fixtures/NetworkTestService.qml`, `fixtures/NetworkTestView.qml` |
| Power state/Battery/Profile | `power-service-live-probe.qml`, `power-service-runtime-smoke.qml`, `power-widgets-smoke.qml`, `fixtures/PowerTestPanel.qml`, `fixtures/PowerTestService.qml`, `fixtures/power-bin/*` |
| Brightness | `brightness-widget-smoke.qml`, `fixtures/MonitorTestPanel.qml`, `fixtures/MonitorTestView.qml` |
| Bluetooth | `bluetooth-widget-smoke.qml`, `bluetooth-ipc-ownership-regression.sh`, `fixtures/BluetoothTestBackend.qml`, `fixtures/BluetoothTestView.qml` |
| Shared panel primitives | `panel-surface-smoke.qml` |

Missing focused CPU, picker-overlay, and multi-bar reuse tests must be added
before their slices are declared complete. Focused State, Control Center,
telemetry, and power-state contract/runtime tests now exist.

## Cross-Boundary Blockers

1. **Combined manifest:** resolved by deleting the combined prototype and
   leaving Omarchy as the sole application-menu owner.
2. **Internal registry:** `WidgetRegistry.qml` hardcodes QS Rise widget
   components, bypassing Omarchy's independently enabled widget registry.
3. **Bar-owned feature services:** `Bar.qml` creates telemetry, power, AI,
   picker, Reactor, workspace, network, monitor and Bluetooth state. A second bar
   would duplicate or destroy them during a bar switch.
4. **Unversioned host object:** widgets consume dozens of ad-hoc `bar.*`
   properties and methods. The supported subset needs a versioned host facade
   and contract test.
5. **Direct sibling imports:** power model, adapters, style
   core helpers and AI visual helpers currently cross future plugin boundaries.
6. **Mixed settings surface:** resolved by moving Shibumi settings to the
   Control Center and deleting the former menu surface.
7. **Bar-specific Reactor coupling:** Reactor reads `bar.moduleSlots` and several
   bar-owned services. It must consume service contracts and publish events,
   while the selected bar owns rendering.
8. **Root-relative helpers and assets:** scripts and assets resolve through the
   combined source tree. Each plugin must resolve only manifest-local payloads.
9. **Tests assume one source tree:** several fixtures import root `services/`,
   `widgets/`, `menu/` or `core/`. They need plugin-local smoke entry points plus
   repository-wide contract tests.

## Extraction Order

The safest order preserves runtime behavior while removing ownership from the
bar incrementally:

1. add `state`, host-facade v1, vendoring and self-containment checks;
2. add `telemetry` and `power-state` services;
3. separate the Control Center and retire the Shibumi application menu without
   changing G1 visually;
4. extract Memory and CPU as the first low-action widget proof;
5. extract Media and Audio using official services;
6. extract Workspaces, Status and Center with multi-output lifecycle tests;
7. extract Network, Brightness and Bluetooth with the validation system mutation tests;
8. extract Battery and Power Profile over the shared power service;
9. extract AI, Quick Access and Reactor with process/cache/IPC cleanup gates;
10. move the now feature-free bar host and replace `WidgetRegistry` with host
    registry lookup;
11. implement transactional suite install/update/uninstall;
12. close V1 parity, then add a second bar host without modifying any feature
    plugin.

Current extraction status (2026-07-19): steps 1 through 11 are implemented.
The active bar is registry/service-only; every G1-G15 feature, Update Center,
shared state, telemetry, power state, and Reactor owner loads from an
independently validated plugin. The 24-plugin profile passes the fresh Quattro
contract suite, isolated transactional lifecycle tests, and a real 21-to-22
the validation system update. Remaining work is release acceptance rather than another
ownership extraction; see `release-readiness.md`.

## Exit Criteria For Inventory Phase

- every current runtime file has one target owner or is marked transitional;
- no feature service remains intentionally owned by a bar variant;
- G1 Control Center remains separate from Omarchy's application menu;
- common code has a vendoring owner rather than a sibling runtime import;
- target IDs and dependencies are stable enough to scaffold manifests; and
- no runtime file has been moved before these contracts are tested.
