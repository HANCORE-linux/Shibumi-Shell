# Omarchy Quattro Contract Gaps For Third-Party Shell Suites

> **Document status: External dependency register.** This document records
> verified host gaps and bounded workarounds. It does not relax the Shibumi
> product or release contract in `../ARCHITECTURE.md`.

## Purpose

This register records host contracts that Shibumi cannot currently consume from
Omarchy Quattro without duplicating state, loading a presentation component as
a backend, or maintaining repository-specific lifecycle tooling.

It is intended as constructive alpha feedback, not as a requirement that
Omarchy adopt Shibumi internals. Quattro already provides the important
foundation: schema-validated plugins, generic `bar`, `bar-widget`, `service`,
`panel`, `overlay`, and `menu` loaders, `serviceFor()`, a shared widget registry,
and safe fallback to the stock bar.

Initially verified against `basecamp/omarchy` branch `quattro` at commit
[`4a02da20d58d912a74748845bc55b5ec73acd65f`](https://github.com/basecamp/omarchy/tree/4a02da20d58d912a74748845bc55b5ec73acd65f)
on 2026-07-22.
the validation system was updated and the register revalidated against
[`1b6ab15331bfc88eb66746021d9e32c976ed438a`](https://github.com/basecamp/omarchy/tree/1b6ab15331bfc88eb66746021d9e32c976ed438a)
and package `4.0.0.r1242.g1b6ab15-1` on 2026-07-23. This matches the protected
online head checked that day. The newer code does not change the plugin
registry, installer, manifest, selector, or bar-loader gaps recorded below.
Its compatible Network, Weather, Tray, and Notification changes pass the
complete Shibumi suite and focused real-session checks. Pinned `4a02da2` links
remain exact source evidence for the originally audited contracts.

Revalidated again on 2026-07-27 against online Quattro commit
[`e55f130d55c8f9e5b7b6074c20225f5222ca063c`](https://github.com/basecamp/omarchy/tree/e55f130d55c8f9e5b7b6074c20225f5222ca063c).
the validation system then ran package `4.0.0.r1423.gc1647fa-1` at `c1647fab`; the only checked
source commit after that packaged revision changes the Edge glyph. Quattro
commit `fc4caf3c` removed the notification bar-widget entry point and retained
`omarchy.notifications` as a presentation-neutral service. Shibumi now consumes
that service directly, which partially resolves QTR-005/QTR-006 for
notifications. Quattro's enterprise Wi-Fi path is also available on the validation system;
Shibumi delegates identity and password to its official `connectEnterprise`
action and does not add a second NetworkManager owner.

Revalidated on 2026-07-28 against current online Quattro head
[`f4e8470c3a1becd01164e4787b23f6ce09460b57`](https://github.com/basecamp/omarchy/tree/f4e8470c3a1becd01164e4787b23f6ce09460b57).
That head was six commits ahead of the validation system's packaged `c1647fab` source. The
host-relevant change removes the short-lived `omarchy.tmux` service,
`TmuxAlert` indicator, and associated manifest option; Shibumi has no reference
to that service or indicator and its 24 independently validated plugins pass
the current host contract. The remaining commits concern update conflict
recovery, migration notification, mise failure handling, and an Edge glyph;
they do not change the plugin registry, manifest schema, bar loader, service
injection, or third-party discovery contracts used by Shibumi.

Revalidated on 2026-07-29 against the validation system package
`4.0.0.r1441.g9174fbf-1`. The current `PluginRegistry.qml` discovers and
enables plugins but exposes no repository update contract. Shibumi therefore
retains its transactional `shibumi-suite` source updater. The current registry,
manifest, bar loader, service injection, and third-party discovery contracts
pass the complete 24-plugin regression.

Reviewed on 2026-07-30 against upstream commit
[`09b955dc751c4282e893dc753788f335b0dcae57`](https://github.com/basecamp/omarchy/commit/09b955dc751c4282e893dc753788f335b0dcae57).
The new Setup > Plugins menu adds generic enable, disable, and remove actions
and a `barWidget.defaultSection` placement hint. the validation system's packaged
`4.0.0.r1441.g9174fbf-1` does not yet contain that menu. The change improves
single-plugin management but does not add suite, dependency, or external
lifecycle ownership metadata: every Shibumi root is still shown as an
independently removable third-party plugin, and selecting a full bar changes
`bar.id` without Shibumi's per-bar continuity transaction. Shibumi now declares
and validates every widget's default section, keeps suite-internal helpers out
of its own free-toggle catalog, and provides `shibumi-suite repair` for an
accidental partial removal. QTR-001 and QTR-002 remain open.

the validation system then updated to package `4.0.0.r1458.gfa6b5fc-1`, which contains this
menu. All 24 manifests and the complete Shibumi contract pass. A real
individual disable of `hancore.shibumi.bluetooth` was detected as profile
drift and repaired transactionally. The live test also confirmed a mixed-kind
edge case: when a third-party plugin is both `bar-widget` and `service`, is
present only in `plugins[]`, and absent from the bar, `list --json` reports the
widget disabled but `enable` finds the existing service entry and does not add
the widget. Shibumi's service-only Update Center intentionally occupies that
state, so its suite verification distinguishes discovery/service activation
from the host's widget-enabled flag.

Priority meanings:

- **P0**: blocks a clean, native third-party plugin suite or safe provider
  replacement.
- **P1**: forces duplicated backends, hidden panel instances, or unstable
  coupling to first-party implementation details.
- **P2**: useful contract hardening; Shibumi has a bounded workaround.

## Summary

| ID | Priority | Requested host contract | Current Shibumi impact |
| --- | --- | --- | --- |
| QTR-001 | P0 | Multi-plugin repository and lifecycle source | One release needs a custom transactional installer, updater, repair path, and remover. |
| QTR-002 | P0 | Enforced dependencies and service readiness | Shibumi must resolve, order, and protect dependencies itself. |
| QTR-003 | P0 | Configurable default menu provider | Standard Omarchy menu commands remain hard-coded to `omarchy.menu`. |
| QTR-004 | P0 | Exclusive capability providers | Notification/OSD replacement can create duplicate global owners. |
| QTR-005 | P1 | Presentation-neutral first-party services | Alternative views must instantiate stock panels as hidden backends. |
| QTR-006 | P1 | Reusable status/data services for stock widgets | Update, indicator, AI, and tray policy are coupled to widget instances. |
| QTR-007 | P1 | Structured background/theme discovery | Custom pickers must know Omarchy state and background directory layout. |
| QTR-008 | P1 | Standard invocation/output context | Plugins must infer the target monitor and originating bar instance. |
| QTR-009 | P2 | Versioned bar-host capability contract | Stock widget compatibility with third-party bars is implicit. |
| QTR-010 | P1 | Exact-code plugin reload after an in-place update | Rescan can recreate unchanged URLs from cached QML while the new files and digest are already visible. |

## QTR-001: Multi-Plugin Repository Sources

**Current behavior**

`omarchy plugin add` defines a plugin as one Git repository, validates one root
`manifest.json`, and installs it into one directory named after that manifest
ID. Third-party discovery scans only direct children of
`~/.config/omarchy/plugins/`. The generic Setup > Plugins menu also enables,
disables, or removes one discovered root at a time; it has no externally
managed bundle marker.

Evidence:

- [`bin/omarchy-plugin-add`](https://github.com/basecamp/omarchy/blob/f54edbe/bin/omarchy-plugin-add)
- [`PluginRegistry.qml`, third-party scan depth](https://github.com/basecamp/omarchy/blob/4a02da20d58d912a74748845bc55b5ec73acd65f/shell/services/PluginRegistry.qml#L296-L319)
- [`bin/omarchy-menu-plugin`, generic per-root actions](https://github.com/basecamp/omarchy/blob/09b955dc751c4282e893dc753788f335b0dcae57/bin/omarchy-menu-plugin)

**Impact**

Shibumi is intentionally one repository containing multiple independently
selectable bars, widgets, panels, menus, and singleton services. Installing the
repository as one giant plugin would destroy those ownership boundaries. Until
the host supports suites, Shibumi must maintain its own staging, validation,
update, rollback, profile, and uninstall layer.

**Minimal proposed contract**

- A repository root may contain an explicit suite index, for example
  `omarchy-plugin-suite.json`.
- The index lists plugin directories and optional install profiles.
- A plugin may declare an externally managed suite and the host delegates
  suite-level enable, disable, repair, and remove actions to that owner.
- `omarchy plugin add/update/remove` validates and mutates the selected set as
  one transaction.
- Partial failure restores every affected plugin and the previous
  `shell.json`.
- The user still reviews one repository revision before enabling its code.

**Acceptance proof**

Install two services, two widgets, one menu, and one bar from one repository;
make the second widget fail validation; prove that no plugin or configuration
from the attempted revision becomes visible.

## QTR-002: Dependencies, Activation Order, And Readiness

**Current behavior**

Manifest validation checks identity, kinds, and safe entry points, but does not
validate or enforce dependency metadata. `_syncServices()` iterates enabled
services without a dependency graph. `ensureService()` may return `null` while
an asynchronous component is still loading.

Evidence:

- [`PluginRegistry.validateManifest()`](https://github.com/basecamp/omarchy/blob/4a02da20d58d912a74748845bc55b5ec73acd65f/shell/services/PluginRegistry.qml#L41-L80)
- [`ensureService()` and `_syncServices()`](https://github.com/basecamp/omarchy/blob/4a02da20d58d912a74748845bc55b5ec73acd65f/shell/shell.qml#L264-L347)

**Impact**

Shibumi records `requires` and `recommends`, but its installer must enforce
them. Direct `serviceFor()` consumers also need local null/retry logic. Disable
or uninstall can otherwise leave enabled dependants without their state owner.

**Minimal proposed contract**

- Standard manifest fields `requires` and `recommends` containing plugin IDs
  plus an optional compatible version range.
- Validation for missing requirements and cycles.
- Dependency-ordered activation and reverse-order shutdown.
- A service lifecycle observable as `loading`, `ready`, or `failed`, with a
  change signal or callback.
- Disable/remove either refuses while required by enabled plugins or performs
  an explicit reviewed cascade.

**Acceptance proof**

Enable a widget whose service loads asynchronously and itself requires another
service. The widget becomes active only after both services are ready. A failed
dependency produces an actionable error and no partially active dependant.

## QTR-003: Configurable Default Menu Provider

**Current behavior**

The standard `omarchy-menu` command and the stock menu widget explicitly summon
`omarchy.menu`.

Evidence:

- [`bin/omarchy-menu`](https://github.com/basecamp/omarchy/blob/4a02da20d58d912a74748845bc55b5ec73acd65f/bin/omarchy-menu#L18-L31)
- [`menu/BarWidget.qml`](https://github.com/basecamp/omarchy/blob/4a02da20d58d912a74748845bc55b5ec73acd65f/shell/plugins/menu/BarWidget.qml#L1-L24)

**Impact**

Shibumi no longer provides a menu implementation and therefore does not
consume this proposed contract. Omarchy keybindings and commands continue to
open the stock menu.

**Minimal proposed contract**

- A host-owned setting such as `defaults.menuProvider` or a capability alias
  such as `omarchy.default-menu`.
- `omarchy-menu` resolves this provider before summon/hide/toggle/call.
- Missing or failed providers fall back to `omarchy.menu`.
- Route payloads remain the existing stable menu payload contract.

**Acceptance proof**

Select a third-party menu provider, invoke every existing Omarchy menu
keybinding, and verify that it receives the same route payloads. Disable or
break it and verify immediate fallback to the stock menu without changing the
keybindings.

## QTR-004: Exclusive Capability Providers

**Current behavior**

First-party non-bar plugins are implicitly enabled. There is no manifest-level
exclusive capability or selected-provider mechanism. This is safe for normal
views but not for process-global roles such as the notification server or OSD
feedback owner.

Evidence:

- [`PluginRegistry.isEnabled()`](https://github.com/basecamp/omarchy/blob/4a02da20d58d912a74748845bc55b5ec73acd65f/shell/services/PluginRegistry.qml#L100-L126)
- [`omarchy.notifications` manifest](https://github.com/basecamp/omarchy/blob/4a02da20d58d912a74748845bc55b5ec73acd65f/shell/plugins/notifications/manifest.json)
- [`omarchy.osd` manifest](https://github.com/basecamp/omarchy/blob/4a02da20d58d912a74748845bc55b5ec73acd65f/shell/plugins/osd/manifest.json)

**Impact**

A third-party notification or OSD implementation cannot safely replace the
first-party owner. Loading both notification servers or two OSD responders is
not an acceptable fallback strategy.

**Minimal proposed contract**

- Manifest-declared provided capabilities, for example
  `notification-server`, `osd-provider`, and `default-menu`.
- A host-owned selected provider for exclusive capabilities.
- Exactly one active owner per exclusive capability.
- Load the candidate first where possible; on failure retain or restore the
  stock provider.
- Non-owning notification views may still consume the selected notification
  service without claiming the server capability.

**Acceptance proof**

Switch notification provider while notifications are active. Prove that only
one D-Bus notification server owns the name, history remains consistent, and a
failed third-party provider leaves the stock implementation working.

## QTR-005: Presentation-Neutral First-Party Services

**Current behavior**

The generic service loader exists and works, but several first-party plugins
publish only `bar-widget` entry points. Their authoritative data, processes,
and actions live inside `Panel.qml`:

| Capability | Current kind | State/actions currently coupled to view |
| --- | --- | --- |
| `omarchy.audio` | `bar-widget` | sinks, sources, streams, mute, volume, default-device actions |
| `omarchy.network` | `bar-widget` | visible Wi-Fi, saved-profile actions, DNS, throughput, ping, speed test |
| `omarchy.bluetooth` | `bar-widget` | devices, discovery, connect/disconnect/forget, audio sink handoff |
| `omarchy.monitor` | `bar-widget` | brightness, displays, scale, mirror/toggle actions |
| `omarchy.power` | `bar-widget` | battery/system information and power profiles |
| `omarchy.weather` | `bar-widget` | location, current conditions, forecast, refresh state |
| `omarchy.model-usage` | `bar-widget` | Claude/Codex providers, refresh and aggregate state |

Evidence: their current
[`manifest.json` files](https://github.com/basecamp/omarchy/tree/4a02da20d58d912a74748845bc55b5ec73acd65f/shell/plugins/panels)
and the
[`model-usage` manifest](https://github.com/basecamp/omarchy/blob/4a02da20d58d912a74748845bc55b5ec73acd65f/shell/plugins/model-usage/manifest.json).

**Impact**

An alternative bar that needs Shibumi presentation but official Omarchy
behavior must instantiate the registered stock widget or its panel, hide that
presentation, inject a synthetic bar facade, and proxy properties/actions.
This couples backend lifetime to UI lifetime and to private property names.
It also makes duplicate scans and processes easier to introduce.

**Minimal proposed contract**

Add a `service` entry point to each capability. Stock panels and third-party
views consume the same singleton. The API does not need to dictate visual
models, but should expose stable state and action boundaries:

- **Audio:** default input/output, node/stream models, levels and mute state,
  set volume/mute/default device. Metering may be an explicit lease so it runs
  only while a visible consumer requests it.
- **Network:** backend availability, visible networks, saved profiles including
  non-visible profiles, scan state, connect/connect-with-secret/disconnect/
  forget, connection result, DNS state, and optional diagnostic leases.
- **Bluetooth:** adapter state, categorized devices, pending actions,
  connect/disconnect/forget, and reference-counted discovery acquisition.
- **Monitor:** display topology, focused display, brightness capability/value,
  scale and enable/mirror actions.
- **Power:** UPower state and profile list/current profile/set action. The
  existing battery warning service may remain separate.
- **Weather:** location, current/forecast values, loading/error state, refresh,
  and location mutation.
- **Model usage:** enabled provider snapshots, refresh state/action, and stable
  provider IDs. OpenCode remains a Shibumi extension, not an Omarchy request.

**Acceptance proof**

Run the stock panel and a minimal third-party read-only view simultaneously.
Both receive identical state from one service instance. Closing either view
does not stop the service or start a duplicate poller; optional high-frequency
work stops after the last lease is released.

## QTR-006: Reusable State Behind Stock Bar Widgets

**Current behavior**

Quattro correctly registers `omarchy.system-update`, `omarchy.indicators`,
`omarchy.tray`, `omarchy.clock`, and `omarchy.workspaces` as first-party
`bar-widget`s. They are reusable as complete visual components. However, some
state and policy remain local to those widget instances:

- System Update owns its check process, timer, IPC, and update-available flag.
- Indicators dynamically create per-indicator processes/watchers for reminder,
  night light, screen recording, and dictation. Idle and DND already have good
  services.
- Tray owns pin/hidden policy and menu state directly on the visual component.

Evidence:

- [`SystemUpdate.qml`](https://github.com/basecamp/omarchy/blob/4a02da20d58d912a74748845bc55b5ec73acd65f/shell/plugins/bar/widgets/SystemUpdate.qml)
- [`Indicators.qml` and indicator components](https://github.com/basecamp/omarchy/tree/4a02da20d58d912a74748845bc55b5ec73acd65f/shell/plugins/bar)
- [`Tray.qml`](https://github.com/basecamp/omarchy/blob/4a02da20d58d912a74748845bc55b5ec73acd65f/shell/plugins/bar/widgets/Tray.qml)

**Impact**

Shibumi can embed the complete stock widgets, but it cannot retain its own V1
presentation while consuming one official state owner. Reimplementing these
checks would duplicate host work and policy.

**Minimal proposed contract**

- `omarchy.system-update` adds a service exposing availability, check state,
  refresh, and launch-update action.
- An `omarchy.indicators` or `omarchy.activity-status` service owns recording,
  dictation, night-light, reminder, idle, and DND state/actions. Existing idle
  and notification services may be referenced rather than duplicated.
- Tray policy may expose a narrow service/model for pinned and hidden IDs plus
  mutations. Raw StatusNotifier items can remain Quickshell-owned.

Clock and workspace state do not block Shibumi: stable Qt/Quickshell/Hyprland
APIs are sufficient. They are intentionally not requested as new services.

**Acceptance proof**

Render two different bar presentations on separate outputs and verify one
update check, one recorder/dictation watcher set, and one persistent tray policy
owner for the entire shell process.

## QTR-007: Structured Background And Theme Discovery

**Current behavior**

`omarchy.background` is already a useful singleton for current background,
transitions, applying a background, and opening stock selectors. It does not
publish the active theme identity or the ordered source directories and media
formats used by Omarchy's selector.

Evidence:

- [`Background.qml`](https://github.com/basecamp/omarchy/blob/4a02da20d58d912a74748845bc55b5ec73acd65f/shell/plugins/background/Background.qml)
- [`ImagePicker.qml` input contract](https://github.com/basecamp/omarchy/blob/4a02da20d58d912a74748845bc55b5ec73acd65f/shell/plugins/image-picker/ImagePicker.qml#L14-L31)

**Impact**

Shibumi owns two custom picker presentations, Tanzaku and Hearthstone. The
native carousel remains owned by Quattro's `omarchy.image-picker` plugin. To
show the same candidates as Quattro, the custom views currently need knowledge
of `~/.local/state/omarchy/current` and
`~/.config/omarchy/backgrounds/<theme>`, plus matching format and cache rules.
Those are host implementation details and have already changed between Omarchy
generations.

**Minimal proposed contract**

Extend `omarchy.background` with stable structured properties or methods for:

- active theme ID;
- existing background source directories in precedence order;
- supported source formats;
- current selected background; and
- an apply method that keeps Omarchy transition/state behavior authoritative.

Returning source metadata is sufficient; Omarchy does not need to implement QS
Rise thumbnailing or picker styles.

**Acceptance proof**

Place backgrounds in both the active theme and user override directory. A
third-party picker discovers both without hard-coded Omarchy paths, applies one
through the service, and observes the same current-background state as the
stock selector.

## QTR-008: Standard Invocation And Output Context

**Current behavior**

Generic panel/menu/overlay invocation accepts an opaque payload and calls the
plugin's `open(payloadJson)`. There is no common field or helper that identifies
the originating bar instance, output, pointer output, or requested target
screen.

Evidence:

- [`summon()` payload delivery](https://github.com/basecamp/omarchy/blob/4a02da20d58d912a74748845bc55b5ec73acd65f/shell/shell.qml#L442-L479)
- [`panel loader`](https://github.com/basecamp/omarchy/blob/4a02da20d58d912a74748845bc55b5ec73acd65f/shell/shell.qml#L582-L639)

**Impact**

Per-output Shibumi panels must produce identical placement whether opened from
a mouse on a particular bar or from an Omarchy shortcut/IPC command. Without a
host contract, every plugin invents focus/pointer/screen inference and can open
on the wrong monitor after focus or hotplug changes.

**Minimal proposed contract**

- A normalized invocation context passed separately or inside a reserved
  payload member: `screenName`, `sourcePluginId`, `sourceBarId`, and invocation
  kind (`pointer`, `keyboard`, `ipc`).
- A host helper to resolve the preferred real screen when context is absent.
- Backward compatibility for plugins that accept only their current string
  payload.

**Acceptance proof**

With two outputs, open the same plugin from each bar, a keyboard shortcut, and
IPC with an explicit output. It appears on the deterministic expected output;
disconnecting that output falls back to a remaining real screen.

## QTR-009: Versioned Third-Party Bar Capabilities

**Current behavior**

The shell injects `omarchyPath`, `shell`, `manifest`, `barWidgetRegistry`,
`pluginRegistry`, and `barConfig` when matching properties exist. First-party
widgets then use additional bar methods and properties for tooltips, panels,
settings, execution, hover suppression, and geometry. There is no versioned
manifest declaration or runtime capability query for that extended facade.

Evidence:

- [`configureBar()`](https://github.com/basecamp/omarchy/blob/4a02da20d58d912a74748845bc55b5ec73acd65f/shell/shell.qml#L215-L224)
- [`bar-widget registration`](https://github.com/basecamp/omarchy/blob/4a02da20d58d912a74748845bc55b5ec73acd65f/shell/shell.qml#L657-L712)

**Impact**

Shibumi must reconstruct and regression-test the facade expected by every
stock widget it embeds. A Quattro change can load successfully but fail later
on interaction because a method was renamed or omitted.

**Minimal proposed contract**

- Document a versioned minimum bar-host facade for third-party `bar` plugins.
- Let a bar manifest declare the supported facade version and optional
  capabilities such as tooltip hosting, anchored panel routing, settings
  mutation, and command execution.
- Let widgets declare required capabilities or degrade visibly when absent.
- Validate compatibility before selecting a third-party bar; preserve stock-bar
  fallback on mismatch.

**Acceptance proof**

Select a fixture bar missing one required capability. The host refuses or
marks the incompatible widget before runtime interaction and retains a working
stock bar. A conforming fixture passes a shared contract test.

## QTR-010: Exact-Code Reload After Plugin Update

**Current behavior**

`shell.reloadPlugins()` deactivates plugin loaders, calls
`Qt.clearComponentCache()`, rescans manifests, and recreates the selected bar,
services, panels, and bar widgets. With an in-place update whose entry-point
URLs are unchanged, the validation system proved that new marker files and the new suite
payload digest can be visible while QML components are still created from the
previous cached code. A newly added IPC function returned `Function not found`
after multiple successful rescans and a stock-bar round trip.

Evidence:

- [`reloadPlugins()` and `finishPluginReload()`](https://github.com/basecamp/omarchy/blob/4a02da20d58d912a74748845bc55b5ec73acd65f/shell/shell.qml#L734-L769)
- [`syncPluginWidgets()` unchanged-URL handling](https://github.com/basecamp/omarchy/blob/4a02da20d58d912a74748845bc55b5ec73acd65f/shell/shell.qml#L670-L712)

**Impact**

A transactional updater cannot equate successful discovery or a new on-disk
digest with execution of the new code. Shibumi must request a full
`Quickshell.reload(false)` after swapping an updated payload and before runtime
verification. A deployment predating that endpoint needs one explicit Omarchy
Shell restart to bootstrap it.

**Minimal proposed contract**

- A host-owned `reloadPlugins` operation guarantees that all replaced QML and
  JavaScript entry points execute from the new bytes before it reports ready.
- The operation exposes completion or failure and preserves the selected bar,
  shell configuration, enabled services, and stock-bar fallback.
- Plugin update verification can query a runtime revision or content digest
  generated by the newly executing component rather than a marker read from
  the replaced directory.

**Acceptance proof**

Install a fixture plugin with IPC method `revision()` returning `A`. Replace it
in place at the same URL with a version returning `B`, rescan once, and prove
that the existing shell returns `B`. Repeat for an active bar, a service, a
bar-widget, and a keep-loaded panel without duplicate instances or stale
workers.

## Shibumi Coverage Matrix

This matrix ensures every planned plugin has been considered. `Own` means the
feature is intentionally implemented by Shibumi and is not an upstream gap.

| Shibumi plugin | Host contracts used or missing | Classification |
| --- | --- | --- |
| `hancore.shibumi.bar` | QTR-001, QTR-002, QTR-008, QTR-009, QTR-010 | Host integration |
| `hancore.shibumi.state` | QTR-001, QTR-002 | Host integration |
| `hancore.shibumi.control-center` | QTR-009 | Host integration; UI is Own |
| `hancore.shibumi.reactor` | Media service already exists | Own |
| `hancore.shibumi.telemetry` | None | Own `/proc` and GPU telemetry |
| `hancore.shibumi.power-state` | QTR-005 power service | Host service gap |
| `hancore.shibumi.workspaces` | Stable Hyprland API | Own presentation; no host gap |
| `hancore.shibumi.status` | QTR-004, QTR-006; idle/notifications already exist | Partial host service gap |
| `hancore.shibumi.memory` | Telemetry service | Own |
| `hancore.shibumi.cpu` | Telemetry service | Own |
| `hancore.shibumi.audio` | QTR-005 audio; media service already exists | Host service gap |
| `hancore.shibumi.ai` | Current `omarchy.agents` primitive record contract; QTR-005 model-usage fallback on pinned older hosts; OpenCode extension is Own | Partial host service gap |
| `hancore.shibumi.center` | QTR-005 weather, QTR-006 system update | Host service gap |
| `hancore.shibumi.media` | `omarchy.media` already supplies a service | Contract available |
| `hancore.shibumi.quick-access` | `omarchy.background`; discovery via QTR-007 | Partial host service gap |
| `hancore.shibumi.network` | QTR-005 network | Host service gap |
| `hancore.shibumi.battery` | QTR-005 power/UPower | Partial host service gap |
| `hancore.shibumi.brightness` | QTR-005 monitor | Host service gap |
| `hancore.shibumi.power-profile` | QTR-005 power | Host service gap |
| `hancore.shibumi.bluetooth` | QTR-005 Bluetooth | Host service gap |
| Future notification plugin | QTR-004 | Blocked until exclusive ownership is safe |
| Future OSD plugin | QTR-004 | Blocked until exclusive ownership is safe |

## Explicitly Not Requested From Omarchy

The following are Shibumi product choices and should not be presented as
Quattro shortcomings:

- V1 visual tokens, G1-G15 grouping, split mode, drag-and-drop, compact mode,
  panel chrome, and top/bottom composition;
- CPU, memory, GPU, and process telemetry;
- OpenCode usage support and Shibumi AI warning presentation;
- Tanzaku and Hearthstone picker views, thumbnail caches, and media
  browsing;
- Reactor animations and quote/event presentation;
- Shibumi Control Center UI; and
- additional Shibumi bar variants.

## Suggested Alpha Order

1. **Foundation:** QTR-002 dependencies/readiness and QTR-009 bar capability
   versioning. These make all third-party compositions more deterministic.
2. **Distribution:** QTR-001 suite sources, so one repository can remain
   modular without custom install/update plumbing.
3. **Safe replacement:** QTR-004 exclusive provider selection.
4. **Reusable platform behavior:** QTR-005 services, beginning with Network,
   Audio, Bluetooth, Monitor, and Power; then Weather and Model Usage.
5. **Shared status and UX context:** QTR-006, QTR-007, and QTR-008.

Shibumi can continue development with bounded adapters, but QTR-003 through
QTR-006 should be resolved before those adapters are treated as stable public
architecture. The desired outcome is not more Omarchy UI: it is one
authoritative backend that stock and third-party presentations can both use.
