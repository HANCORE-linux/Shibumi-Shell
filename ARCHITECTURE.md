# Shibumi architecture

> **Document status: Canonical product and architecture contract.** This file
> is the single source of truth for Shibumi. Supporting documents may add
> implementation detail or validation evidence, but they may not override the
> premises and release gates defined here.

## Documentation Authority

Use this order when documents, tests, or historical reports disagree:

1. `ARCHITECTURE.md` defines the product boundary, non-negotiable behavior,
   ownership model, and release gates.
2. Machine-readable contracts and the current source define exact schemas,
   plugin IDs, defaults, and executable behavior.
3. Normative supporting contracts under `docs/` define one bounded surface in
   more detail.
4. `docs/release-readiness.md` and current parity matrices record acceptance
   evidence and remaining gates.
5. Phase reports and local files under `~/Projects/Reports` are historical
   evidence. They do not change the current contract.

[`docs/README.md`](docs/README.md) classifies every supporting document and
provides the canonical reading order. A product decision made in a discussion
is not binding until it is recorded here or in a linked normative contract.

## Canonical Product Premises

These premises apply to every implementation, review, and release decision.

### Product and repository boundary

- QS Rise V1 remains the standalone Arch Linux and Hyprland reference product
  in the separate `Quickshell-Dots` repository. It has its own installer,
  updater, lifecycle, and release history.
- Shibumi is the native Omarchy Quattro plugin suite in this repository. It
  runs inside the existing Omarchy Shell process and never starts a second
  `ShellRoot` or Quickshell shell.
- Shibumi is an independent third-party project. It is not an official Omarchy
  product, an official Omarchy bar, or a Basecamp-maintained plugin.
- Shibumi may port approved host-neutral behavior from QS Rise V1. The products
  do not share deployment paths, update state, or platform ownership code.
- This repository contains 24 independently registered runtime plugins. A
  transactional suite adapter bridges Quattro's current one-repository to
  one-plugin installation limit.
- Future Shibumi bars use separate `bar` plugin IDs and reuse the same feature
  plugins, services, panels, and host facade. A new bar must not fork feature
  ownership or persistence.
- Private alpha commits may retain explicitly documented physical or
  credential-dependent gates. The repository must remain private until every
  public-release gate in this document and `docs/release-readiness.md` passes.

### QS Rise V1 parity and quality

- The approved current QS Rise V1 implementation is the normative UI, UX, feature,
  and interaction reference for the default `hancore.shibumi.bar` plugin.
- Native Quattro services may replace V1 backends. They may not replace the V1
  presentation with stock Quattro visuals or remove an approved workflow.
- Shibumi may improve reliability, ownership, or resource use, but it may not ship
  a visible or functional quality regression compared with V1.
- Every widget, tooltip, panel, menu, picker, empty state, degraded state, and
  error state must match the V1 information hierarchy and interaction outcome.
- Panel actions remain open when V1 keeps the panel open. Only explicit close,
  Escape, outside dismissal, or a workflow that deliberately transfers focus
  may close a panel.
- A backend being functional does not establish parity. The visible surface,
  actions, focus behavior, Top and Bottom placement, and output routing must
  also pass.

The detailed visual contract is
[`docs/v1-presentation-contract.md`](docs/v1-presentation-contract.md). The
current feature status is tracked in
[`docs/v1-parity-matrix.md`](docs/v1-parity-matrix.md) and
[`docs/v1-widget-parity-audit.md`](docs/v1-widget-parity-audit.md). A dated
comparison with the current read-only V1 working tree belongs in
[`docs/current-v1-discrepancy-audit.md`](docs/current-v1-discrepancy-audit.md);
an uncommitted reference change is a parity candidate, not a stable release
baseline.

### Layout And Default Composition

- Shibumi supports horizontal Top and Bottom bars. A vertical bar is not a V1
  feature and is outside the Shibumi product contract.
- The default order is `G1-G7` on the left, `G8` in the center, and
  `G9, G10, G11, G14, G12, G13, G15` on the right.
- V1 can explicitly add one center slot in edit mode: at most two center
  positions total. The default remains G8 alone; existing saved layouts are
  not expanded on load. Only an empty extra slot can be removed. Center slots
  use the existing drag/drop and gap treatment. A two-position center exposes
  one positional split with the existing marker and spacing. Missing
  `splits.center` migrates to a disabled array of the required length without a
  settings-schema version bump; an explicitly malformed field rejects the V1
  layout as a unit. G8's width budget excludes its center
  sibling; when G8 is disabled or has no loaded widget, the first loaded,
  stage-shown center group owns the remainder. Owner selection uses loading
  readiness, not its budget-dependent geometry, to avoid binding feedback.
  Compaction remains output-local and never rewrites the layout.
  Automatic outer plugin allocation is unchanged. A center-bound provider
  may use an already added empty center slot, but cannot grow it implicitly.
  When removing a provider from a base position, automatic repair requires
  exactly one occupied extra containing a fixed group. Multiple occupied
  extras are ambiguous without swap history: refuse without mutation. Users
  can move the provider back into an extra before removing it. No provenance
  field, saved-layout migration or V2 removal change is introduced. The
  Control Center preflights installed V1 bar widgets before starting plugin
  uninstall; bar removal still revalidates the layout at its own mutation.
- All split boundaries start disabled. Split markers, drag targets, invalid
  returns, persistence, and geometry must retain the V1 behavior.
- V1 and V2 own independent optional layout-protection preferences. Both
  default off to preserve direct live editing. When protection is enabled for
  the active generation, direct split, divider, and section-boundary clicks on
  the bar require that output's explicit edit mode; the Control Center's
  deliberate bulk and restore actions remain available.
- G7 AI usage, G14 power profile, and G15 Bluetooth start disabled. Other
  groups start enabled. Hardware-dependent widgets may remain hidden when the
  required hardware is absent.
- Responsive hiding is temporary presentation state. It must not rewrite the
  stored group order, enabled state, compact state, or split state. Its width
  budget includes unassigned provider entries in all three regions; center
  extras reduce the grouped center's available width. The existing stage
  priorities remain unchanged, including when the final stage cannot fit.
- A newly placed V1 family alternative reuses one displaced fixed group slot
  instead of requiring an additional dynamic slot. The fixed slot retains its
  order and drag identity; the alternative retains its own settings and host
  surface. Existing explicit dynamic placements are not silently migrated.
  Multiple providers cannot share one slot. New V1 managed family replacements
  require single-instance manifests: an `allowMultiple` family request is
  refused before layout, registry or family-state mutation. Existing layouts,
  unrelated multi-instance entries and V2 retain their behavior.
  On scoped hosts, each `WidgetSlot` binds the exact configured layout ID
  directly to its accepted `barWidgetRegistry.widgets[id].component` and
  metadata. It checks the actual Component type, not its JavaScript `status`
  projection. Republication of the same handle leaves the Loader item intact;
  replacing the handle produces one controlled Loader submission. Success
  still requires the current Loader's Ready state and exact submitted-source/
  completed-item provenance; a handle alone is not readiness. State
  publication, structural layout, and catalog acquisition are separate
  reaction paths. Scoped bar/config and registry fan-out do not start catalog
  reads; explicit requests and the five-second demanded reconcile do.
  Missing registration stays empty until the registry publishes it; an original must
  never substitute for a clone. Composite G3 is the sole nested-Component
  exception: only while `hancore.shibumi.status` is configured may its explicit
  owner-bound route consume scoped `hancore.shibumi.update-center` and
  `omarchy.tray` Components. They remain unavailable through ordinary
  unconfigured lookup. Clone ancestry comes from public `listPlugins`,
  with cycle detection and a 32-entry traversal bound, not fabricated foreign
  manifests or executable paths. Native IPC owns enable/disable and clone
  restoration; the active Bar owns layout edits and confirms its injected
  `barConfig`. No shared catalog/config revision or universal CAS is assumed.
  Older full-registry hosts retain their admitted manifest route. Missing
  selections, conflicting families and duplicate single-instance entries are
  refused before mutation. The pinned 4.0.3 fixture covers scoped catalog and
  selected-provider flows; package-bound physical acceptance remains open.
  Family replacement does not increase capacity; the separately approved
  optional V1 center slot follows
  the limits above. V2 layout semantics remain unchanged, and the settings
  schema stays at version 1.
- G1 is the Shibumi wordmark and Control Center. Omarchy remains the sole owner
  of the application launcher menu; G1 neither owns nor opens it.
- G1 exposes the current V1 palette contract: colors 01-07 plus foreground,
  contrast-aware swatch labels, and the four-column picker. Color01 is the
  fresh default. Palette values are semantic theme roles, not persisted raw
  colors.
- G3 owns the V1 tray and notification presentation over the official owners.
  G8 owns the Omarchy update presentation.
- G9 retains the default media row and the selectable current V1 FULL/muse
  outcome: 24-band real Cava, vinyl mark, transport state, click play/pause,
  and wheel previous/next. Missing Cava must degrade without breaking media
  actions or leaving a worker.
- G10 owns the V1 quick-access workflow and the Tanzaku and Hearthstone picker
  views. Quattro retains ownership of its native carousel picker.

The exact G1-G15 owner and feature map is
[`docs/phase2-ownership-map.md`](docs/phase2-ownership-map.md). Executable
defaults live in `hancore.shibumi.state/ShibumiConfig.js` and
`contracts/plugin-suite-v1.json`.

The procedure for registering another Shibumi bar without duplicating feature
ownership is [`docs/multi-bar-extension-plan.md`](docs/multi-bar-extension-plan.md).

### Presentation And Interaction

- Colors, borders, radii, shadows, typography, spacing, icons, hover states,
  selected states, and disabled states use Shibumi semantic tokens mapped from
  the active Omarchy theme.
- Controls that serve the same role use the same dimensions, radius, border,
  fill, font, icon treatment, and interaction feedback across every panel.
- Tooltips and panels follow the invoking widget and output. Their edge follows
  the selected Top or Bottom bar position.
- Panels use one routed popout owner per output. Opening a sibling replaces the
  current panel; unrelated outputs retain independent state.
- Non-Shibumi widgets hosted by the Shibumi bar use one provider-neutral
  compatibility adapter for standard Omarchy panels. Quattro built-ins and
  third-party plugins receive the same active bar connection, panel surface,
  border, radius, and tooltip treatment without plugin-specific patches.
  Plugins that do not expose the standard panel contract require an explicit
  host-wrapper contract rather than visual heuristics.
- Icons must use the approved V1 asset or icon family and preserve V1 optical
  size and alignment. A semantically similar stock icon is not sufficient when
  it changes the Shibumi identity.
- Motion must reproduce the approved V1 behavior. Ports may not add decorative
  transitions, carousel motion, or continuous animation without a separate
  product decision and performance evidence.
- Compact mode removes only content explicitly omitted by V1. It must not
  change the underlying action, tooltip, state owner, or panel contract.

### Runtime, Outputs, And Lifecycle

- On the scoped 4.0.3 host, the admitted shared Runtime performs one exact-PID
  public `shell.rescanPlugins` prime per Quickshell process before the Shibumi
  bar becomes ready or visible. The first Bar owner stays unavailable; success
  requires IPC acknowledgement and a newly admitted Bar owner after the host
  rebuild. Missing replacement, timeout, nonzero exit, payload retirement, or
  scope loss fails terminally for that startup prime. No second rescan is
  dispatched after output loss: valid current host Components are submitted
  directly to the output-local Loader, including when their JavaScript status
  projection is unavailable. A proved `>0 -> 0 -> >0` transition and exhaustion
  of the existing resolution retries for a previously loaded, still-configured
  and enabled widget may emit one passive sanitized warning per process. This
  starts no work and cannot replenish the startup-prime budget. There is no
  retry, settings-time rescan, stale Component retention, private registry
  access, lock IPC probe, or second shell process.
- One shared controller creates one bar per real output and rejects placeholder
  or zero-sized outputs.
- Screen-local panels, pickers, tooltips, focus, input masks, and drag state
  follow the invoking output and are destroyed when that output disappears.
- Hotplug, hot-unplug, Display Power Management Signaling (DPMS), suspend,
  hibernate, resume, mixed scale, and portrait or narrow outputs must not create
  duplicate bars, orphan panels, stale owners, or persistent layout changes.
- A lost layer window is recovered at the affected output boundary. The whole
  shell is not restarted for a local window failure.
- Automatic reconnect after a physical multi-monitor disconnect is not a QS
  Rise requirement. Correct cleanup and a working manual reconnect path are
  required.

The lifecycle contract and uncompleted physical gates are defined in
[`docs/v1-output-lifecycle-audit.md`](docs/v1-output-lifecycle-audit.md).

### Ownership, Performance, And Safety

- Every platform capability has one authoritative state and action owner.
  Quattro or Quickshell remains authoritative when it exposes a sufficient
  service contract.
- Shibumi adds a narrow adapter only when the host contract cannot produce the
  V1 outcome. It does not instantiate a second tray, notification daemon,
  audio owner, network owner, media owner, or equivalent platform backend.
- Views do not execute platform commands directly. Services own commands,
  validation, cancellation, timeouts, and structured parsing.
- All QML loaded into the single Quickshell process is inside one trust boundary.
  Service facades are ownership and supported-API boundaries, not a sandbox:
  same-process plugin code can traverse and mutate the QObject tree. Containing
  malicious installed QML is a host concern and a non-goal for these facades;
  external command output still crosses bounded, validated parsers.
- Polling, file watching, and worker processes are process-wide and shared
  unless the state is genuinely output-specific.
- Closed panels and pickers release UI-only timers, scanners, peak monitors,
  thumbnail workers, video resources, and transient models.
- Event-driven state is preferred. Every reconcile timer requires a documented
  interval, owner, activation condition, shutdown condition, and measured need.
- Inputs are never interpolated into unquoted shell commands. Cache and state
  files use versioned schemas, validation, bounded data, and atomic writes.
- Install, update, rollback, and uninstall are transactional. A failed update
  restores the prior working suite and does not invent or overwrite user state.
- Managed activation records the preceding bar object. Deactivate and uninstall
  restore that object; older state schemas use Quattro's current stock bar as a
  compatibility fallback rather than synthesizing an empty layout.
- Every bar-owner transition uses Quattro's full restart boundary, including
  rollback and interrupted-transaction recovery. Managed install, migration,
  update, and repair drain the exact production shell before publishing plugin
  roots; they never stop a shell after starting asynchronous plugin discovery.
  Live reload is reserved for mutations that keep the active bar owner.
- Before recovery or any other lifecycle mutation, the release lifecycle
  inventories every public and private transaction journal and classifies the
  install by revision, complete plugin digests, activation metadata, and
  journal schema. Beta.13 admits only the exact public Beta.11, Step-5-tip, and
  current-release identities. Step-6 Power registration, Step-6 journal fields
  or phases, partial cross-release markers, and unknown states fail closed
  without discarding or recovering any journal. One admitted public journal may
  explain an exposed target/state mismatch; recovery consumes its validated
  snapshot and live identity is checked again before the requested operation.
  Rollback and commit artifacts are role-bound to exact pre-mutation digests.
  Schema-2 journals additionally bind the configuration parent by device and
  inode. The lifecycle holds that parent descriptor, performs `shell.json`
  reads and writes relative to it, and rechecks its path identity before
  recovery, reconciliation, and retirement boundaries. Rollback snapshots are
  bounded regular files opened without following symlinks and remain bound to
  their admitted inode and digest. Recovery atomically quarantines and
  revalidates backups, preserves the live target until post-restore validation
  succeeds, and validates archive namespaces before commit cleanup. Detected
  public-target, artifact, or configuration-parent authority loss stops the
  operation without deleting a replacement. More than one public journal is
  ambiguous and fails closed.
- Step-6 development installations are not downgraded or migrated by Beta.13.
  They require a separately reviewed rollback that compares every target
  identity and preserves intervening foreign or user changes.

### Release Decision

- Static lint, fixtures, and component smokes are necessary but do not replace
  physical runtime acceptance for session policy, hardware, output, suspend,
  or Wayland behavior.
- the validation system is the disposable Omarchy Quattro runtime target. The primary V1
  machine and the `Quickshell-Dots` working tree must not receive Shibumi
  deployment or source changes during development.
- A release candidate requires a clean fresh install, update, rollback,
  uninstall, shell restart, Top and Bottom pass, panel and picker lifecycle
  pass, resource pass, and every non-deferrable hardware and output gate.
- Known gaps must be recorded in `docs/release-readiness.md`. A missing test is
  not converted into a pass by plausibility or a green fixture.
- Release archives are bound to the accepted commit and carry a complete
  inventory and checksum. Tag publication first creates a draft, downloads and
  verifies the exact remote asset name/size/digest inventory, and publishes
  only after that comparison succeeds. Server-side rules must prevent updates
  or deletion of published `v*` tags.

## Product Boundary

Shibumi is a third-party native plugin suite for Omarchy Shell. Its default product
includes a full-bar plugin, independently registered widgets and services, and
a separate G1 Control Center. Omarchy's application menu remains authoritative;
Shibumi registers no competing `menu` entry point. It is not a second
Quickshell process and it is not a repackaged copy of QS Rise V1.

The production `shibumi` style must reach visual and behavioral parity with the
approved QS Rise V1 reference: its information hierarchy, compact
presentation, split and drag behavior, panels, pickers, and approved feature
set. Shibumi deliberately uses its own name and G1 wordmark. That identity
change does not permit a reduced feature or interaction contract.

QS Rise V1 and Shibumi have separate repositories, release histories, installers, update
paths, and issue scopes:

- QS Rise V1: standalone Arch and Hyprland shell with optional Omarchy integration
- Shibumi: third-party native Omarchy Shell full-bar plugin suite

Only behavior proven to be host-neutral should move from QS Rise V1 to Shibumi. A port must
be adapted to the Shibumi ownership model rather than copied together with QS Rise paths,
hooks, polling, or lifecycle scripts.

### Compact Enforceable Backend Boundary

The machine-readable boundary contract is
[`contracts/backend-boundary-v1.json`](contracts/backend-boundary-v1.json). It is
the only repository boundary source for production dependency classification;
it is not a status system and does not replace the suite contract or release
readiness record. `scripts/check-production-boundary` loads that manifest and
fails closed on malformed or incomplete declarations.

Every mutable capability declares one owner, its current backend boundary, its
output cardinality, and its worker policy. Production dependencies are classified
as exactly one of `hostIntegration`, `nativeApi`, `omarchyBackend`,
`omarchyAction`, or `hostOwnedProvider`. A transitional `omarchyBackend` must
name a known backend, an explicit `removalStep`, and a reason. The manifest's
transition ledger locks every declared transition capability and dependency to
that classification, so a transition cannot be silently reclassified without a
boundary-contract change. Process-wide Shibumi owners must also expose a valid
service manifest. New categories, owners, backend identities, host providers,
or undeclared occurrences fail the lint rather than becoming implicit
compatibility debt.

The only host-owned provider exceptions are Omarchy Notifications, OSD, and
Idle. Their provider identities, owners, allowed forms, process-wide cardinality,
and host-owned worker policy are declared explicitly in the boundary manifest.
No other `firstPartyServiceFor`, private provider QML, hidden component, helper
state poller, or output-duplicated capability owner is permitted. OSD remains an
explicit host summon/IPC action; it is not a Shibumi provider.

The production lint runs in source and package gates. It checks exact reviewed
occurrences, private component paths, provider and first-party service calls,
Omarchy commands, helper-backed state markers, package escapes, symlinks, UTF-8
source, transition-ledger consistency, and process-wide owner manifests. The
lint verifies declared output cardinality and worker policy; it does not claim
to prove runtime process cardinality or live worker behavior. Compatibility debt
may be removed by a later migration step, but it may not be broadened silently.
This boundary slice does not activate Audio, Network, Bluetooth, or any other
backend cutover.

## Why A Full-Bar Plugin

Replacing individual widgets on Omarchy's built-in bar is the lower-risk choice
when a product only changes widget content or visual tokens. Whiterose documents
that approach correctly and deliberately keeps the built-in bar as its host.

Shibumi has a different boundary. Its split layout, section chrome,
drag-and-drop model, per-screen panel behavior, and picker integration are core
product behavior rather than a collection of replacement widgets. These are the
reasons to accept the additional responsibility of a full-bar plugin.

The decision is conditional: Shibumi must prove that it preserves the host contracts
listed in this document. A feature that Omarchy already owns better should use
the host service or widget registry rather than be reimplemented merely because
Shibumi controls the bar window.

## Verified Host Contract

The installed loader and installation contracts were rechecked against
the validation system's Omarchy Quattro package `4.0.0.r1458.gfa6b5fc-1` on 2026-07-30.
The plugin registry, validator, installer, bar selector, bar loader, and
manifest contract remain compatible. Quattro now provides per-plugin setup
menus and `barWidget.defaultSection`, but still does not update or protect a
multi-plugin repository as one dependency set. Shibumi therefore owns its
transactional source-update and repair adapter. Shibumi consumes the extracted
`omarchy.notifications` service directly instead of loading its removed bar
widget, and delegates enterprise 802.1X credentials to Quattro's official
network owner. The complete contract suite and focused real-session adapter
checks pass.

- Each runtime plugin directory contains its own schema-version-1
  `manifest.json` and declares only its supported kinds.
- Current `omarchy plugin add` maps one Git repository to one root plugin; it
  does not install a multi-plugin repository.
- Shibumi therefore uses a repository-owned transactional bundle installer to
  stage its independently validated plugin directories until Omarchy provides
  a supported multi-plugin source command.
- Generic Omarchy plugin enable, disable, and remove actions operate on one
  Shibumi root and do not replace the bundle lifecycle.
- The bar entry point is an `Item`, not a `ShellRoot`.
- Omarchy loads third-party bars asynchronously and then injects supported
  properties.
- A third-party bar must therefore provide safe construction defaults instead
  of `required` host properties.
- The shared runtime owns one process-singleton `omarchy.bar`
  visibility-nudge handler, enabled only for the one fully admitted active
  Shibumi bar. It exposes only `syncHidden`, which asks that owner to re-read
  Omarchy's host-owned `bar-off` marker after `omarchy-toggle-bar` changes it;
  the directory watcher remains the ordinary update path. Incoming ownership
  arms only after the bounded host-handler handoff window; changing the
  host-injected bar identity revokes outgoing ownership synchronously.
  Overlapping or shutting-down Bar lifetimes fail closed instead of registering
  two targets.
- Omarchy falls back to `omarchy.bar` when a selected third-party entry point
  fails to load.
- Plugin code is unsandboxed and executes inside the Omarchy Shell process.
- Plugin payloads may not contain symlinks.

Host-injected properties used by Shibumi:

```text
omarchyPath
shell
manifest
pluginRegistry
barWidgetRegistry
barConfig
```

`barConfig` is host-owned. Shibumi consumes supported fields and requests
mutations through the host API; it must not maintain a competing `shell.json`
representation. `bar.transparent` is exclusively the saved transparency
preference of `omarchy.bar`. Shibumi V1 and V2 ignore it, render opaque, expose
fixed-false compatibility facade values, and never create, remove, or rewrite
the saved preference.

### Configuration and reset behavior

- Canonical settings live in the unique `plugins[]` service entry
  `{id: "hancore.shibumi.state", shibumiStateSchemaVersion: 1, shibumi: {...}}`
  inside the host-owned `shell.json`. State is the single runtime writer under
  both bars, using its own scoped `updateEntryInline` capability and preserving
  all unrelated entry fields. There is no Bar broker or second settings store.
  The numeric schema value is 1 (JSON `1.0` is equivalent); booleans and strings
  are invalid canonical versions. The sibling `bar.transparent` preference
  remains stock-bar-owned and survives lifecycle operations unchanged.
- The drained suite lifecycle migrates legacy `bar.shibumi` once when canonical
  settings are absent. A bare State entry does not block that import; invalid
  canonical data refuses rather than falling back. Runtime never migrates.
  Installation metadata `settingsStorageVersion: 1` is bound to the admitted
  payload identity and prevents current repair/update paths from resurrecting
  legacy data after destructive native disable. The current lifecycle refuses a
  legacy-storage target even with `--allow-downgrade`, and there is no reverse
  export. This does not make a package-manager rollback to older lifecycle code
  safe: Pacman replaces that guard before the user transaction runs. Beta.12 is
  the first package with canonical storage and has no eligible older package
  target. Transaction failure/recovery still restores its complete original
  snapshots.
- Two process-wide read-only FileViews watch the user document and official
  defaults. Only a missing or zero-length user file falls back to defaults;
  corrupt or unreadable data refuses. Reads spawn no subprocess. The 75 ms
  debounce merges rapid setters against pending intent; a fresh complete entry
  is read before dispatch. Each dispatch/readback has a two-second deadline.
  Setter `true` means queued, not saved. Published config/revision remain
  file-backed, with explicit pending/status/serial and settlement notification;
  a native `false` can mean unchanged and requires matching file readback too.
  Scope loss cancels queued work. Reversible Active/Inactive organizer intents
  use the requested-state/coalescing path directly while structural layout and
  provider transitions remain serialized; file readback still owns canonical
  config and rollback. Full-entry readback is not an fsync guarantee, a generic
  CAS contract, or a bound on FileView's acquisition allocation.
- The one-time migration renames `hancore.qsrise.*` IDs, `bar.qsrise`, nested
  plugin-keyed settings, and string references without changing unrelated
  configuration or the user's layout order.
- `omarchy bar reset` selects `omarchy.bar` and retains the remaining bar
  configuration. `shibumi-suite status` reports Shibumi as inactive, and
  `shibumi-suite activate` selects it again.
- `omarchy bar defaults` replaces the complete `bar` object and removes its
  layout, but canonical service-entry settings survive. `shibumi-suite activate`
  restores the managed layout. Native disable/removal of the State entry is
  destructive; it is not equivalent to suite `--keep-settings`.
- Generic per-plugin enable, disable, and remove actions do not own Shibumi's
  suite lifecycle. Shibumi roots must be managed as one dependency set;
  `shibumi-suite repair` transactionally restores a partial payload and its
  selected profile. Repair alone may admit an absent owned root or payload
  digest drift when the installation state and every remaining ownership marker
  retain the exact supported identity; unsafe markers, paths, and foreign roots
  still fail closed.
- Uninstall removes Shibumi plugin references, selects the built-in bar, and
  uses Quattro's full restart boundary before deleting the provider payload.
  Normal uninstall removes canonical and legacy settings. `--keep-settings`
  retains the complete canonical State entry, including unknown fields and deep
  settings, dormant while its plugin payload is absent. Reinstall reuses it.

## Design Rules

- Native first: use Omarchy's `qs.Commons` and `qs.Ui` primitives where their
  contract fits instead of recreating controls and service access.
- Tokens only: production UI colors, type, spacing, borders, and bar dimensions
  come from `Color`, `Style`, and `Border`, not a parallel hardcoded theme.
- Quiet motion: interaction animations are short and purposeful; continuous
  animation is opt-in, lifecycle-gated, and measured.
- Accessible state: status is not communicated by color alone, keyboard paths
  are defined, and destructive actions require explicit confirmation.
- Host reuse: PipeWire, UPower, Bluetooth, Hyprland, SystemTray, MPRIS,
  Networking, notifications, idle, and other Omarchy-owned services remain the
  authoritative state sources where available.

## Non-Negotiable Invariants

1. One Omarchy Shell process; Shibumi never starts another Quickshell instance.
2. One bar window per real output, created from one shared root controller.
3. Service state is singleton unless it is genuinely screen-specific.
4. Per-screen panels, focus, anchors, and drag state never leak across outputs.
5. Split layout and drag-and-drop mutations are serialized through one model.
6. Heavy panels, pickers, video previews, and scanners are lazy and release
   resources when closed.
7. Event-driven APIs are preferred; reconcile timers require a measured need.
8. QML views do not execute platform commands directly.
9. No global state object may become a replacement for V1's oversized
   `Theme.qml`.
10. Omarchy owns plugin discovery, activation, bar selection, and runtime
    lifecycle. The Shibumi repository installer owns transactional bundle
    staging, update, rollback, and removal because the current Omarchy CLI
    installs only one root plugin per Git repository.
11. Existing Omarchy widgets receive their documented bar facade if Shibumi renders
    them through `barWidgetRegistry`; compatibility is tested, not assumed.

## Ownership Layers

The source layout is a top-level plugin suite. The historical combined tree
was migrated into independently validated plugin directories without changing
the approved behavior:

```text
hancore.shibumi.bar/              default bar host and composition
hancore.shibumi.bar.<variant>/    future independently selectable bar hosts
hancore.shibumi.control-center/   reusable G1 widget and settings panel
hancore.shibumi.<feature>/        complete widget/panel/service slices
hancore.shibumi.state/            shared live-state service, runtime, and passive presentation library
shared/presentation/             canonical active ShibumiPanel source for checked vendoring
scripts/                         panel drift check, install, update, and uninstall tools
tests/                           suite, contract, and regression tests
```

The 24 runtime plugins remain separately registered and are installed and
updated as one admitted suite. Two explicitly authorized exceptions permit
exact, declared imports from cooperating plugins into
`hancore.shibumi.state/runtime/` and the passive
`hancore.shibumi.state/lib/presentation/` module. No other sibling or
repository-root escape is allowed. The presentation module contains only
visual components: no service, Process, Timer, poller, worker, backend,
persistence, singleton, or mutable runtime authority. Consumers declare State
directly and State precedes them in suite order.

The ownership, lifetime, version and publication rules are normative in
[`docs/architecture/shared-runtime-v1.md`](docs/architecture/shared-runtime-v1.md).
This is not a QML sandbox or an authorization to expose private host services.
`ShibumiPanel.qml` retains three UI-lifecycle timers and therefore remains the
only canonical source under `shared/presentation/`; its existing plugin and
`widgets/` copies stay deterministically vendored and drift-checked. Bar-host
and feature-owner sources are maintained directly in their
`hancore.shibumi.*` plugin roots. Panels may consume services; services do not
import panels.
Widgets do not discover host paths or launch shell commands.

The Phase 2 owner for every V1 group and the notification and OSD boundaries
are recorded in
[`docs/phase2-ownership-map.md`](docs/phase2-ownership-map.md). That document is
normative: a port may not introduce a second owner merely to reproduce V1
presentation.

The normative repository and migration contract is
[`docs/plugin-suite-migration-plan.md`](docs/plugin-suite-migration-plan.md).
The current plugin inventory is
[`docs/plugins/README.md`](docs/plugins/README.md), and the versioned
widget-to-bar API is [`docs/host-facade-v1.md`](docs/host-facade-v1.md).
Application-menu ownership is an explicit exclusion: Omarchy owns it and
Shibumi must not ship a `menu` kind or application-menu service.

Host capabilities that Quattro does not yet expose without unstable adapters
are tracked in
[`docs/omarchy-quattro-contract-gaps.md`](docs/omarchy-quattro-contract-gaps.md).
That register separates actionable alpha feedback for Omarchy from Shibumi
product work that remains owned by this repository.

## State And Process Budget

- Use Quickshell and Omarchy APIs before starting a process.
- A feature gets one authoritative state owner.
- Pollers are centralized and shared by every screen.
- Closed panels have no UI-only timers or worker processes.
- Process output is parsed structurally and inputs are never interpolated into
an unquoted shell command.
- Cache files use explicit schemas and atomic replacement.

Every new recurring timer or process must document its interval, owner,
activation condition, and shutdown condition.

The retired Shibumi application menu owns no worker, watcher, timer, service,
or visible surface. Omarchy's menu and its process budget remain outside the
Shibumi runtime.

## Multi-Bar Architecture

Each selectable Shibumi bar design is its own plugin with `kinds: ["bar"]`.
The default V1-parity host keeps the stable id `hancore.shibumi.bar`; future
designs use semantic ids such as `hancore.shibumi.bar.<name>`.

Bar variants implement one versioned host facade for output ownership, panel
and tooltip routing, group/split access, drag-and-drop mutation, top/bottom
geometry, configuration mutation, and visual tokens. They reuse the same
independent widget, panel, menu, and service plugins. A variant may own surface
composition and bar-specific motion, but it may not fork feature state,
scanners, panels, persistence, or platform actions.

Widgets depend on the stable host facade and standard Omarchy contracts, never
on a particular bar plugin. Contract and self-containment regressions replace
the current assumption that future bars are internal `styles/` packages.

The detailed V1 feature migration gate is maintained in
[`docs/v1-parity-matrix.md`](docs/v1-parity-matrix.md). A feature may be adapted
to an Omarchy service, but it may not silently disappear from Shibumi.

## Picker Architecture

Shibumi must not repeat QS Rise V1's three independent picker pipelines. The target is:

```text
PickerController
  source discovery
  selection and navigation
  lifecycle and cancellation

ThumbnailService
  content-addressed cache
  priority warmup
  bounded workers

TanzakuView / HearthstoneView
  presentation only

Omarchy image-picker plugin
  native carousel, owned and invoked independently by Quattro
```

Closing a picker must cancel or detach pending visual work without leaving
worker descendants, stale callbacks, or retained media resources.

## Migration Phases

Current status:

- Plugin-suite migration Phase A: complete; the combined tree is frozen as the
  behavior-preserving migration source
- Plugin-suite migration Phases B-D ownership implementation: complete locally;
  all 24 declared plugins validate independently, deterministic shared-source
  vendoring and self-containment are enforced, and all fixed G1-G15 slots load
  through registered plugin entry points. The active bar is a strict
  registry/service-only host and passes a fresh Quattro composition smoke
- Plugin-suite migration Phase E: complete. the validation system passed the historical 21-to-22
  update migration, final-source uninstall with clean stock-bar recovery, a
  fresh install, later expansion to 24 plugins, markerless alpha ownership
  adoption, and a controlled post-exposure failed-update
  rollback without configuration, state, payload, process, or artifact loss
- Phase 0: complete
- Phase 1 implementation: complete locally
- Phase 1 predecessor runtime paths: passed on the validation system, 2026-07-16; exact
  Shibumi payload evidence must be recorded separately
- Phase 1 final acceptance: current upstream broken-plugin fallback and
  fractional-scale behavior still require final runtime evidence
- Phase 2 ownership/backend implementation: complete locally for the declared
  initial plugin set; final real-Wayland provider/action acceptance remains
- Phase 2 V1 presentation parity: substantially implemented for G1-G15 and the
  G3 Update Center/tray/notification composition. The current V1 eight-choice
  palette and G9 FULL/muse outcome are implemented and accepted on the validation system
  for the current single-output slices. Final Wayland actions, unavailable
  hardware, the remaining same-state comparison matrix, and physical
  multi-output remain open
- Phase 3 split/drag implementation: present locally; a physical Bottom ghost
  plus successful drop, byte-identical invalid-drop return, and process-restart
  persistence pass on the validation system. Hotplug and fractional-scale runtime acceptance
  remain open
- V1 output lifecycle: the native per-output `Variants`, placeholder rejection,
  targeted layer-window recovery, per-output cleanup, focused bar-widget
  routing, and non-persistent narrow/portrait presentation stages are present.
  the validation system passes controlled headless add/remove, 800x1280 portrait staging,
  focused routing, and cleanup without lifecycle warnings. Real DPMS,
  deep/S3 suspend, and S4 hibernate/resume also preserve the same shell process,
  configuration, single bar layer, IPC, and crash baseline. The remaining
  physical release gates for hotplug, hot-unplug during drag, and mixed scale
  are defined in
  `docs/v1-output-lifecycle-audit.md`
- Phase 4 picker/media implementation: implemented locally; all four modes,
  Tanzaku, Hearthstone, and Quattro's native carousel render on the validation system with
  focused-output routing and clean close. Theme/wallpaper success plus unique
  screenshot/video copy, open, trash, and Bottom rendering pass. Failure
  feedback, cold-cache timing, remaining Hearthstone, and physical multi-output
  acceptance remain open
- Phase 5 release parity and performance acceptance: in progress. The bounded
  idle CPU, child CPU, repeated panel/picker PSS, and G9 FULL/muse lifecycle
  and resource gates pass; final V1 visual parity and the remaining physical
  action/hardware gates remain open

The concise current release gate is maintained in
[`docs/release-readiness.md`](docs/release-readiness.md).

The evidence and per-group status behind this classification are recorded in
[`docs/v1-widget-parity-audit.md`](docs/v1-widget-parity-audit.md). A working
official backend or an instantiated stock widget is not sufficient to mark a
group complete when the approved V1 presentation or workflow is still absent.

### Phase 0: Historical Combined Contract Scaffold

- Valid transitional root manifest
- Loader-safe `Item` entry point
- One development `PanelWindow` per output
- Host position support
- No V1 runtime copy

### Phase 1: Bar Foundation

- Horizontal production chrome for the V1-compatible top and bottom positions
- Versioned style registry with `shibumi` as the fail-safe default
- Shared output/runtime core separated from selectable presentation surfaces
- Bar-off visibility contract
- Stable multi-monitor add/remove behavior
- Shared layout model for left, center, and right sections
- Tooltip and popout coordination
- Host widget registry compatibility facade and a proven stock-widget smoke
  test

### Phase 2: Core Widgets

- Workspaces and window title
- Clock, system tray, audio, network, power, and battery
- Centralized telemetry and event services
- Compact-mode contracts
- Versioned Shibumi group configuration through the dedicated state service and
  host-owned `shell.json`
- Registry-only G1-G15 widget resolution with unassigned official/custom host
  entries preserved as regional extras

Current Phase 2 foundation:

- the active `hancore.shibumi.bar/Bar.qml` owns only output windows, layout, split/drag interaction,
  panel/tooltip routing, style selection, and registered widget composition;
  feature data and workers live in independently validated plugins;
- fail-closed schema-1 parser for V1 group order, splits, and resource-bounded
  widget settings;
- one process-wide `hancore.shibumi.telemetry` procfs service shared by every output;
- internal CPU and memory widgets with compact/full horizontal presentations;
- screen-local, on-demand CPU and memory panels;
- GPU telemetry is inactive unless a CPU panel is open and tolerates missing or
  unusable `nvidia-smi` by falling back to DRM sysfs or no GPU row.
- one process-wide `hancore.shibumi.workspaces` Hyprland model with V1 persist-10, persist-5, active,
  default, numbers, and magic presentation contracts;
- a validated Quattro workspace action adapter, per-screen Shibumi workspace
  widget, and lifecycle-lazy keyboard panel whose backend-free content is
  offscreen tested;
- the Control Center owns Shibumi settings while Omarchy exclusively owns the
  application launcher menu. Disabled widget loaders and the default-off G7
  service construct no backend work;
- one process-wide `hancore.shibumi.center` clock and weather service feeds a
  single V1-compatible G8 center composite on every output;
  the composite owns weather, clock/date/calendar, and active-only status
  presentation while retaining the official weather detail workflow and
  official Omarchy idle/notification state owners;
- per-output free-span geometry feeds the G8 normal/compact/minimal hysteresis
  state, and optional center siblings are removed from that budget before the
  stage decision;
- nested panel routing preserves `omarchy.weather` summon/hide/open behavior;
  the visible stock weather button is replaced by the V1 glyph and tooltip,
  while the official component remains hidden as the complete detail-panel
  and action owner;
- the registered `omarchy.system-update` component remains hidden as the sole
  update detector and launcher, while a worker-free V1 facade restores the
  approved G8 glyph, urgent color, tooltip, and exact `runUpdate()` delegation;
- the local calendar participates in the same Tab/Shift-Tab sibling routing as
  the other Shibumi panels. the validation system top-position evidence covers weather,
  update availability, and reversible official idle/DND state changes;
  one shared Voxtype stream, a real dictation cycle, and the physical
  recording-indicator stop action are validated on the validation system; bottom and
  physical multi-output evidence remain open.
- G3 replaces the tray and notification group slots with one V1-compatible
  status pill while instantiating the registered `omarchy.tray` and
  `omarchy.notifications` components exactly once; `omarchy.system-update`
  is owned by G8 as in V1;
- the status container owns no SystemTray model, notification daemon, process,
  timer, or file watcher. Child settings, popouts, SNI menus, DND, history, and
  update actions remain official; deterministic wrapper geometry avoids
  visibility and stale-Loader width feedback.
- G6 keeps the registered `omarchy.audio` component closed and hidden as the
  authoritative PipeWire device, stream, MPRIS-label, and action adapter. The
  Shibumi full/compact widget and lazy mixer panel own the visible V1
  presentation, while every volume, mute, device, and stream mutation delegates
  to that same official instance. It does not create or trigger a second OSD;
- during the Step 4A transition, the bridge reads the authoritative
  `Pipewire.ready` signal and owns one bounded `PwNodePeakMonitor` only while
  the visible mixer is open; it exposes primitive snapshots and typed stable-ID
  actions while the official stock panel and its workers remain closed. The
  native `AudioBackendAdapter` provides the replacement primitive peak seam and
  is lifecycle-gated for activation. Component regressions cover missing-backend
  behavior, readiness, settings, screen-aware alias routing, action forwarding,
  unique click registration, model release, and teardown. Real Wayland panel
  mapping remains an acceptance gate.
- G7 replaces the stock AI presentation with one selected-provider Shibumi
  pill and one lazy local panel. The process-wide `hancore.shibumi.ai` service consumes
  the primitive schema-v1 records produced by current `omarchy.agents`; it
  never loads the host Agents panel or exposes host backend objects to views.
  The service owns one bounded update process and two watched Claude/Codex
  record paths process-wide while G7 is active; disabled G7/providers own no
  collector, record watcher, legacy provider, or OpenCode worker. On the
  pinned older Quattro baselines, the
  legacy `omarchy.model-usage` providers remain an exclusive fallback;
- OpenCode is supplied by one plugin-local read-only SQLite adapter because the
  consumed Agents record set does not publish an OpenCode record. It runs at
  activation and every five minutes while OpenCode data exists, writes no
  cache, makes no network call, and is shared by every output. Provider
  selection, refresh, `omarchy.agents` plus legacy `omarchy.model-usage`
  summon/hide routing, real Wayland panel mapping, and the complete pinned
  Quattro contract suite remain the acceptance boundary. Real Claude/Codex
  account-data on the current Agents host and multi-output acceptance remain
  gates. The consumed Agents manifest, update command, collectors, and record
  schema are revision-bound to Omarchy `v4.0.0` (`f0020448`) by a
  repository-owned compatibility contract rather than inferred from mutable
  installed files.
- G9 replaces only the official media presentation. The keep-loaded
  `omarchy.media` service remains the sole MPRIS/PipeWire selection and action
  owner while Shibumi views supply the default row, FULL/muse row, lazy panel,
  progress, cover art, and source selection;
- closed media views are worker-free. One lazy process-wide Shibumi spectrum
  service owns the optional Cava capability/default-sink probe, bounded Cava
  process, streamed configuration, degraded state, and cleanup. It runs only
  while at least one visible FULL/muse or spectrum consumer has an active
  playing source. Per-output, per-panel, and per-view probe or Cava processes
  are forbidden, and no path may leave a temporary file. The implementation
  preserves V1's 24-band, 60-fps Cava input while rendering the same geometry
  through bounded scenegraph bars instead of repainting 24 JavaScript canvas
  paths per frame. the validation system accepts the real-player, unavailable/crash,
  retry/cleanup, Top/Bottom, single-output visual, and resource slices.
  Multiple real players and physical multi-output acceptance remain gates.
- G11 uses one process-wide `hancore.shibumi.network` service, regardless of
  output count. It is the native NetworkManager owner over Quickshell's public
  Networking API and publishes only generation-bound primitive radio, device,
  network, exact-profile, connection, DNS, throughput, reachability, action,
  and failure snapshots. Raw backend wrappers stay private;
- Shibumi owns the single `omarchy.network` compatibility IPC handler without
  loading the host Network or QR components. Its own scanner lease, bounded
  profile catalog, telemetry, reachability, Enterprise dispatcher, Wi-Fi QR
  surface, and route-bound TLS speed-test workers are process-wide and
  demand-driven. An explicit QR click may read only the `psk` field from the
  exact active saved WPA/WPA2/SAE profile through a bounded, owner- and
  topology-revalidated `GetSecrets("802-11-wireless-security")` request. That
  response may contain only that `psk` value plus empty maps for the exact
  secret-free setting-group names observed in the immediately preceding
  `GetSettings()` snapshot bracketed by equal `VersionId` reads; any other
  group, field, value, or in-snapshot version race fails closed.
  Postflight requires the same owner, device, active connection, profile, access
  point, SSID, security, and group set plus exactly NetworkManager's observed
  one-step `VersionId` advance caused by the successful secret refresh; every
  other version delta or identity change fails closed. The exact D-Bus message
  may request interactive authorization from Omarchy
  Quattro's native Polkit agent; it adds no PolicyKit rule or authorization
  bypass, and cancellation or timeout fails closed. Worker failures expose only
  an allowlisted secret-free stage code, never exception text or response data.
  The passphrase crosses no snapshot, property, argument, environment, cache, log,
  or persistence boundary and is discarded immediately after QR encoding. No
  Network feature state comes from an Omarchy helper or `nmcli`;
- each output owns only its bar presentation, telemetry consumer lease, lazy
  Shibumi popup, and ephemeral QR session. WPA2-Enterprise is conservatively
  limited to PEAP/MSCHAPv2 with system CAs and a mandatory server domain;
  unknown EAP/certificate variants fail closed. DNS servers are a read-only
  diagnostic snapshot in this slice; unsupported DNS mutation is routed to
  Network settings rather than implemented through an unbounded settings map.
  Source and fixture gates pass,
  while real mutation, Enterprise authentication, recovery, bottom, and
  physical multi-output acceptance remain runtime gates and are not claimed.
- G13 has one process-wide `hancore.shibumi.brightness` service around the
  registered `omarchy.monitor` component. That hidden component remains the only
  brightness, display, scale, IPC, poller, and command owner;
- each output owns only its V1 brightness presentation and a lazy local Shibumi
  panel. The panel delegates brightness, scale, and display mutations to the
  shared owner and creates no process, timer, file watcher, or second monitor
  model. A no-backlight system retains display and scale controls. Top panel
  mapping, reversible laptop brightness mutation, and a real `1.0 -> 1.25 ->
  1.0` scale round trip pass on the validation system; physical display enable/disable and
  multi-output behavior remain gates.
- G12 and G14 are separate V1 battery and power-profile presentations over the
  process-wide `hancore.shibumi.power-state` service. Battery state stays event-driven through the
  shared UPower singleton, battery details are panel-lifecycle gated, and one
  profile refresh/set owner serves every output. Beta.13 retains the existing
  UPower, Omarchy helper, `busctl`, and `powerprofilesctl` backend ownership;
  shared-runtime admission is not a Step-6 backend transition. Battery truth
  requires `UPowerDevice.ready`, independently of profile availability on
  batteryless machines. The four existing operation slots remain process-wide,
  each with a ten-second one-shot deadline and exact admission lease/generation.
  Scope loss cancels work and rejects stale publication; a started operation
  drains its exit and stdout callbacks before its slot can be reused. A late
  process-start signal rechecks cancellation and admission. Deferred refreshes
  retain revocable demand until dispatch; last-consumer release, battery loss
  and scope invalidation cancel it. Synchronous busy-state notifications are
  rechecked before process dispatch and completion publication. Cancellation cannot
  undo a platform action already applied before the process was stopped.
  The existing 5-second active-profile/detail and 5-minute full-profile timers
  require current admission and their respective consumer leases. Panels keep
  their local Bar and reactive service references; native battery objects are
  not deliberately exported. Canonical Power sources live directly in
  `hancore.shibumi.power-state/`; `Service.qml` keeps its plugin-local
  `../hancore.shibumi.state/runtime` import. The combined `omarchy.power`
  alias is consumed so it cannot run beside the split views; G14 remains
  available on batteryless desktops. the validation system passes a real
  discharging-to-charging transition with matching kernel, UPower, helper,
  widget, and panel state.
- G15 has one process-wide `hancore.shibumi.bluetooth` service and one native
  `BluetoothBackendAdapter`. The adapter keeps native BlueZ device QObjects
  private and publishes detached primitive records carrying the device path,
  address, adapter identity, and monotonic device/adapter incarnations. Every
  mutation resolves exactly one current entity immediately before dispatch;
  stale, malformed, ambiguous, unavailable, or state-conflicting requests
  return typed failures and dispatch nothing. Beta.13 deliberately retains one
  `omarchy-bluetooth-device` helper path per device action and never invokes a
  native device method in parallel. Because the 4.0.2 helper accepts only an
  action/address pair, production fails closed with more than one adapter; the
  residual replacement race after dispatch remains explicit Step-4B helper
  debt. Callers inspect `.ok` explicitly. The
  adapter also owns pending state and Bluetooth-audio handoff; no complete
  Omarchy Bluetooth UI component is instantiated as a backend;
- each output owns only its V1 Bluetooth presentation and lazy Shibumi device
  panel. The process-wide service leases discovery across open panels and owns one
  symmetric six-method `omarchy.bluetooth` IPC target. Presentation has no
  Bluetooth/PipeWire import, process, timer, or file watcher; the service facade
  owns one bounded discovery-reconciliation timer and the adapter owns four
  bounded lifecycle timers. While a requested Discovery start is still pending
  during teardown, at most one temporary 30-second retry/expiry timer per
  native adapter survives the facade. Top mapping, adapter/radio
  reactivity, discovery ownership/teardown, both backend load orders, and IPC
  lifecycle pass on the validation system; real device/audio, bottom, and
  physical multi-output gates remain.
- the interaction foundation has a pure fixed-group layout model, one
  bar-owned persistent controller, and one transient drag session per output;
- the group renderer resolves Shibumi and official Quattro widgets without
  duplicate state owners, preserves custom host-layout extras, omits empty
  groups without reserving space, and renders persisted within-section split
  spacing;
- per-output edit mode now owns pointer targets, ghost geometry, invalid-drop
  return, full-output input masking, and transient cleanup while the root
  controller remains the sole persistence owner;
- pure run geometry converts within-region and boundary splits into section
  chrome without coupling presentation to persistence.
- Reactor Modes 1-6 are style-owned, backend-free gap renderers. Mode 7 uses
  one process-wide lazy event service over existing Shibumi and Quattro owners;
  Mode 8 uses one process-wide lazy quote reader. Theme/event/quote file
  contents are acquired through bounded no-follow regular-file reads, not
  unbounded FileView content buffers. Metadata watchers trigger one coalesced
  short-lived Python reader per active input (two in Mode 7, one in Mode 8),
  initially and on observed changes, with a two-second one-shot deadline and
  cancellation on backend loss; there is no acquisition polling timer.
  The existing single pacman event tail remains Mode-7-only. Modes 7-8 share the same
  per-output swarm renderer, use physical run gaps, and create no service or
  renderer in Mode 0. The Control Center persists the selected mode through
  the canonical State entry's `shibumi.reactor` data. Controlled Mode 7/8 Wayland and CPU
  acceptance remains open.

### Phase 3: Interaction Model

- Split layout, run chrome, hover-revealed within-section markers, and boundary
  treatment: implemented locally
- Group swap within and across sections, geometry-based targets, ghost, and
  invalid-drop return: implemented locally
- Per-output edit state, full-output input mask, and exclusive keyboard focus:
  implemented locally
- Persistence through host-owned configuration APIs: implemented locally
- Real top/bottom pointer behavior, output hot-unplug during editing, and
  fractional-scale acceptance: open Wayland gates

### Phase 4: Panels And Pickers

- Lazy panels with explicit cleanup
- Shared image/media picker controller and thumbnail service
- Theme and wallpaper actions through Omarchy host contracts

The G10 implementation has one process-wide controller and helper contract.
Tanzaku and Hearthstone are presentation-only views and own no scanner, timer,
watcher, or converter. Shibumi does not duplicate Quattro's native carousel
image-picker plugin. the validation system proves both retained Shibumi styles and all four
modes open on the focused output, style selection survives restart, and close
leaves no helper/converter or temporary artifact. the validation system also passes real
theme/wallpaper success actions and unique screenshot/video copy, open, and
two-step trash actions with complete artifact cleanup. Failure feedback,
cold-cache timing, remaining Hearthstone rendering, and physical multi-output
acceptance remain release gates.

### Phase 5: Parity And Release

- Port remaining approved V1 features
- Preserve the versioned Shibumi presentation contract; CPU and memory normal
  and compact variants are the first completed token-backed slices
- Performance and memory gates
- Clean install, update, rollback, and remove tests through Omarchy
- Documentation and private release candidate testing

## Acceptance Gates

No phase is complete from static checks alone.

### No-Regression Release Gate

Shibumi is not releasable if it reduces the approved QS Rise V1 experience. Native
Omarchy integration may replace implementation details, but not user-visible
quality. Every migrated slice must meet or exceed V1 for:

- feature coverage and action feedback;
- visual hierarchy, alignment, density, theme response, and motion quality;
- interaction latency and warm/cold open behavior;
- multi-monitor, top/bottom, split, drag-and-drop, and panel ownership;
- idle CPU, child-process CPU, memory retention, and worker cleanup;
- degraded/missing-backend behavior and recovery after shell reload.

Official Quattro widgets are temporary service-compatible fallbacks, not the
final Shibumi presentation. A fallback-backed group remains incomplete until
its Shibumi view and the relevant runtime gates pass. Intentional differences
from V1 require an explicit documented product decision; convenience or a
cleaner Shibumi architecture alone is not sufficient justification.

### Runtime

- Plugin loads without QML errors and does not trigger host fallback.
- Adding, removing, disconnecting, and reconnecting outputs affects only the
  corresponding bar window.
- Top and bottom positions render without overlap or clipping. Defensive
  left/right host geometry is not a QS Rise V1 or Shibumi release gate.
- Host shell reload destroys all Shibumi windows and workers cleanly.
- Failure of one optional backend does not prevent the bar from loading.

### Interaction

- Split state survives reload.
- Drag-and-drop is deterministic on one and multiple monitors.
- A panel opens on the invoking screen and never steals another screen's
  panel state.
- Closing a panel stops its UI-only work.

### Performance

- Idle CPU and child-process CPU are measured on a warm session.
- Open/close memory is tested over repeated cycles.
- No hidden panel or picker continues rendering, scanning, or decoding.
- A cold cache and a warm cache are both measured.

### Lifecycle

- The official `omarchy plugin validate` command passes for every one of the 24
  child plugin roots.
- The repository root has no `manifest.json`; native
  `omarchy plugin add <repository>` must fail instead of installing a partial
  or misleading plugin.
- The suite adapter uses the official validator, plugin discovery rescan,
  `shell.json` contract, and Omarchy Shell Inter-Process Communication (IPC).
  It owns only atomic multi-plugin staging and rollback.
- Update review contains only Shibumi plugin changes.
- Failed load falls back to the built-in bar.
- `omarchy bar reset`, `omarchy bar defaults`, status, and reactivation follow
  the configuration contract above.
- Removal restores the built-in bar without leaving Shibumi-owned state.

## Reference Implementations

These projects are evidence sources, not code templates:

- Official Omarchy Quattro host and built-in bar: the validation system package
  `4.0.0.r1458.gfa6b5fc-1`
- ThinkOodle `omarchy-shell-plugins`, commit
  `352b8d69017adae0074453f49dd9bac36cf07a15`
- Whiterose roadmap and widget architecture, commit
  `874ac54bd3c1a658c91f79bc63f6a4e80338f862`
- bjarneo `omarchy-shell-plugins`, commit
  `c4c9f7bd660eb1db4d1dcdd6c64177d3f7dce4bf`

The official Omarchy source is authoritative when examples disagree with the
current loader or manifest behavior.

## Explicit Non-Goals

- Preserving V1 file paths or helper names for compatibility
- Shipping V1's installer, uninstaller, self-updater, systemd units, or hooks
- Maintaining two theme owners inside the Omarchy process
- Running a second notification daemon or duplicate OSD beside Quattro's
  implicitly enabled first-party services
- Copying the complete V1 `Theme.qml`, `shell.qml`, or picker implementations
- Publishing the repository before the private acceptance matrix passes
