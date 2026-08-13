# Phase 2 Ownership Map

> **Document status: Normative supporting contract.** The G1-G15 ownership and
> action boundaries in this document remain binding. Current acceptance status
> is recorded in `release-readiness.md`.

This document maps the QS Rise V1 bar groups to the Omarchy Quattro host
contract. It is the implementation boundary for Phase 2: preserve the V1 user
experience without copying V1 lifecycle code or creating a second owner for
platform state.

## Resolution Rules

Every feature has exactly one state owner and one action boundary:

1. Use an Omarchy or Quickshell service when it already owns the platform
   state.
2. Add a narrow adapter when the host API does not match the V1 view contract.
3. Add a Shibumi service only for product state that Omarchy does not own.
4. Keep per-screen popup placement in the shared bar runtime, never in a data
   service.
5. Keep presentation in independently installable widget and panel plugins. A
   selectable bar host may supply tokens and surfaces, but not another feature
   service or action path.
6. Until a complete Shibumi replacement is ready, an official Omarchy widget
   remains the fallback. A partial view must not remove a working host action.

## V1 Group Map

| Group | V1 contents | Authoritative Shibumi state/action owner | Shibumi responsibility |
| --- | --- | --- | --- |
| G1 | Shibumi wordmark and Control Center | Independent `hancore.shibumi.control-center` widget/panel over host-owned Shibumi settings | Preserve the V1 wordmark/icon, screen-local Control Center, lifecycle-gated feedback, colors 01-07 plus foreground, and complete bar-settings contract without opening or owning the App Menu; the current eight-choice palette is implemented and accepted on the validation system |
| G2 | Workspaces and workspace panel | One root-owned `Quickshell.Hyprland` model plus validated Quattro focus adapter | Shibumi modes, three presentation styles and lazy screen-local panel implemented locally; real-Wayland acceptance remains |
| G3 | Tray and notifications | Complete official `omarchy.tray` and `omarchy.notifications` components | One V1 status pill groups both components without copying SystemTray, notification, DND, history, menu, or action ownership; Omarchy update presentation is restored to G8 and no V1 self-updater exists in Shibumi |
| G4 | Memory | Shibumi singleton system telemetry | Compact/full widget and lazy detail panel |
| G5 | CPU | Shibumi singleton system telemetry | Compact/full widget and lazy detail panel |
| G6 | Volume | Official `omarchy.audio` state/actions through a narrow bridge; one open-only local peak monitor | V1 full/compact pill and lazy V1 mixer panel cover descriptively labeled output/input devices, per-app streams, mute, and meter; real Wayland/top-bottom/multi-output acceptance remains |
| G7 | Claude, Codex, and OpenCode usage | One root-owned Shibumi AI usage service over primitive current `omarchy.agents` schema-v1 records; pinned older hosts exclusively fall back to their official Claude/Codex `omarchy.model-usage` providers, and one read-only OpenCode SQLite provider fills the remaining host gap | One selected-provider pill, V1 usage fill, local lazy panel, provider cycling, refresh, current `omarchy.agents` and legacy `omarchy.model-usage` routing, and no duplicate visible host panel, cache, or screen-local poller ownership; OpenCode is accepted on the validation system while current-host Claude/Codex real-account and multi-output gates remain |
| G8 | Weather, clock, date, status indicators, Omarchy update | Shared Shibumi clock/status adapters plus official Quattro weather-detail, idle, notification, and update owners | Single V1 pill, lazy routed calendar, local weather/status/update facades, child settings, and monitor-local normal/compact/minimal stages are implemented. Top weather, update-available, idle/DND, the complete recording-indicator lifecycle, and a real Voxtype recording/transcription cycle pass on the validation system; bottom and physical multi-output acceptance remain. |
| G9 | MPRIS | Keep-loaded official `omarchy.media` service plus one lazy process-wide Shibumi Cava service | Preserve the default row and current V1 FULL/muse 24-band spectrum, vinyl, transport, click, and wheel outcome; implementation plus real-player/failure/resource/Top-Bottom single-output acceptance pass, while multiple-real-player and physical multi-output gates remain |
| G10 | Idle inhibitor, media browser, theme/wallpaper picker | Surface-bound Quickshell idle inhibitor, Omarchy theme/background actions, and one root-owned Shibumi picker/media controller | V1 quick-tools pill plus Tanzaku and Hearthstone presentation-only views; Quattro keeps its native carousel; basic focused-output runtime and worker cleanup accepted on the validation system |
| G11 | Network | One root-owned service around the official `omarchy.network` state/action backend, plus Shibumi-owned inline speed-test and saved-profile workers | V1 `NET`/SSID/signal and compact views plus a lazy local details/DNS/speed-test/available/saved/connect/forget panel; top Wayland mapping and cleanup pass on the validation system, while mutation, bottom, and physical multi-output acceptance remain |
| G12 | Battery | One root-owned Shibumi power service over Quickshell's UPower singleton; Quattro battery helper only while the detail panel is open | V1 compact/full battery view and lazy battery panel; hidden on batteryless desktops; a real discharging-to-charging transition passes on the validation system |
| G13 | Brightness | One root-owned service around the complete official `omarchy.monitor` backend | V1 `BRI`/sun/percentage and compact views plus a lazy, screen-local Shibumi brightness/scale/display panel; top/Bottom mapping, reversible laptop brightness mutation, and a real `1.0 -> 1.25 -> 1.0` scale round trip pass on the validation system, while physical display enable/disable and multi-output acceptance remain |
| G14 | Power profile | Same root-owned Shibumi power service; one Quattro profile-list poller and one validated setter | V1 compact/full profile view and lazy profile panel; remains available without a battery |
| G15 | Bluetooth | One root-owned Shibumi service and native Quickshell BlueZ/PipeWire adapter; no complete Omarchy Bluetooth component is loaded | V1 full/compact widget and lazy per-output Shibumi device panel; confirmed discovery ownership with bounded reconciliation, latest-only audio handoff intent, and one symmetric six-method legacy IPC target; top mapping and real adapter/radio/discovery lifecycle pass on the validation system, while real device/audio, bottom, and physical multi-output acceptance remain |

## Shared Runtime Modules

The following features are shared by every future bar plugin. They are
independent plugin packages rather than children of one bar implementation.

### Application Menu

Omarchy's `omarchy.menu` is authoritative. Shibumi registers no `menu` kind,
application-menu service, launcher window, app index, favorites state, or menu
action adapter. G1 remains exclusively the Shibumi Control Center. Shibumi may
route its theme and wallpaper providers through Omarchy's documented menu
extension, but it does not replace the menu itself.

### Notifications

Quattro's first-party `omarchy.notifications` plugin is implicitly enabled and
owns the active `NotificationServer`, popup lifecycle, DND state, and history.
Loading a second Shibumi notification service would create two competing
notification daemons and is prohibited.

The initial Shibumi notification work therefore reuses
`shell.firstPartyServiceFor("omarchy.notifications")` and supplies Shibumi bar
and history views over that service. A full daemon replacement is a separate
host-contract project: Quattro must first support selecting or disabling the
first-party notification service, with rollback to the official service.

### On-Screen Display

Quattro's first-party `omarchy.osd` plugin is also implicitly enabled. A second
volume/brightness OSD would duplicate feedback. Shibumi initially keeps the official
OSD and makes Shibumi widgets drive the same PipeWire and monitor state.

A Shibumi OSD replacement is permitted only after the host exposes an explicit
selection contract for the OSD owner. It then becomes a shared panel/overlay
plugin, not a bar-style component.

## Configuration Ownership

The final Shibumi layout requires V1 group order, splits, compact choices, and
responsive behavior that the stock Omarchy `bar.layout` array cannot fully
describe. Shibumi will store this state under the host-owned `bar.shibumi` object in
`~/.config/omarchy/shell.json` and mutate it only through the injected shell
API.

Host-wide fields remain canonical:

```text
bar.id
bar.position
bar.transparent
bar.style
```

Shibumi-owned fields are versioned and validated before use:

```text
bar.shibumi.version
bar.shibumi.order
bar.shibumi.splits
bar.shibumi.widgets
```

Missing or malformed Shibumi state resolves to compiled defaults. Shibumi does not
silently rewrite `shell.json` during load. The group renderer consumes the QS
Rise order while retaining settings from `bar.layout`; unassigned custom host
widgets remain regional extras instead of disappearing.

The local interaction foundation keeps V1's fixed 15-group swap behavior and
positions split flags by gap rather than by widget identity. `LayoutController`
is the only bar-side persistence requester and calls `setLayout()` or
`resetLayout()` on `hancore.shibumi.state`; that service is the sole owner of the
host configuration mutation. Each `BarPanel` owns a separate transient
`DragSession`; styles receive that session for rendering but may not create or
persist interaction state. The renderer resolves all fixed groups through the
host plugin registry, preserves unassigned host entries as regional extras, and
applies split spacing.
Edit controls, drop targets, the drag ghost, and run chrome consume only this
shared state. They do not gain a second persistence path. Real pointer and
multi-output lifecycle acceptance remains separate from the local model and
component-load evidence.

## Phase 2 Implementation Order

1. Add a versioned, pure layout/config parser with V1 group defaults and no
   load-time writes.
2. Resolve Shibumi groups through registered plugin entry points while
   retaining unassigned official/custom host widgets as regional extras.
3. Add shared system telemetry and port CPU plus memory as the first complete
   widget-and-panel slice.
4. Port complete host-backed slices, including their panel actions, rather than
   replacing isolated icons.
5. Prove that Omarchy's application menu remains the sole registered provider.
6. Add Shibumi notification views over the official notification service.
7. Revisit an OSD replacement only after an exclusive host-owner contract
   exists.

Each slice requires compact, panel, lifecycle, failure, top/bottom, and
multi-output checks before it replaces the official fallback.

Tray remains a deliberate official fallback at this stage because its Quattro
entry point combines presentation with pin/hide and SNI-menu workflows.

Audio has an explicit backend/presentation boundary without forking state or
actions. The Shibumi G6 composite instantiates the registered official
`omarchy.audio` component internally, keeps its popup closed, suppresses its
stock button registration and IPC handler, and delegates the V1 bar and local
mixer actions back to that same instance. Quattro remains authoritative for the
PipeWire node lists, MPRIS stream labeling, output/input devices, per-app audio
objects, and direct PipeWire mutations. Shibumi owns only the screen-anchored
presentation, a settled list snapshot, and one peak monitor while that panel is
open. It does not invoke or create a second OSD. A local audio service, copied
device model, shell poller, or independent mixer backend remains prohibited.

Media uses the cleaner service/view split already provided by Quattro. The G9
Shibumi component consumes `shell.firstPartyServiceFor("omarchy.media")` and
the original `omarchy.media` bar alias is suppressed, but the official service
stays loaded and authoritative for player selection, ghost filtering, action
routing, source switching, PipeWire stream correlation, and OSD feedback. The
Shibumi views own only presentation and lazy panel state. One lazy process-wide
Shibumi spectrum service owns the optional Cava probe, process, degraded state,
lease accounting, and cleanup. Per-output, per-panel, or per-view Cava owners
are prohibited even though the spectrum is not a second media-state owner.
The service runs only with a playing official source and at least one visible
spectrum lease, streams the bounded V1 configuration through stdin, and allows
exactly three retry starts before exposing failure. the validation system accepts the
single-output lifecycle, real-player, degraded, Top/Bottom, visual, and
resource slices; this does not waive physical multi-output acceptance.

Network uses the same state/action delegation principle as audio, but the owner
must be root-scoped: Quattro's component includes a permanent three-second bar
status process, so instantiating it inside every output would duplicate work.
One `NetworkService` hosts that component, and all G11 widgets consume it.
Screen-local popups delegate visible-network and DNS mutations to the official
backend. The root service runs `omarchy-network-speedtest` itself for bounded
download/upload phases and publishes progress only to Shibumi's inline panel;
it never loads Omarchy's standalone speed-test panel. A lifecycle-only `nmcli`
query/action path adds saved profiles that are not currently visible because
Quickshell's model omits them. One shared verbose status process runs while a
Network panel is open or an Ethernet bar still consumes throughput, without
restoring V1's permanent `/proc`/`ip`/`iw` poller.

## Sequencing Decision

The V1 application menu is outside Shibumi's product boundary. Notification
and OSD services likewise remain authoritative in Quattro until an explicit,
exclusive owner-selection contract prevents duplicate platform owners.
