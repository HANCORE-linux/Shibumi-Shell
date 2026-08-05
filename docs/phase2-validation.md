# Phase 2 Validation

> Historical note: the Shibumi application-menu experiment documented below
> was retired before `0.1.1-beta.1`. Omarchy now exclusively owns the
> application menu; none of the menu payload described here ships.

> **Document status: Historical validation evidence.** This document preserves
> combined-plugin and feature-slice evidence. It does not describe the current
> release gate and cannot override `../ARCHITECTURE.md`.

> **Migration note:** Results in this document describe the combined-plugin
> prototype. They remain valuable behavioral evidence, but they do not accept
> the target plugin-suite packaging. Every affected lifecycle gate must be
> repeated after extraction according to `plugin-suite-migration-plan.md`.

## Local Foundation

The first Phase 2 slice adds the versioned QS Rise group configuration contract,
an internal widget registry, shared CPU/memory telemetry, CPU and memory widgets
with lazy detail panels, and the root-owned workspace slice.

Validated locally on 2026-07-16:

- malformed, duplicate, missing, and unknown-version QS Rise layout state falls
  back to compiled V1 defaults without writing `shell.json`;
- valid group order, split state, and sanitized widget settings survive
  normalization;
- widget settings reject non-finite numbers, oversized strings/collections,
  excessive object breadth, unsafe prototype-related keys, and nesting beyond
  the documented bound before they enter runtime state;
- the isolated Quickshell smoke loads real `/proc/stat` and `/proc/meminfo`;
- CPU and memory widgets share one root telemetry object;
- widget creation acquires one consumer per feature;
- widget destruction releases both consumers and stops recurring sampling;
- closed detail panels are not instantiated or type-resolved;
- GPU polling has zero consumers while the CPU panel is closed;
- unusable `nvidia-smi` output is rejected and does not create a false Nvidia
  backend;
- contract regression, Bash syntax, ShellCheck, `git diff --check`, and Qt 6
  `qmllint` complete successfully.

The isolated offscreen smoke emits an IPC-socket warning because it uses a
throwaway runtime directory and does not need IPC. Its explicit lifecycle marker
and exit status are the test gate; a QML load failure cannot pass the harness.

## Workspace Slice

Validated locally on 2026-07-16 without installing or selecting the private
plugin:

- one root-owned `WorkspaceService` consumes `Hyprland.workspaces` and
  `Hyprland.focusedWorkspace` for every output;
- negative special workspaces, invalid ids, duplicates and out-of-order source
  rows are normalized deterministically;
- V1 `Persist 10`, `Persist 5`, and `Active` modes preserve the focused
  beyond-range workspace without rebuilding fixed in-range models;
- V1 `Default`, `Numbers`, and `Magic` presentations use the same service and
  per-screen widget delegates;
- workspace focus accepts only integer ids from 1 through 9999 and dispatches
  the same Quattro `hl.dsp.focus` action used by the official widget through
  the host launcher;
- mode and style persist under schema-1 `bar.qsrise.workspace`; invalid values
  fail to compiled defaults without a cache file;
- the screen-local panel is lifecycle-lazy and exposes actual positive
  workspaces, focused state and window counts;
- its backend-free content passes real offscreen component loading, row/cursor
  activation and 280px segmented-control fit checks;
- service, action adapter, widget and panel own no `Process`, `Timer`, or
  `FileView`.

The actual `Ui.KeyboardPanel` cannot be instantiated with the offscreen Qt
platform because no Wayland `PanelWindow` backend is loaded. Top/bottom mapping,
focus transfer, two-output ownership and hot-unplug therefore remain real
Wayland acceptance gates rather than simulated claims.

## Layout Interaction Foundation

Validated locally on 2026-07-16 before connecting the visible group renderer:

- `LayoutModel.js` rejects malformed region sizes, duplicates, missing groups,
  unknown groups, invalid split arrays, and out-of-range split indices;
- cross-region operations swap the two V1 group identities without mutating the
  source object or moving positional split state;
- one root-owned `LayoutController` persists only through
  `Bar.mutateQsRiseConfig()` and suppresses logical no-op writes;
- structural equality is independent of JavaScript object key order, preventing
  an unchanged reset from rewriting `shell.json`;
- two simultaneous `DragSession` fixtures keep source and target state isolated
  per output while committing against the latest shared root order;
- invalid drops return the per-output ghost to its source, while same-group and
  canceled drops avoid configuration writes;
- each real `BarPanel` creates one transient session and injects it into its
  selected bar surface; styles do not own the controller or session;
- layout model, controller, and drag session own no `Process`, `Timer`, or
  `FileView`.

The subsequent renderer slice is also validated locally against a fresh
Omarchy Quattro checkout:

- all fixed G1-G15 descriptors match either an internal QS Rise component or
  an available official Quattro bar-widget contract;
- host widget settings survive group resolution and optional configured modules
  are inserted only into their declared group;
- unknown/custom host-layout entries remain visible as regional extras while
  the consumed `omarchy.menu` alias is not duplicated;
- G10 resolves as one bounded QS Rise quick-access group, while G12 battery and
  G14 power profile retain separate V1 presentations;
- one root-owned power service supplies both groups and consumes the combined
  `omarchy.power` alias, preventing per-output or cross-group worker duplication;
- disabling a multi-module group unloads its entire Loader tree, including
  optional configured Quattro children, and collapses its geometry so it leaves
  neither a stale group gap nor a split interval;
- persisted within-section splits add exactly one 16-unit growth interval;
- the real Quickshell loader smoke proves group composition and split growth;
- `GroupSlot` and `GroupSection` own no `Process`, `Timer`, or `FileView`.

The Phase 3 local suite now covers run chrome geometry, edit-mode affordances,
drag target registration, target rebinding after order mutation, the drag
ghost, invalid-drop return, and boundary split treatment. Real top/bottom plus
multi-output pointer behavior remains a Wayland acceptance gate; see
`docs/phase3-validation.md`.

## G10 Picker And Media Slice

Validated locally and against the real Quattro host on the validation system on 2026-07-17:

- one process-wide controller owns theme, wallpaper, screenshot, and video
  scan/cache/warmup state for every output;
- Tanzaku and Hearthstone own presentation only and contain no
  process, timer, or file watcher;
- icon clicks retain their originating output, while IPC/shortcut opens resolve
  the focused Hyprland output with a real loaded bar output as fallback;
- all four modes opened on `eDP-1` with populated entries and without QML load
  warnings;
- both retained QS Rise picker styles rendered on Wayland and the selected style survived
  a shell restart;
- foreground cancellation terminates converter descendants and removes lock
  and temporary files;
- closed pickers leave no `qsrise-picker`, `magick`, or
  `ffmpegthumbnailer` workers;
- the Omarchy plugin validator and the complete local contract regression pass.

Theme/wallpaper apply, screenshot/video open/copy/trash feedback, cold-cache
timing, top/bottom placement, and multi-output/hotplug behavior remain explicit
runtime gates.

## Internal Wayland validation evidence

Validated against the real Quattro host on the validation system on 2026-07-16:

- one Omarchy Shell process loaded the private development plugin on `eDP-1`;
- the full memory and CPU widgets were each present exactly once in the top bar;
- the memory panel mapped successfully on Wayland;
- the CPU panel mapped successfully on Wayland with the GPU-absent presentation;
- creating the CPU panel acquired exactly one GPU telemetry consumer;
- destroying the CPU panel released the consumer to zero;
- the probe subprocess had exited when checked three seconds after panel close;
- the temporary panel shell exited with `PANEL_SMOKE_OK` and status 0;
- the production Omarchy Shell instance remained running throughout the isolated
  panel test.

the validation system was then restored and checked:

- `~/.config/omarchy/shell.json` again had its original SHA-256
  `7b2bde9f1c7d247cd7988fc7b00a0743fb6114b16ceb181f90d30515ca9785a1`;
- the built-in Omarchy bar was active again;
- exactly one Omarchy Shell instance remained;
- the private plugin, temporary harness, backup, and probe workers were absent;
- the restored shell log reached `Configuration Loaded`.

The restored stock Quattro shell emitted existing duplicate `omarchy.*` IPC
handler and `Indicators.qml` binding-loop warnings after QS Rise had been
removed. They are host-side findings, not output from this plugin slice.

## Remaining Parity Gates

The foundation slice is runtime-valid, but full V1 parity still requires:

- compact CPU and memory visual review;
- GPU-present presentation on suitable hardware;
- `Open btop` action review in the final plugin deployment;
- bottom-bar visual and interaction review;
- a screen-local panel check with two simultaneously active outputs.
- workspace top/bottom mapping, focus/escape behavior, two-output invocation,
  and hot-unplug while the workspace panel is open.

## App Menu Contract Foundation

Validated locally and against the real Quattro host on the validation system on 2026-07-16:

- the historical combined root manifest was accepted with `bar`, `menu`,
  `bar-widget`, and `service` kinds and safe entry points; this proves the
  prototype lifecycle only and must not be treated as suite-package evidence;
- the menu implements `open`, `close`, `refresh`, `ping`, and a read-only debug
  state without creating a second `ShellRoot`;
- service injection and late `shell.serviceFor(pluginId)` resolution both work;
- the launcher uses the injected host `toggle()` API without a shell process;
- Quattro reported the plugin active and enabled with all four kinds;
- the launcher appeared exactly once and visibly on `eDP-1`;
- host IPC changed the menu from closed to route `apps` and back to closed;
- the service remained ready through summon and hide;
- the official `omarchy.menu` continued to summon and answer `ping` while QS
  Rise was active;
- exactly one Omarchy Shell instance ran throughout;
- the active test log reached `Configuration Loaded` without QS Rise errors;
- no App Menu scanner or helper process existed.

After the test, the validation system was restored to the original configuration hash, the
private plugin and backup were removed, and the official menu was summoned
again successfully. That deployment validated the lifecycle foundation only;
the local data foundation below was added afterward and has not been deployed.

## App Menu Data Foundation

Validated locally on 2026-07-16 without changing the running desktop shell:

- `DesktopEntries.applications.values` is consumed directly, including its
  QML list-like representation; no Python scanner or recurring process exists;
- desktop ids are normalized and validated before favorites, hidden state, or
  lookup use;
- favorites retain configured order, hidden entries are excluded by default,
  and duplicate desktop entries are selected deterministically after matching
  so richer duplicate metadata is not lost during search;
- the App Menu service loaded the real Quattro default JSONC source with more
  than 250 entries and resolved `system.lock` and `style.theme`;
- JSONC comments, block comments, trailing commas, URLs containing `//`,
  dotted hierarchy, aliases, explicit field clearing, provider metadata, and
  visibility/checked result application have deterministic fixtures;
- user entries override only fields they actually declare;
- malformed user JSONC falls back to the valid default tree, while a missing,
  empty, or malformed default source leaves `menuReady` false;
- the service watches the official default and user extension paths and does
  not write either source;
- the combined offscreen Quickshell service/menu/widget contract smoke passes.

## App Menu Command Runtime

Validated locally on 2026-07-16 without changing the running desktop shell:

- every menu source rebuild automatically re-evaluates `when` and `checked`
  guards in one short-lived process;
- guard state initializes fail-closed, forged or malformed result rows are
  ignored, and a forced guard-process termination leaves guarded rows hidden
  with an explicit error state;
- guard execution is bounded by `timeout` and a queued re-evaluation replaces
  stale results after a source generation changes;
- provider execution accepts only `fonts` and `power-profiles`, queues both
  through one short-lived worker, and rejects unknown provider names without
  execution;
- provider rows have bounded text and count, deterministic collision-safe ids,
  control-character removal, and shell-quoted dynamic action values;
- actions are routed through Omarchy's Hyprland launch adapter and applications
  through the validated `DesktopEntry.execute()` object;
- the service owns exactly two non-recurring processes and no timer;
- ten deterministic model runs and five complete offscreen contract runs
  passed without residual fixture or Quickshell processes.

## App Menu Visible Workflow

Validated locally on 2026-07-16 without changing the running desktop shell:

- one controller owns routes, descendant search, selection, navigation stack,
  app edit mode, invoking-screen selection, and action dispatch;
- one lifecycle-lazy surface is created on open and destroyed on close;
- the card uses Quattro UI primitives and the V1 base card/row dimensions;
- command rows, application rows, checked state, favorites, hidden state,
  provider loading/failure, and empty results render through one list;
- keyboard and pointer activation use the same controller path;
- top, bottom, and constrained-screen geometry is deterministic; defensive
  left/right calculations are not part of the V1 parity gate;
- screen changes re-resolve the requested or focused output and a missing target
  screen keeps the surface hidden;
- signalled or crashed guard/provider workers are never accepted as success;
- 20 consecutive complete contract suites passed after the process-status fix,
  with no files left in the dedicated test temp root.

The actual Wayland `PanelWindow`, visual parity, two-output invocation and
hot-unplug, bottom-position interaction, focus restoration, and 20-cycle PSS gate
remain intentionally open because no development live deployment was requested.

The V1 presentation contract is now implemented locally:

- default, gradient, and glide selection modes share the same controller and
  list delegates;
- off, search-only, and full-card wallpaper modes reuse the first-party
  `omarchy.background` service and instantiate images only with the open card;
- icon visibility and 60/80/100 percent scale settings share the same versioned
  host configuration mutation path as favorites and hidden apps;
- the same surface now owns widget enable/compact state, workspace mode/style,
  picker style, top/bottom position, split/reset actions, Reactor mode, and the
  V1 border/shadow/frost/radius/height/accent choices;
- the official-host smoke resolves `shell.bar`, mutates each settings family
  through that active controller, and verifies the resulting host configuration
  plus split/reset delegation instead of accepting a load-only settings test;
- default-off G7, G14, and G15 state survives partial widget configuration;
  disabled widget loaders instantiate no delegate, and G7's shared provider
  service is not constructed while G7 is disabled;
- the long settings content is bounded by a vertical `Flickable`; an official-
  Quattro offscreen smoke proves content height exceeds the viewport while the
  card remains within its available screen height;
- the inline settings surface, both wallpaper loaders, all three selection
  contracts, background service lookup, and invalid-setting rejection pass the
  offscreen card/contract smokes;
- visual acceptance of those modes on real Wayland remains open.

## G6 Audio Presentation Bridge

Validated locally on 2026-07-16 without changing the running desktop shell:

- G6 resolves one `hancore.qsrise.audio` composite and consumes the original
  `omarchy.audio` layout alias, preventing a second visible audio widget;
- the composite loads the registered official audio component as its hidden
  state/action adapter; the official popup and its open-only workers remain
  closed;
- the host facade suppresses only the hidden stock button's click-target
  registration; the V1 QS Rise surface registers exactly one target;
- full and compact layouts have stable, distinct widths and preserve V1 label,
  slider, percentage, and compact-glyph structure;
- the lazy QS Rise panel restores output/input volume, output/input device
  selection, per-app volume and mute, microphone mute/meter, and descriptive
  device labels over the official state and commands;
- right-click mute, wheel volume, open/close, host settings, screen-aware alias
  routing, unavailable-backend behavior, model actions, and teardown pass the
  offscreen component smoke;
- no local audio process, recurring poller, PipeWire device model, or MPRIS
  model exists. One 75 ms list-settle timer and one open-only microphone peak
  monitor are presentation lifecycle helpers, not competing backend owners;
- the current Quattro source exposes every required list, state, label, and
  mutation contract, and the Qt 6 linter resolves the new panel without type or
  incompatible-child errors.

The local mixer contains a `KeyboardPanel`, which cannot be instantiated under
Qt's offscreen platform because no `PanelWindow` backend exists. Real Wayland
visibility, anchoring, top/bottom behavior, panel switching, device changes,
microphone meter behavior, and multi-output ownership therefore remain explicit
acceptance gates rather than being represented by a false offscreen smoke.

## G9 Media Service/View Boundary

Validated locally on 2026-07-16 without changing the running desktop shell:

- G9 resolves one `hancore.qsrise.media` presentation and consumes the
  original `omarchy.media` bar alias while leaving the keep-loaded official
  service authoritative;
- no local view imports MPRIS or PipeWire, and no closed-panel worker, timer,
  or file watcher exists;
- V1 idle/active presentation, track metadata, play/pause, previous/next,
  wheel actions, source selection, lazy panel loading, one click target, and
  teardown pass the offscreen component smoke;
- a bounded one-shot capability/default-sink probe and the optional direct
  Cava process are structurally gated by panel-open plus playing state; Cava
  receives its configuration through stdin, so neither path creates a temp
  config artifact;
- an isolated real-session probe produced a valid 12-band raw frame from the
  current default-sink monitor, then restored the exact pre-test Cava PID set;
- the current Quattro media service still exposes `activePlayer`,
  `sourcePlayers`, `runAction`, `playerKey`, and `selectPlayer`.

The product `MediaPanel` uses `KeyboardPanel`, whose `PanelWindow` backend is
not available under Qt's offscreen platform. The smoke therefore uses a narrow
panel lifecycle fixture and does not claim to render the product window. Qt-6
lint plus the official service contract cover static correctness; real Wayland
visibility, spectrum execution, top/bottom placement, panel switching, and
multi-output ownership remain explicit acceptance gates.

## G3 Status Composition

Validated locally on 2026-07-17 without changing the running desktop shell:

- G3 resolves one `hancore.qsrise.status` container and consumes the original
  `omarchy.tray` and `omarchy.notifications` aliases; the consumed
  `omarchy.system-update` alias is presented by G8 as in V1;
- the container loads each registered official G3 component once and forwards
  its original host settings instead of copying SystemTray, notification, DND,
  history, SNI-menu, or action logic;
- local V1 tray icons, hidden-app drawer, bell, and badge read the official
  component state and forward all actions to those owners;
- the common V1 pill has deterministic width as tray children appear or
  disappear; its layout does not depend on inherited child visibility or stale
  Loader implicit widths;
- three visible child actions remain three registered click targets, while the
  container adds no competing target, worker, watcher, or service owner;
- nested notification open/close routing, child identity/settings, dynamic
  width, unavailable loading, popout cleanup, and destruction pass the
  offscreen component smoke;
- the current Quattro sources still expose the update, tray, and notification
  state/action properties consumed by the composition.

Actual SNI menus, notification history/actions, DND mutation, top/bottom popup
placement, and multi-output ownership remain real-Wayland acceptance gates.

## G8 Center Composition

Validated locally and on the validation system through 2026-07-20:

- G8 renders one local V1 center pill with weather, clock/date/calendar,
  active-only status indicators, and the Omarchy update indicator;
- the registered weather and update components remain hidden backend/action
  owners. The local update facade adds no process, timer, IPC handler, or
  competing detector and delegates activation exactly to `runUpdate()`;
- the local calendar is lifecycle-lazy and forwards Tab/Shift-Tab to the
  shared sibling-panel router;
- local component tests cover normal/compact/minimal staging, update facade
  visibility/tooltip/action forwarding, recording elapsed formatting, and all
  four status action boundaries;
- on the validation system's top-position eDP-1 output, the weather panel opens and closes,
  the real Omarchy update-available state is visible, and reversible official
  idle/DND mutations changed the center width from 151 to 207 and back to 151;
- a clean shell restart ended in `Configuration Loaded`, with no new QML or
  JavaScript errors and no diagnostic IPC hook left in the runtime.
- the validation system exposes the complete Quattro command contract for recording and
  Voxtype. Exactly one long-lived `voxtype status --follow --extended --format
  json` process runs below the shared Quickshell service and reports the real
  inactive snapshot; no duplicate QS Rise poller or probe process remains.
- a reversible Bottom-position test rendered the complete bar and the G8
  calendar above the center island without overlap or clipping. The original
  `shell.json` was restored byte-for-byte after the screenshot.

Recording-active behavior is accepted through the physical G8 indicator click,
including valid MP4 finalization and complete test-artifact cleanup. Active
dictation also passed `recording`, `transcribing`, and `idle` with text
insertion. the validation system has no second output. Remaining Bottom panels,
edit/split/drag, mixed scale, and physical multi-output remain explicit
acceptance gates. Tooltip
content is covered by the component contract, not claimed as visual evidence
because the runtime screenshot attempt was interrupted by the host
screensaver.

## Representative Bottom Placement

Validated on the validation system on 2026-07-20 using the real 1920x1080 eDP-1 Wayland
output:

- the complete QS Rise bar rendered at the bottom while preserving all G1-G15
  islands and the centered G8 composition;
- the G1 Control Center opened above the left island, the G8 calendar opened
  above the center island, and the G11 Network panel opened above its right
  widget anchor;
- none of the three cards overlapped the bar or exceeded the output bounds;
- each panel was opened and closed through the real `shell` IPC routing path;
- the test restored the exact original `shell.json` SHA-256 and left the bar
  service active at the original Top position.

This is representative Bottom evidence, not a blanket pass for every panel.
Edit mode, split/drag, remaining panels, mixed scale, and physical
multi-output behavior remain release gates.

## G11 Shared Network Service And Panel

Validated locally and on the validation system on 2026-07-18:

- G11 resolves one `hancore.qsrise.network` presentation, consumes the
  original `omarchy.network` alias, and preserves a configured optional
  `omarchy.tailscale` sibling;
- one root service loads the registered official network component; two-output
  regression fixtures still create exactly one backend owner while retaining
  one screen-local click target and popup per output;
- the host facade suppresses the hidden stock button, popup, and IPC handler.
  Screen-local widget/panel files contain no Networking import, process, or
  file watcher;
- V1 full Wi-Fi (`NET`, signal, SSID), full Ethernet (link/interface), and
  compact connection-state presentations react to official exported state;
- the lazy QS Rise panel exposes active-route details, ping/throughput, DNS,
  speed test, available and saved networks, inline PSK, connect/disconnect,
  confirmed forget, and a network-settings fallback;
- saved invisible profiles are queried once at open/rescan through the real
  NetworkManager CLI. The 1.5-second open-only sampler updates only verbose
  route details and cannot restart DNS/profile work;
- left/right click, legacy `omarchy.network` alias routing, two screen-local
  sessions, state propagation, final-close worker cancellation, and destruction
  cleanup pass the component regression;
- Quattro's validator and the complete contract suite pass on the validation system. A real
  top-anchored panel shows correct metrics, saved count, expanded security/
  signal/saved metadata, and no warning/error log; close leaves no `nmcli` or
  speed-test worker.

Connection mutation, inline authentication, DNS/speed-test execution, bottom
placement, and physical multi-output acceptance remain runtime gates. V1's
separate permanent Ethernet poller is intentionally not restored.

## G13 Shared Monitor Ownership And Local Panel

Validated locally and on the validation system on 2026-07-18:

- `Bar.qml` creates exactly one root `MonitorService`, which owns exactly one
  hidden instance of the registered official `omarchy.monitor` component;
- that official component remains the sole state, action, IPC, polling, scale,
  display, and brightness owner. Its stock button and popup are suppressed;
- each output owns only the V1 full/compact brightness view and a lazy local
  `BrightnessPanel`. The screen-local slice creates no process, timer, file
  watcher, UPower model, or competing monitor owner;
- the local panel covers brightness slider and five-percent steps, scale
  choices, display enablement, refresh/close, keyboard navigation, and the
  no-backlight display-control fallback;
- two-widget ownership, lazy panel teardown, wheel/preview/set actions, scale,
  display toggle, alias routing, compact layout, and unavailable state pass the
  component regression;
- the complete contract suite, Qt 6 lint, plugin validation, and live/repo
  comparison pass on the validation system;
- the real top-anchored panel maps to the invoking BRI widget without clipping
  or log errors. A real laptop brightness mutation completed and was restored
  exactly (`57 -> 62 -> 57`), and closing left no monitor or brightness worker.
- the visible panel completed a real `1.0 -> 1.25 -> 1.0` scale round trip.
  Hyprland state, the complete shell configuration hash, shell PID, and crash
  count returned unchanged; the single-display safety gate correctly refused
  disabling the last physical output.

Physical display enable/disable, desktop/no-backlight hardware, and physical
multi-output ownership remain real-session acceptance gates.

## G12/G14 Shared Power Ownership

Validated locally on 2026-07-17 and checked read-only against Machine1 and
the validation system:

- Machine1 has no laptop battery but exposes `power-saver`, `balanced`, and
  `performance`, proving G14 must not depend on G12 visibility;
- the validation system exposes a charging BAT0 through UPower plus the same three profiles
  through the installed Quattro helper contract;
- a later physical transition captured `BAT0=Discharging`, AC offline, and the
  matching UPower/helper state before the charger was connected. Kernel sysfs,
  UPower, and the helper then agreed on `Charging` at 37.9 W with about 31
  minutes remaining; the user confirmed the live widget bolt and panel state;
- `Bar.qml` creates exactly one `PowerService`; every output's G12/G14 view
  binds to that same object;
- battery percentage, state, health, rate, and time are event-driven UPower
  properties; `omarchy-battery-status --shell` is acquired only while a
  battery panel is open;
- the shared profile refresh runs once per bar process, not once per output or
  widget, and `powerprofilesctl set` receives only a profile returned by the
  validated helper list;
- the V1 battery and power-profile panels are separate and screen-anchored;
  opening one transfers popout ownership from the other;
- desktop/no-battery, laptop/charging, compact/full geometry, right-click
  profile cycling, battery removal, shared-service identity, and panel-detail
  lifecycle pass the offscreen power smoke;
- battery/profile views and panels contain no UPower import, process, timer, or
  file watcher.

Real charge/discharge and profile mutations are accepted. Two-output
interaction remains a controlled Wayland acceptance gate.

## G15 Shared Bluetooth Service And Local Panel

Validated offscreen and on the validation system on 2026-07-18; backend
ownership was replaced and revalidated on 2026-08-06:

- G15 creates one root `BluetoothService` and one native
  `BluetoothBackendAdapter` for the entire process;
- the Shibumi adapter is the only BlueZ, pairing, pending-action, discovery,
  and Bluetooth-audio owner. It uses Quickshell's Bluetooth/PipeWire models
  plus the validated Omarchy device/audio helper commands; no complete stock
  Bluetooth component or second IPC handler is instantiated;
- every output consumes the same service and lazily creates only its own V1
  widget and QS Rise device panel;
- discovery starts for the first open panel and stops after the final panel
  closes. Ownership is confirmed only from observed discovery, and bounded
  reconciliation covers rejected starts, external stops, and adapter changes;
- one process-wide `omarchy.bluetooth` IPC handler exposes all six methods;
  open/show/toggle/close/hide route symmetrically to the local panel and
  `toggleBluetooth` owns the radio action;
- full/compact geometry, two-output session accounting, native action routing,
  missing-adapter cleanup, and worker-free ownership pass the component smoke;
- the validation system proves one IPC target, top panel mapping, real adapter/radio
  reactivity, discovery start/teardown, and a clean runtime log.

Pair/connect/disconnect/forget with real devices, Bluetooth default-sink
switching, bottom placement, and physical multi-output interaction remain
controlled hardware acceptance gates.
