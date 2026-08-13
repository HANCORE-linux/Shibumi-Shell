# QS Rise V1 to Shibumi widget parity audit

> **Document status: Current validation evidence.** This audit records detailed
> G1-G15 parity evidence. `release-readiness.md` contains the current release
> summary if status wording differs.

Date: 2026-07-23

This audit compares the production V1 bar with the current Shibumi Omarchy Shell
plugin. A correct backend owner is necessary, but it does not by itself count
as V1 parity. A group is complete only when its bar presentation, panel,
actions, degraded states, top/bottom geometry, and per-output behavior meet the
V1 contract.

Status values:

- **Ported**: the V1 outcome is represented locally; runtime acceptance may
  still be open.
- **Adapted, incomplete**: the Quattro owner is retained, but V1 presentation
  or workflow is still missing.
- **Missing**: no Shibumi implementation exists yet.

## Group Audit

| Group | V1 contents | Current Shibumi result | Status | Required work |
| --- | --- | --- | --- | --- |
| G1 | Wordmark and Control Center | Independent wordmark widget and compact V1-style Control Center over the shared Shibumi state and bar facade | Adapted, acceptance incomplete | Main surface, stored settings contract, exclusive Omarchy application-menu ownership, Top/Bottom placement, 20-cycle closed-PSS, and the eight-choice V1 palette are complete. Finish the remaining subpage, state-matrix, multi-output, and hotplug acceptance. |
| G2 | Workspaces and workspace panel | Local V1-style view over one shared Hyprland service | Ported | Final top/bottom, mixed-scale, multi-output, keyboard, and hotplug acceptance. |
| G3 | Arch updater, tray, notifications | Local V1 tray icons, hidden-app drawer, bell/badge, shared pill, pending-only V1 notification panel, and a Shibumi-owned DBusMenu surface over the official Quattro tray and notification owners; the Omarchy update indicator remains authoritative | Ported, acceptance incomplete | A deterministic SNI/DBusMenu fixture accepts the populated attention drawer, root application menu, retained child menu, and real nested action on the validation system at Top and Bottom. Checked, disabled, separator, and submenu-launch rows render correctly; two independent `item=6` DBus events prove the nested action path. The root handle remains referenced during navigation and the card retains its root height so Top pointer travel cannot fall through to the dismiss surface. Final real third-party SNI, multi-output, notification-action, and hardware-adjacent acceptance remain. Do not copy the standalone shell updater into Shibumi. |
| G4 | Memory widget and panel | Local compact/full widget and lazy panel over shared procfs telemetry | Ported | Correct global panel anchoring and complete visual/runtime comparison. |
| G5 | CPU widget and panel | Local compact/full widget and lazy panel; GPU detail is lifecycle-gated | Ported | Correct global panel anchoring and complete visual/runtime comparison, including systems without `nvidia-smi`. |
| G6 | Volume widget and mixer panel | V1-style bar and lazy mixer panel over the official PipeWire state/action owner | Ported | Validate real output/input device changes, app-stream mutation, microphone meter/mute, top/bottom placement, and multi-output lifecycle on Wayland. |
| G7 | One selected Claude, Codex, or OpenCode indicator and AI panel | One process-wide Shibumi provider service now renders a single selected provider and a local V1-style panel. Claude/Codex reuse the official provider scanners only when their local data exists; OpenCode uses one read-only, cache-free SQLite adapter. | Ported | OpenCode bar, panel, legacy IPC alias, refresh lifecycle, cleanup, and default Top/Bottom product-panel routing are accepted on the validation system. Complete real-account Claude/Codex and physical multi-output acceptance before release. |
| G8 | Weather, clock, date, idle, DND, recording, Voxtype, Omarchy update | Local V1 weather, clock/date/calendar, active-only status, and update facades over process-wide services and official owners | Adapted, incomplete | Weather has one process-wide source, honors Quattro's saved location, and lazy-loads the V1 panel without the stock Weather poller. the validation system confirms one shared live Voxtype stream plus a real recording/transcription/idle cycle with text insertion. A real no-audio Quattro recording was detected, timed, stopped by physically clicking the visible G8 indicator, finalized as a valid MP4, and cleaned up while G8 expanded and contracted correctly. Complete mixed-scale and physical multi-output acceptance. Idle, notification, and update owners remain authoritative. |
| G9 | MPRIS controls, marquee, pulse, and player panel, including selectable FULL/muse | Local default row, lazy panel, and current V1 24-band vinyl/waveform/transport row over the official keep-loaded media service and one lazy process-wide spectrum owner | Ported | Real `mpv`, two-player source switching, the actual empty/populated Top/Bottom MediaPanel, available/unavailable/crash states, two-client/one-worker lifecycle, 20 pause/resume cycles, resource characterization, and Top/Bottom bar visuals pass on the validation system. Complete degraded/failure presentation and physical multi-output acceptance. |
| G10 | Idle inhibitor, screenshot/video browser, theme/wallpaper picker | One V1 quick-access pill, a true surface-bound idle inhibitor, and one process-wide picker/media controller with V1-faithful Tanzaku and Hearthstone views; use Quattro's native image picker for its carousel | Ported | Basic open/close, all four modes, style persistence, focused-output routing, worker cleanup, 20-cycle closed-PSS retention, real theme/wallpaper success, controlled theme/wallpaper failure feedback, and screenshot/video copy/open/two-step trash are accepted on the validation system. Tanzaku and the revised Hearthstone wallpaper view are visually accepted; keyboard navigation, warm close cleanup, native carousel coexistence, V1 idle-inhibitor presentation, and a real 4K cold-wallpaper/warm-reopen gate pass. Complete remaining Hearthstone theme/media rendering and physical multi-output acceptance. |
| G11 | Network state, Wi-Fi/ethernet presentation, throughput, network panel | One root-owned official NetworkManager backend plus lazy Shibumi panels, a Shibumi-owned inline speed-test process, and a lifecycle-only saved-profile adapter | Ported, acceptance incomplete | Top and bottom panel placement, expanded metadata, saved-profile discovery, alias routing, and backend refresh pass on the validation system. The direct inline speed-test path has fixture-backed phase, failure, and crash-cleanup coverage; repeat real output acceptance for this new owner before release. A stale saved-only profile was forgotten through the visible two-step action and stayed absent after reopen/rescan. A real `DHCP -> Cloudflare -> DHCP` DNS round trip passed through the panel and Polkit with the original connection and resolver state restored. Validate a new protected-network connection/passphrase and physical multi-output before release. |
| G12 | Battery widget and battery detail panel | Local view and panel over the shared UPower service | Ported, state accepted | the validation system reports the physical BAT0 as present and healthy. A real discharging-to-charging transition produced matching kernel, UPower, helper, widget, and panel state. Complete physical multi-output acceptance. |
| G13 | Brightness widget and panel | One official root backend plus V1-style per-output widget and lazy local Shibumi display panel | Ported, acceptance incomplete | Top and Bottom mapping, reversible laptop brightness mutation, and a real `1.0 -> 1.25 -> 1.0` scale round trip pass on the validation system. Validate no-backlight hardware, physical display enable/disable, and physical multi-output ownership. |
| G14 | Power-profile widget and panel | Local view and panel over the shared power-profile service | Ported, action accepted | the validation system completed and restored a real performance-to-balanced-to-performance change from `app-graphical.slice`; the product panel now passes Top/Bottom routing and loader diagnostics. Complete physical multi-output acceptance. |
| G15 | Bluetooth widget and panel | One shared Shibumi-native BlueZ/PipeWire adapter with local V1-style widgets and lazy Shibumi device panels | Ported, acceptance incomplete | Top/Bottom mapping, real adapter/radio reactivity, confirmed discovery ownership/reconciliation, multi-panel lease accounting, and the symmetric six-method legacy IPC pass on the validation system. Validate pair/connect/disconnect/forget with real devices, Bluetooth audio, and physical multi-output. |

## Panel Capability Decisions

This table grows with the panel-by-panel review. A Quattro capability is not
accepted merely because it already exists upstream; it must preserve a single
authoritative backend owner, remain lifecycle-bounded, and fit the V1 visual
and interaction contract.

| Panel | V1 baseline | Quattro capability decision | Presentation decision | Remaining acceptance |
| --- | --- | --- | --- | --- |
| Audio | Output volume, output selection, microphone state, application streams | **Keep/adapt:** official PipeWire owner, output and input volume actions, output selection, per-stream volume/mute, microphone mute, and live microphone level | Shibumi owns the 280 px V1 card, description-first device labels, typography, device rows, button states, output/input/stream sliders, and thin activity meter. Stock Quattro sliders and panel chrome are excluded. | Real microphone slider/mute/meter mutation, output-device switch, app-stream mutation, top/bottom placement, and multi-output lifecycle on the validation system. |
| Notifications | V1 bell/badge, 320 px pending card, compact text rows, per-row dismiss and clear action | **Keep/adapt:** official notification owner, persistent pending/recent models, DND, deduplication, image-cache lifecycle, per-row dismiss, mark-seen, and clear-pending actions | Shibumi owns the 320 px card, header, row typography, dismiss controls, empty state, and action button. The V1 surface deliberately shows pending notifications only; recent history and DND remain service/control-center concerns instead of adding duplicate tabs or controls. Stock 440 px Quattro popup chrome and large media rows are excluded. | Real populated transitions, DND interaction through its authoritative control, dismiss/clear, app focus, close/reopen, and multi-output lifecycle on the validation system. |
| Weather | V1 weather glyph, 300 px detail card, current conditions, three-day forecast, refresh, and unit toggle | **Keep/adapt:** one Shibumi process-wide weather source, Quattro's persisted weather location, bounded 15-minute refresh, last-good data, and explicit refresh. **Exclude:** a second hidden stock Weather panel/poller and Quattro's 480 px stock presentation. | Shibumi owns the V1 glyph, tooltip, 300 px card, compact stat rows, forecast rows, refresh state, and metric/imperial control. | Real saved-location response, cold/failed fetch, refresh, unit persistence, top/bottom placement, and multi-output lifecycle on the validation system. |

## Shared V1 Contracts

| Area | Current result | Audit conclusion |
| --- | --- | --- |
| Top and bottom | The horizontal `BarPanel` keeps a stable edge-local host window; per-output edit-dismissal and input-transparent drag overlays preserve full-output feedback without reporting screen height as bar height | **Implemented locally, representative placement and stored state accepted.** The full Bottom bar plus G1 Control Center, G3 Update Center, centered G8 calendar, G7 AI, G11 Network, G14 power-profile, G15 Bluetooth, and Display panels map correctly on the validation system. All 14 split boundaries and a stored G4/G5 reorder render and survive `reloadConfig`; physical Bottom drags pass for a successful drop, byte-identical invalid-drop return, and process-restart persistence. Focus, mixed-scale, and multi-output behavior remain Wayland gates. |
| Island edge spacing | Separate 5 px frame and 4 px content insets are tokenized and applied to the first/last regions | **Implemented locally.** Exact mixed-scale visual comparison remains a Wayland gate. |
| Tooltips | Shibumi owns the V1 bar background, pill border, radius 6, 10/4 padding, mono 12 px, and letter spacing 1 surface | **Implemented locally.** Top/bottom placement and multi-output target ownership remain Wayland gates. |
| Panels | Local V1-style panels now cover the reviewed core slices, including Control, Updates, Audio, Notifications, Weather, AI, Media, Network, power-profile, Bluetooth, and display controls | **Incomplete.** A same-output current-V1/Shibumi run covers the closed bar and ten principal panel families at Top/color01; later focused G1 palette, populated G9 FULL/muse, actual empty/two-source G9 Top/Bottom MediaPanel, and G7/G14/G15 Top/Bottom default slices pass. Remaining degraded and account/device-backed states, complete Bottom comparison, and physical multi-output still gate parity. |
| Multi-monitor and resume | One bar window and one drag session are created per real output; invalid Wayland placeholders are rejected and lost layer windows receive targeted recovery | **Implemented locally, acceptance open.** Focused bar-widget routing, V1 side-group narrow/portrait staging, controlled headless add/remove, output-local summon, and cleanup pass on the validation system. Physical mixed scale, hotplug during edit, display sleep, suspend/resume, hibernate/resume, and split/drag persistence remain real runtime gates as specified in `v1-output-lifecycle-audit.md`. |
| Split and drag | Shared persistent model, per-output drag session, run chrome, ghost, and invalid-drop return exist | **Implemented, partially accepted.** the validation system passes a physical Bottom ghost, successful drop, byte-identical invalid-drop return, process-restart persistence, and the V1 hover-revealed `•`/`│` handles. The ghost now renders on a dedicated input-transparent output overlay while the bar keeps a stable edge-local input surface. Hotplug, mixed scale, and multi-output gates remain. |
| Compact mode | Implemented for CPU, memory, audio, media FULL/muse, network, battery, brightness, power, and Bluetooth; G7/G10 expose bounded group pills and G1 persists all approved compact toggles | **Partial.** G9 passes its focused single-output runtime gate; G8 and final mixed-scale visual acceptance remain. |
| Fresh-install widget defaults | V1 starts G7 AI usage, G14 power profile, and G15 Bluetooth disabled; other groups start enabled. Brightness is enabled but renders only when a backlight exists, so hardware absence must not be confused with a disabled default. | **Accepted on the validation system.** A real final-source fresh install hid exactly G7/G14/G15, rendered every other applicable group, used Tanzaku and Reactor mode 0, and preserved Bottom. Restoring the previously enabled optional groups and restarting the shell retained the complete settings block. Missing-hardware behavior remains covered by the component contracts and final unavailable-hardware gate. |
| Image pickers | One shared scanner/cache/controller with Tanzaku and Hearthstone presentation-only views; Quattro retains its native carousel | **Ported, top/bottom rendering and success actions accepted.** Basic the validation system rendering, cleanup, the warm Tanzaku fullscreen overlay at Bottom, theme reapply, wallpaper apply/restore, controlled failure feedback, and a 2,091 ms content-unique 4K Hearthstone cold preview pass. The restored warm cache exposed 11/11 previews in 275 ms, and hard-aborted scan cleanup preserves the stable cache. Hearthstone Bottom/theme/media and physical multi-output gates remain. |
| Media browser | Screenshot/video modes share the same lazy controller, bounded poster workers, open/copy/trash actions, and fast-close cancellation | **Ported, primary actions accepted.** Unique the validation system screenshot and video fixtures passed copy, open, two-stage trash, cache refresh, and complete artifact cleanup. Remaining malformed-media and output-lifecycle edge cases remain. |
| Reactor | Modes 1-6 use a backend-free gap layer; Mode 7 uses one lazy root event service; Mode 8 uses one lazy root quote service; Modes 7-8 share a per-output renderer | **Implemented; single-output visual, lifecycle, and bounded CPU gate accepted.** Mode 0 constructs no service or renderer, and no Quattro service owner is duplicated. Modes 1-6 have controlled the validation system visual evidence. Real split-gap runs prove Mode-7 text and monitor sweep plus Mode-8's V1-compatible quote-fit fallback. Active effects retain documented non-default CPU cost; physical multi-output acceptance remains. |
| Notifications | Local V1 bell/badge and lazy V1 pending presentation over the authoritative Quattro service/widget | **Ported, acceptance partial.** Empty and populated 320 px cards now pass at Top and Bottom, including the 12 px inset, header/count, separator, compact app/summary/body row, dismiss affordance, empty label, and edge-local routing. A real uniquely tagged notification reached Quattro's authoritative pending model; clicking the visible Shibumi row dismiss control removed it and live-updated the same open panel to `No notifications`. The panel contains no duplicate DND control or recent-history tabs. Row activation delegates app focus to Quattro, while dismiss and clear mutate its authoritative pending model. Error/degraded, real app-focus/default-action, and physical multi-output states remain open. |
| OSD | Official Quattro OSD remains active | **Correct adaptation.** Shibumi must not create a competing OSD owner. |
| Standalone updater | Not copied | **Correct adaptation.** Omarchy owns runtime discovery and activation; the Shibumi suite installer owns transactional bundle staging and rollback while current Omarchy supports one repository per installed plugin. The Omarchy update indicator still belongs in the V1 G8 position. |

## Product Decisions

The following decisions are already fixed by the product requirements and do
not need to be reopened:

1. Shibumi supports the same top and bottom product positions as V1. Vertical bars
   are not a Shibumi release requirement.
2. Quattro owns plugin lifecycle, notifications, OSD, NetworkManager, BlueZ,
   PipeWire, display control, and other platform services where an adequate
   service contract exists.
3. Reusing a Quattro backend does not permit a lower-quality or unrelated final
   Shibumi presentation.
4. V1 panel UI/UX is a release premise, not a post-functional polish target.
   Quattro tokens may supply host theme and scale inputs, but all visible
   geometry, hierarchy, controls, states, iconography, and motion must match
   the approved V1 reference unless an exception is explicitly approved.
5. OpenCode, both Shibumi picker styles, the native Quattro image picker, the media browser, compact behavior,
   split layout, drag-and-drop, and robust multi-monitor behavior remain part
   of Shibumi parity.
6. G1 remains the Shibumi wordmark and Control Center. Omarchy exclusively owns
   the application menu; Shibumi does not register a menu plugin or service.

No additional product decision blocks the next implementation slice. A future
intentional visual exception for an official panel must be approved explicitly
after a side-by-side runtime comparison; it may not be inferred from the use of
an official backend.

## Correct Phase

The project pauses **Phase 2: Core Widgets and V1 presentation parity** for the
behavior-preserving plugin-suite migration defined in
`plugin-suite-migration-plan.md`. It is not in final visual polish.

- Phase 0 contract scaffold: complete.
- Phase 1 bar/runtime foundation: implemented; final multi-output and
  fractional-scale acceptance remains open.
- Phase 2 ownership/backend foundation: substantially implemented.
- Phase 2 V1 presentation parity: in progress. G1 is separated from the App
  Menu and its complete V1 settings contract is implemented; G3 now has local
  package/theme Update Center presentation. G8 has accepted top-position
  weather plus update, idle, DND, recording, and active Voxtype evidence but
  still needs bottom and multi-output acceptance. G9 FULL/muse passes its
  focused single-output implementation, visual, lifecycle, failure, and
  resource gates. Final side-by-side and action gates remain for several local
  panels.
- Phase 3 split/drag implementation: present locally; the corrected Bottom
  window geometry, ghost, and successful physical drop pass. Remaining edge
  cases are hotplug, mixed scale, and multi-output behavior; byte-identical
  invalid-drop return and process-restart persistence also pass.
- Phase 4 pickers/media: implemented locally; basic the validation system rendering,
  focused-output routing, persistence, cleanup, apply/action, and cold
  wallpaper cache pass. Remaining Hearthstone theme/media, Bottom, and
  multi-output gates remain.
- Phase 5 release parity and performance acceptance: started. The current
  reload, crash-baseline, CPU, PSS, and worker-cleanup slice passes; the complete
  presentation matrix and physical gates remain open.

## Implementation Order

1. Correct shared top/bottom panel geometry, island content inset, and tooltip
   presentation without regressing edit mode. **Implemented locally; real
   top/bottom, mixed-scale, and multi-output acceptance remains open.**
2. Restore group semantics and center presentation: move Omarchy update to G8,
   implement V1 status/weather facades, and correct G3. **Implemented locally;
   top weather/update/idle/DND, recording, and active Voxtype runtime paths pass
   on the validation system, while bottom and multi-output
   acceptance remains open.**
3. Implement the G7 single-provider AI facade with correct assets and OpenCode
   parity. **Implemented and accepted for OpenCode on the validation system; final
   Claude/Codex account-data and multi-output acceptance remains open.**
4. Restore G10 and build the shared picker/media architecture. **Implemented
   locally and basic-runtime accepted on the validation system; final action and output
   gates remain.**
5. Extract the approved V1 bar controls and wordmark into
   `hancore.shibumi.control-center`; keep the application menu owned by
   Omarchy. **The Control main surface, eight-choice palette, and repeated
   lifecycle gates pass. Shibumi's former menu implementation is retired.
   Remaining subpage, state-matrix, multi-output, and hotplug acceptance is
   open.**
6. Complete Shibumi panel presentation over official service owners for audio,
   network, monitor, and Bluetooth; complete real-Wayland acceptance for the
   G3 tray/notification facade. **Network and monitor presentation plus root
   ownership are implemented; final mutation/bottom/multi-output acceptance
   remains.**
7. Port Reactor through a shared event service and style-owned renderer.
   **Implemented; single-output Mode 7/8 rendering, lifecycle, and bounded CPU
   characterization pass. Physical multi-output acceptance remains open.**
8. Complete the remaining current-V1 presentation, multi-monitor, mixed-scale,
   hardware, and account-dependent acceptance before release. Representative
   Top/Bottom placement, reload/crash baselines, performance/cleanup,
   successful and invalid Bottom drops, G9 FULL/muse, and process-restart
   persistence are accepted.
