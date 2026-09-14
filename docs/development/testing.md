# Testing

Status: maintainer reference

Automated Shibumi tests can run from any supported development checkout.
Maintainers repeat the complete contract and live Wayland acceptance on an
isolated validation system before release; users and external contributors do
not need access to that system.

## Test order

Run the smallest affected regression first. For a bar-host change:

```bash
cd /path/to/shibumi
OMARCHY_PATH=/usr/share/omarchy ./tests/bar-host-registry-regression.sh
./tests/host-registry-prime-regression.sh
```

The bar-host regression also exercises the process-singleton `omarchy.bar`
visibility nudge in an isolated HOME, proving both host-owned marker directions
and rejecting duplicate target registration across overlapping Bar fixtures.
The registry-prime regression uses the real exact-PID Quickshell IPC transport.
It covers success, transport refusal, acknowledged timeout, post-prime Bar-owner
change, changed-process refusal, and scope loss/recovery. Every case remains
fail-closed until a replacement owner is observed, dispatches at most one native
rescan, and checks the exact bounded observation vocabulary, event cardinality,
monotonic elapsed milliseconds, and four-field redacted JSON shape. The pinned
native all-24 and runtime probes separately prove that the Runtime singleton
survives the real host rescan and publishes exactly one successful attempt.

For a Bluetooth change:

```bash
OMARCHY_PATH=/usr/share/omarchy ./tests/bluetooth-plugin-regression.sh
```

Before handing off or releasing any source change, run all four complete
baseline jobs. The installed-package job defaults to the package-managed host:

```bash
./tests/omarchy-installed-package-contract-regression.sh
```

The installed-source-parity job requires an explicit clean Git checkout of the
official `v4.0.3` source revision used by the installed package:

```bash
SHIBUMI_INSTALLED_SOURCE_OMARCHY_PATH=/path/to/omarchy-v4.0.3 \
  ./tests/omarchy-installed-source-parity-contract-regression.sh
```

For an additional 4.0.2 compatibility run, invoke the aggregate contract with
the historical selector and its exact checkout. Release jobs themselves pin
4.0.3 and never inherit this selector:

```bash
OMARCHY_PATH=/path/to/omarchy-v4.0.2 \
SHIBUMI_OMARCHY_BASELINE_PROFILE=installed-source-parity \
SHIBUMI_OMARCHY_BASELINE_VERSION=4.0.2 \
  ./tests/contract-regression.sh
```

The forward-compat job separately requires the immutable upstream snapshot used
by the engineering audit:

```bash
SHIBUMI_FORWARD_COMPAT_OMARCHY_PATH=/path/to/omarchy-forward-compat-ed7bae4a \
  ./tests/omarchy-forward-compat-contract-regression.sh
```

The AI Agents integration retains its own narrower revision-bound host
contract against the official `v4.0.0` source baseline:

```bash
SHIBUMI_AGENTS_OMARCHY_PATH=/path/to/omarchy-v4.0.0 \
  ./tests/omarchy-agents-contract-regression.sh
```

This gate binds the consumed Agents manifest, record reader, updater, and
Claude/Codex collectors independently of the complete host inventory.

Every host-bound test both imports `tests/lib/baselines.sh` and invokes its
loader. The complete-host jobs select three repository-owned manifests with
non-overlapping claims; the Agents job selects its separate narrower manifest:

- `contracts/baselines/omarchy-installed-package-v4.0.3.json` validates the
  package-managed `omarchy 4.0.3-1`, `omarchy-settings 4.0.3-1` layout;
- `contracts/baselines/omarchy-installed-source-parity-v4.0.3.json` proves that
  the official `v4.0.3` source form satisfies the same complete suite;
- the corresponding 4.0.2 manifests remain immutable optional compatibility
  baselines selected only with `SHIBUMI_OMARCHY_BASELINE_VERSION=4.0.2`;
- `contracts/baselines/omarchy-forward-compat-ed7bae4a.json` proves forward
  compatibility with the recorded upstream snapshot.

All three manifests bind the complete consumed `shell`, `bin`, and `config`
subtrees by entry count, path inventory, entry type, executable state, symlink
target where packaging requires one, and file-content digest. Directory nodes,
including empty directories, participate in the inventory and structure
digest; FIFOs, sockets, devices, and other unsupported node types are rejected.
`shell` and `config` payload entries must be regular files; the installed `bin`
payload entries must retain their exact absolute package symlinks. Both
Git-checkout jobs additionally require their exact declared revision. A caller
may relocate a matching tree through the documented path input, but cannot
select an arbitrary manifest, escape the validated tree through a consumed
source symlink, or add or omit any subtree entry.

The aggregate is complete only when it reaches a marker beginning with
`Shibumi complete contract regression passed`. The marker names the selected
installed-package, installed-source-parity, or forward-compat baseline and its
full source revision. Missing or drifted host files, a missing Quickshell
runtime, or any skipped host matrix fail the run before that marker.

The V1/V2 predecessor inventory is pinned portably in
`contracts/baselines/quickshell-dots-d0896fc-v2-deec8103.json`. To additionally
verify a local checkout byte-for-byte, pass its absolute path without encoding
that machine-specific path in a contract:

```bash
SHIBUMI_PREDECESSOR_PATH=/path/to/quickshell-dots \
  ./tests/reference-baseline-regression.sh
```

The full contract covers:

- V1 and V2 source evidence;
- embedded V2 difference classification;
- Quattro version and plugin contracts;
- plugin import boundaries, exact State-module exceptions, and active-panel
  vendored parity;
- host-facade and suite lifecycle behavior;
- QML component and service smokes;
- Control Center, Omarchy menu continuity, bar, panel, and widget behavior;
- transactional installer and updater regressions.

The bar gates also run `tests/v1-center-slot-regression.qml` and the two-output
slot-interaction fixture. `tests/widget-pipeline-diagnostics-regression.sh`
exercises the read-only `debugWidgetPipeline` IPC against unresolved real
`WidgetSlot` ownership. It proves that `debugBarGeometry()` can remain empty
while an unresolved slot exists, and checks the fixed output/expected/slot and
registry-count bounds plus metadata/path redaction. The IPC returns only scalar
facade, selection, component, Loader and output-session state; it does not
acquire data or retain events.

With `SHIBUMI_RUN_WAYLAND_LIFECYCLE=1` and
`SHIBUMI_NATIVE_SHELL_PATH` set to the pinned 4.0.3 `shell` directory,
`tests/widget-pipeline-wayland-regression.sh` runs the focused full-native-host
check (it can also be invoked directly):

```bash
SHIBUMI_NATIVE_SHELL_PATH=/tmp/shibumi-omarchy-0534987/shell \
  ./tests/widget-pipeline-wayland-regression.sh
```

The Python staging driver first admits the complete 183-file native fingerprint.
It runs the native `PluginRegistry`, `BarWidgetRegistry`,
`PluginBarWidgetRegistryApi` and plugin-Bar loader. A disclosed observation-only
counter in `shell.qml` measures public rescan calls; both the overlay digest and
staged native fingerprint are recorded. Unrelated native manifests are withheld. The private plugin directory contains
the real State and Shibumi Bar payloads plus one inert marker widget; native
platform services and every other suite plugin are absent. Quickshell receives
private HOME/XDG/runtime, disconnected buses, a minimal command path, an empty
network namespace, a two-MiB log bound, a process-group deadline, and one nested
Hyprland output. No production desktop output or DPMS state is changed.

A missing marker entry point is the deliberate negative control and must stop
at the `registry-selection` stage while the native Bar, `BarPanel`, V2 Notch
`BarSurface`, `GroupSlot`, and unresolved `WidgetSlot` remain observable. Beta.13
is materialized from commit `2760cdb8272255790d5e4613fed8a48cb63c3555`, with a
read-only census/IPC overlay and three scalar Loader aliases. Unavailable
historical lifecycle/provenance is explicit, not synthesized as success. Original
commit payload fingerprints and the overlay digest remain distinct.

Beta.13 and the candidate each exercise three real nested Wayland-output
removal/return cycles through private compositor configuration. Beta.13 must
reproduce the scoped component-admission failure each time; only that historical
control receives a repair rescan. A staged candidate mutant restores only the
retired JavaScript `Component.Ready` guard, must remain empty after return, emit
one passive warning and dispatch no second rescan. The actual candidate must
retain current Loader/item/submission identity and restore the marked widget on
a mapped valid output on every cycle, with exactly one startup rescan total and
no passive warning. The `instanceof Component` production check is exercised
unchanged. An absent JavaScript status is not itself a failed or successful load.
The maintained `widget-pipeline-classifier-regression.py` tests distinguish
missing selection/handle, Loader.Error, missing item and stale provenance, and
require latched output chronology across later flaps.

`scoped-loader-admission-regression.sh` additionally exercises the production
direct scoped binding and Loader with inert local objects: 42 repeated
publications of one Component handle, one exact A→B replacement, type refusal,
unregister, disable, removed configuration, facade loss/replacement,
asynchronous Load error, registration-before-load and completion/injection
reentrancy. The 42 equal publications retain one item and submission generation;
the replacement advances that generation exactly once. Only the exact
submitted-source/generation/completed-item tuple can report current success;
the native sourceComponent getter is not used as readback authority. The
separately activated legacy resolver retains its original Component readiness
tests.

This is deterministic nested-output evidence through the production host and
render chain. It is not physical hotplug, DPMS, multi-output, GPU, platform
backend, package, or live-desktop acceptance.

`tests/drag-ghost-render-regression.sh` renders only
controlled fixture content offscreen at scale factors 1 and 1.5, checks capture
pixels with the installed `/usr/bin/magick`, and tests cancellation/image lifetime.
It also tests already hidden source-window refusal and cancellation when the
source changes windows. Invalid dimensions use the shared size-guard predicate:
Qt's offscreen QWindow clamps zero dimensions to one, so this is not a native
zero-sized-window runtime test. Changed bar/model QML fixtures abort
the current JavaScript stack after `Qt.exit(1)`: scheduling failure alone must not
fall through to a later success exit. Mutation counterchecks must prove a nonzero
process exit, not merely a diagnostic string or final PASS marker.
`tests/qml-assertion-exit-regression.py` repeats positive/negative/restored-positive
controls for the center limit and controller persistence count in private copies.
The bar-host fixture also runs `fixtures/CloneSelectionChecks.qml` against the
selected baseline's unmodified registry decision/mutation methods, with only
startup directory/watcher I/O disabled. It proves the original-enable hazard,
clone identity/settings preservation and atomic refusal cases without a live
registry. Model/controller/bar tests cover ambiguous extra-slot removal and the
explicit return-to-extra workaround. `fixtures/PluginRemovalChecks.qml` executes
the exact extracted Control Center removal method against inert process
properties, proving refusal before command dispatch. That fixture neither runs
an uninstaller nor proves a filesystem-uninstall transaction. The loaded Plugin
Catalog confirmation tests preserve the actionable error and its generic fallback.
Center interaction cases exercise disabled and non-loading G8, a width-reactive
sibling on two simulated outputs, edit placeholders and loading recovery,
without deriving owner readiness from its own allocated width.
It uses no desktop screenshot or physical layer surface; real Top/Bottom ghost
and mixed-scale acceptance remain separate.

## Asynchronous Control Center restoration

`tests/bar-host-registry-regression.sh` exercises the actual Bar restoration
controller with explicit asynchronous State signals and inert output-local panel
objects. A 1.8-second pending write must neither reopen a panel nor consume the
1.6-second rebuild window. Cases cover independent output serials, failure,
unchanged readback, readiness and Bar admission loss, user cancellation, an
already-applied write followed by failure, synchronous settlement, rejection and
throw against existing records, newer navigation/recreation, a nearly expired
handoff, and cancellation/rescheduling from a panel-open callback.

```bash
python3 tests/state-restore-control-regression.py
```

Ten narrowly calibrated mutations alter only the private staged Bar: incomplete
navigation rollback, duplicate output enrollment, missing admission revocation,
missed synchronous settlement, rejected-existing changes, expired retry windows,
premature pending-window consumption, premature native-publication-window
consumption, false-success settlement and timer-snapshot replay. Positives run
before and after the mutants;
each negative needs a nonzero exit and its intended diagnostic, without unrelated
runtime errors. These objects simulate output identities; they prove no physical
screen, keyboard focus, rendering or full-Bar handoff behavior.

The large `tests/control-center-regression.sh` presentation matrix deliberately
substitutes the complete `SynchronousStateStorage.qml` backend before construction.
It is an in-memory presentation fixture, not async persistence or admission
proof; no native storage object or writer is constructed by that replacement.
The real State controller and public setters retain separate file-backed gates.
The pinned native-root fixture additionally exercises the actual Control Center
and actual Bar restore helper together, including pending/readback settlement and
Bar-admission revocation while State remains ready. That fixture also covers the
serialized layout, family, catalog and selected-provider flows described below.

## Scoped-host State and marker regression

The focused check below consumes the exact `PluginShellApi.qml` from Omarchy
`v4.0.3` (`0534987009061cbe2dacdde4ad564092ab698d12`). It rejects any different
facade bytes before execution:

```bash
python3 tests/scoped-state-regression.py \
  --host-api /path/to/omarchy-v4.0.3/shell/services/PluginShellApi.qml
```

It uses private HOME/XDG directories, disconnected buses, offscreen rendering,
an inert palette, the real Shibumi State service, and exact extracted Bar
marker/verification bodies. It exercises own-file marker resolution under paths
containing spaces, percent and hash characters, a foreign manifest-directory
decoy, missing/malformed/wrong-suite/wrong-digest markers, actual private IPC
verification, rejected/unapplied/unpublished writes, stale mutation scopes, and
scoped snapshot loss/recovery without wider-authority fallback. It does not
instantiate platform backends or touch a production shell. This focused State
case is **not** a complete 4.0.3 compatibility gate. The pinned catalog,
all-suite service, notification, idle and physical acceptance gates remain
separate evidence.

## Shared runtime regression

```bash
python3 tests/scoped-state-regression.py --runtime \
  --host-api /path/to/omarchy-v4.0.3/shell/services/PluginShellApi.qml
python3 tests/shared-runtime-import-regression.py
python3 tests/isolated-process-regression.py
```

The runtime case uses the actual shared module and pinned native facade. It
covers independent relative imports, parentless and late-injected providers,
equivalent manifest refresh, atomic duplicate refusal, malformed host/manifest
revocation, publication loss/recovery, scope loss, retirement, stale leases,
nested structural comparison, native injected publication,
and honest State-to-bar writes. Native QVariantMap key order is insignificant;
array order and values remain significant. The scalar service-facade snapshots
may lag the active bar's injected configuration; neither an uncalled callback
nor an unchanged publication is accepted as success. The extracted marker-only
Bar probe supplies its runtime-ready predicate explicitly and is not a full-Bar
readiness check.

Import regressions cover the exact declared sibling-module exception and
adjacent QML/ESM, path, regexp and template-interpolation spellings through both
public checkers. Unsupported lexical ambiguity fails closed; the lexer is not a
complete syntax validator. Reassess it when the pinned Qt grammar changes.
Neither imports nor underscore-prefixed coordination internals create a sandbox. The legacy full-bar injection remains unchanged. Scoped client
adapters do not expose the complete active bar.

## Audio cooperative-runtime slice

`tests/audio-media-plugins-regression.sh` also runs `audio-runtime-smoke.qml`:
actual Audio service, two widget instances and actual AudioPanel bodies, with
only the panel window shell replaced. Nodes and action delegates are entirely
local fixtures; the scoped host methods are controlled doubles, not the native
4.0.3 root. The test covers late host/manifest admission, shared ownership,
accepted/refused own-ID presentation calls, panel actions, two exact peak leases,
selective close, reactive bar injection, scope loss/recovery and backend
readiness loss/recovery. A controlled State provider proves both widgets' token
registration, mutation, revocation and recovery while bar geometry stays local.
This is not physical output or PipeWire acceptance. The older adapter seam test
retains its disclosed disconnected-PipeWire-singleton warning; fake actions
never fall through to a production bus or command.

## Telemetry cooperative-runtime slice

`tests/telemetry-plugins-regression.sh` also runs `telemetry-runtime-smoke.qml`.
The actual CPU, Telemetry and Storage providers feed CPU, memory, GPU,
temperature and storage widgets and their actual panel bodies. Window shells
and scoped host calls are controlled fixtures. GPU, thermal and storage probes
are disabled before sampler creation; SystemTelemetry still reads procfs.
The test checks actual Loader-item absence before admission, incomplete
injection refusal, shared peer identities, exact sampler leases, open-panel
rebinding across scope loss/recovery, local bar replacement, overlapping CPU
provider refusal and final consumer cleanup. Loss is published before deferred
Loader teardown so peers can release a still-live sampler context; the queued
callback rechecks current admission. No recurring timer is added.

The first synchronous-unload variant emitted an invalid-QML-context warning
and failed the maintained harness despite its QML success marker. The deferred
drain passes the same strict log check. This does not establish full native-host
service destruction or OS-worker termination: real 4.0.3 lifecycle and physical
outputs remain separate gates. The import regression checks all 29 current
production sibling-module importers through the public CLI, including rejected
alternate aliases and undeclared adjacent files.

## Workspaces runtime and V1 G2 geometry

`tests/workspaces-plugin-regression.sh` retains the legacy model, dispatch and
animation smoke and adds the actual Workspaces service, two scoped widgets and
actual WorkspacePanel/Content bodies. Only the panel window shell is replaced.
Controlled complete backend/State objects cover partial injection, shared owner,
late State/tokens, local open-panel Bar rebinding, selective close, cached-method
refusal after host/manifest/duplicate loss, recovery and State write revocation.
Incomplete/throwing fake backends and invalid focus IDs refuse without a native
fallback. Native models and the native action adapter are not public facade
properties. Admission does not assert a connected Hyprland backend; fake focus
acceptance is not observed compositor focus or native State persistence.

The geometry fixture renders actual Workspace/Memory widgets with canonical
VisualTokens in an owned offscreen Window at scale 1. It uses source-derived
32px group/28px slot embedding, not the complete BarSurface/GroupSlot. Real frame
signals precede grabs; Canvas checks the captured pixel columns as well as Item
bounds. Twenty-four V1 cases cover 34/35/36px Bar input, Top/Bottom, small/large
radius and border on/off. Before the fix, 35px cases measured 23px G2 versus 24px
Memory, with the same top but one missing bottom pixel. The local V1 bottom
margin correction preserves 24px without changing global geometry. Eight V2
cases retain the original rounded hidden-pill height and suppression. This is
not physical desktop, full-Bar, mixed-scale or multi-output acceptance.

## Reactor cooperative runtime and bounded inputs

`tests/reactor-plugin-regression.sh` retains the legacy event/quote smoke and
adds scoped admission, State readiness, duplicate refusal, mode replacement,
current-mode deferred Loader teardown, cached-action refusal and two actual
output-local renderer Items. They are zero-sized and windowless: this checks
routing and lifetime, not rendered pixels or physical outputs. Probes are off
before construction, including Hyprland singleton connections. Controlled Audio
loss/replacement/readiness does not generate fictitious mute transitions; an
actual controlled value transition is forwarded once. The real Bar entrypoint
already adapts its scoped shell, which its internal BarSurface consumes.

Mode 0 and modes 1–6 create no feature backend. Mode 7 owns the existing event
backend/pacman tail and two metadata watchers; mode 8 owns the quote backend and
one metadata watcher. Each active input runs at most one coalesced short-lived
Python reader, initially and on observed file changes, with a 2s one-shot
deadline. No recurring acquisition timer is added. Admission/mode loss disables
probes before deferred Loader destruction. This is not complete native-host
teardown or OS-worker termination evidence.

`tests/reactor-text-source-regression.py` exercises the exact helper and actual
QML reader. FileView never reads content (`preload: false`); a no-follow regular
FD reader caps theme/event/quote input at 512/4096/65536 bytes before buffering,
checks stable fstat identity and strict UTF-8, and emits a bounded JSON result.
The interpreter uses `-I -S` and a cleared environment. Tests cover all limits
±1, empty/multibyte/BOM/chunk boundaries, malformed UTF-8, symlinks/nonregular
files, changed content during reading, startup contamination, queued reads,
failed starts, missing helper, timeout, cancellation, owned Item destruction,
and an observed generation change while a successful read is held in flight.
Controlled preload, latched-busy and stale-success mutants must fail with their
intended diagnostics; a restored positive must pass. This is bounded input and
owned-fixture evidence, not a general malicious-QML sandbox or instantaneous
filesystem-path freshness guarantee.

## Power cooperative runtime

The canonical owner and operation controller live directly in
`hancore.shibumi.power-state/`. The service retains its plugin-local
`../hancore.shibumi.state/runtime` import; there is no Power source-vendoring
transform or root/shared mirror.

`tests/power-plugins-regression.sh` retains the legacy presentation and helper
smokes, and adds the actual Power service, two Battery and two Power Profile
widgets, and actual panel bodies with only their window shells replaced. All
commands and battery data are controlled fixtures; even the legacy active-profile
`busctl` call is replaced. The explicit fake command roster is complete or
refuses, and any explicit fake disables native battery access. A battery-only
fake cannot fall through to platform actions.

The runtime fixture covers late/partial admission, native-ready-shaped battery
loss/recovery independently of desktop profile availability, State token arrival,
shared identities, exact leases, actual panel action to a private fake, local Bar
rebinding, duplicates, invalid manifests, cached-action refusal and incomplete
fake refusal. Scope loss and actual service-Loader destruction each cancel a
confirmed in-flight delayed-side-effect helper. The fixture remains alive beyond
its delay to observe that its private profile file stays unchanged before harness
cleanup, then checks replacement and view destruction. This is not physical
battery/profile mutation, a complete native-host lifetime gate or proof that
cancellation can undo an already applied platform action.

`power-command-smoke.qml` exercises the production operation controller: simulated
exit/collector orderings retain cancelled/timed-out records until both callbacks
have drained, followed by actual success, failed start, deadline, replacement,
and synchronous cancellation/failure during startup. The helper is inert and
writes only private fixture data. Controlled copied-source mutants cover early
drain and omitted late-start cancellation under an unavailable-starting-PID seam;
that seam is not a claim about the installed kernel's exact scheduling. An action
return indicates queued launch, not observed profile application. Synchronous
busy-state notifications additionally test cancellation before process dispatch
and generation revocation before completion publication.

`power-deferred-regression.py` runs captured actual Power sources with controlled
settlement/action-completion signals on the fixture's four operation children.
It tests cancellation between scheduling and dispatch: final lease release,
revocation followed by re-admission, battery loss/recovery, and action follow-up.
Manual requests without consumers still run. Four copied-source callback mutants
must fail with their intended diagnostics, followed by a restored positive.
The fixture observes both worker state and private helper traces before cleanup;
this does not claim native helper callback scheduling or a host-tree traversal.
Existing trusted
platform-helper stdout collection is retained; its 65,536-UTF-16-code-unit parse budget
is explicitly not a pre-buffer acquisition limit for arbitrary external input.

## Weather location model sub-slice

`tests/weather-location-regression.py` captures the actual location model and
runs pure QML positives, five calibrated mutants and a restored positive.
It bounds the response parser to 65,536 UTF-16 code units and five input rows,
validates finite geographic coordinate ranges and 160-code-unit printable names,
and rejects markup, bidi controls (including ALM/LRM/RLM), other control characters
and unpaired surrogates. Optional
null metadata and the existing invalid-row filtering/country priority remain.
Commit projection rejects malformed selected rows instead of falling back to a
raw name; the explicit empty-choice raw-name workflow remains. The panel input
uses the same length limit and refuses a rejected commit projection. The actual
panel smoke checks overlong field input and a malformed nonempty selection,
observing no private helper dispatch before restoring a valid selection. Commit
projection is asserted to contain exactly name/latitude/longitude. The baseline
Center gate also runs `weather-panel-control-regression.py` against captured
Commons/Ui fragments from that admitted host, with maintained missing-input-bound
and missing-null-guard mutants plus restored positives. It stages no unrelated
Audio or native service owner; only inert curl/location helpers can run.

These parser and publication limits are independent of the transport limits.
Production weather requests pass `--max-filesize 131072`; geocoding requests
pass `--max-filesize 65536`. The Center regression requires each complete curl
argument vector and makes oversized fixture transfers fail. The panel smoke uses
inert curl and location helpers, while the model controls use no network or
platform helper. Live network behavior, native request lifetime under the real
host, and full unchanged-4.0.3 acceptance remain physical gates. Qt command-line
interface (CLI) logging is routed to stderr so a missing console marker cannot
be mistaken for a completed assertion run.

## Weather report validation

`tests/weather-report-regression.py` captures the actual report model and actual
WeatherService parser with acquisition disabled before construction, private
HOME/XDG and an inert curl PATH. The model validates the whole consumed candidate
before any weather-data field is updated: one current condition, one to three
consecutive valid forecast dates, one to 24 ordered hourly records, finite numeric
ranges, bounded descriptive labels and valid solar-clock values. Absent/null/empty
descriptive metadata and no-sunrise/no-sunset cases remain supported. Existing
first/fifth-hour icon selection is preserved. A rejected later forecast day must
leave every previous data field intact while setting unavailable; a later valid
report recovers. This is reject-before-field-update coverage, not atomic scalar
notification, request-generation, or service-admission proof.

The 131072-unit parser budget is explicitly UTF-16 and remains distinct from
the 131072-byte curl transfer limit. Supplementary Unicode padding distinguishes
code units from code points and UTF-8 bytes at both sides of the parser boundary.
Sixteen calibrated mutations cover these units, parser/day/hour budgets,
label/numeric validation, forecast-field projection, independent forecast
minima/maxima and ordering, consecutive dates and partial publication, followed
by a restored positive. Checks run after the Quickshell engine connects its exit
handler; completion markers without exit zero are never sufficient.

The production service publishes a collected response only after curl also exits
successfully. Failure, including fixture exit 63, leaves the report unavailable
and cannot publish buffered output. A queued refresh uses an object-owned
zero-interval timer, and Loader destruction stops that timer; the teardown
regression observes no later process start. These controls exercise the declared
curl path with inert helpers. They are not a sandbox for a substituted executable,
a live-network test, or physical 4.0.3 acceptance.

## Public native catalog foundation

```bash
python3 tests/native-catalog-regression.py --controls
python3 tests/native-catalog-instance-selection-regression.py
python3 tests/catalog-demand-regression.py --controls
```

The complete contract runs this gate. Captured regular sources, private HOME/all
XDG, absent live buses, offscreen/software Qt and an owned child cgroup isolate
all runs. The QML model/facade checks schema/Unicode/count boundaries, duplicate
JSON keys and IDs, complete bounded ancestry, empty readiness, explicit incomplete
fake suppression, exact serials, synchronous completion, queued/coalesced refresh,
readiness revocation and backend loss/replacement. An accepted operation must drain
before reuse, including A-B-A. A typed QObject guard is required to observe a
replaced object's destruction; keeping it only inside a JS record reproduced a
stalled replacement. Twenty calibrated source mutations, including post-drain cadence, are bracketed by restored
positives. Negatives require their intended diagnostic and nonzero exit.
An active malformed `busy` value cannot override an exact accepted-operation drain;
throwing cancellation remains revoked and cannot strand pre-start bookkeeping.

The transport leaf has inert output/error/exit/timeout/descendant controls at all
byte limits. A separate two-instance regression starts older and newer isolated
shells at one path: path-only IPC demonstrates the ambiguity, while the production
helper must return the DTO owned by each exact PID. A separate QML fixture executes actual NativeCatalog, QProcess and
helper/custodian code, replacing **only** the IPC leaf with an inert process tree.
It exercises success, command failure, TERM cancellation, owner replacement,
forced SIGKILL and Loader destruction. A missing-interpreter substitution tests
actual QProcess start failure. PID/start-time checks run before test-cgroup cleanup
so that cleanup cannot conceal surviving descendants. Disabling the custodian's
parent-death signal must reproduce an observed surviving descendant. The launcher
and custodian also unblock their owned cancellation signals even under an inherited
blocked mask; a separate masked hard-kill/destruction control verifies that need.
This is not
a malicious-child sandbox or a live-desktop test.

The production update service owns the local catalog and its independent
holder-bound demand registry. The scoped Bar owns one persistent read consumer;
the active Control Center Plugins page owns a second consumer and releases or
rebinds its exact lease with the controller. `tests/group-registry-regression.qml`
covers complete nested ancestry, missing parents, cycles, exact 32/33-row
traversal, contradictory known chains, enabled-clone suppression of the original,
clone render identity, immutable `entries`/`byId` identity, prototype rejection,
and no scoped legacy/name fallback. Legacy unscoped cases remain in the same
test.

`tests/bar-host-registry-regression.sh` additionally runs the actual Bar with a
controlled scoped Runtime service. It proves holder identity, exact token/service
release and reacquisition through duplicate loss and provider replacement, final
release on Bar destruction, stale-observation refusal, and unchanged host/registry
mutation counters after catalog publication. The fixture has no live shell,
network or platform mutation route, and catalog changes do not start the Bar's
mutation/reconciliation timer. This is lifecycle and read-classification evidence,
not a Control Center page, native mutation, rendered desktop or physical-output
claim.

The demand gate covers exact token identity, reentrant release/acquire, holder
and service destruction, the 64-holder bound, scoped admission/revocation,
source replacement, suppression of State/config and widget-registry fan-out,
explicit refresh, five-second reconcile, primitive observations and separation
from update scans. It also proves that equal catalog content across demand and
failed-read gaps does not invalidate update results, while changed content does
so exactly once. A cached update result that predates the first catalog read is
invalidated by that first changed publication, and no retained snapshot crosses
the declared `PluginUpdateService` facade after revocation. Seven calibrated
controls and restored positives exercise these
contracts with an inert backend. In the pinned native fixture below,
`FixtureCatalogService.qml` only exposes observation IPC over the production
service facade; native injection supplies its shell/path. That separate run uses
the unchanged helper and actual public native `listPlugins` IPC, not the inert
transport replacement. See the shared-runtime contract for remaining metadata,
consumer and resource gates.

## Pinned native-root integration fixture

```bash
python3 tests/source-snapshot-regression.py
python3 tests/isolated-files-regression.py
python3 tests/isolated-resource-regression.py
python3 tests/native-runtime-regression.py \
  --native-shell /path/to/omarchy-v4.0.3/shell
python3 tests/native-catalog-fallback-regression.py \
  --native-shell /path/to/omarchy-v4.0.3/shell
python3 tests/native-catalog-resource-regression.py \
  --native-shell /path/to/omarchy-v4.0.3/shell
python3 tests/all24-scoped-service-regression.py \
  --native-shell /path/to/omarchy-v4.0.3/shell
```

The runner admits exactly 183 regular files from commit
`0534987009061cbe2dacdde4ad564092ab698d12`, with the whole source inventory bound
to SHA256 `2cd0ffb0c38f31868e28c3556f0efc530f4fcd04765856ec157bc070eac748a0`.
Its inventory serialization is specified beside the constant. Symlinks,
nonregular nodes, extra/missing/drifted bytes and unbound empty directories refuse
before execution. Acquisition uses no-follow directory handles, per-file
identity checks and file/count/depth/aggregate bounds. Only captured bytes are
staged. `--admit-only` checks the source without launching Qt. The suite itself
is a fingerprinted WIP snapshot, not an accepted release commit.

Bubblewrap supplies private HOME/XDG, PID/network namespaces and unavailable
production buses/compositor/devices. Staging is mounted read-only; runtime writes
use 64 MiB fixture and 32 MiB temporary tmpfs mounts. A new, owned cgroup under
the current user's delegated `app.slice` limits all fixture descendants to
512 MiB memory, no swap and 64 tasks. Only the launcher migrates itself; the
caller and production processes never move. No parent controls, systemd units or
desktop configuration are changed. Missing delegation/controllers refuse rather
than running unconstrained. Resource probes exercise cgroup OOM, PID refusal and
tmpfs ENOSPC, and verify owned-group removal. The only suite roots installed are
State, Bar and Control Center; the catalog control adds the explicitly constructed
inert service described below. Other native manifests are withheld from discovery.
Three explicit window replacements cover the suite BarPanel, native stock bar
and CC panel window shell; a controlled Health helper replaces the real check.
Fixture subclasses add observation IPC to the actual State and Bar components.
The host registry supplies the actual CC widget component; its actual panel body
uses the actual State and update-service objects.

The probe starts with the stock-bar window stub and calls the actual scoped
State service's `updateEntryInline` capability. It writes a complete own
`plugins[]` entry with nested settings, preserves unrelated entry fields and the
rest of the document, and requires matching public `listShellConfig` and later
fixture-disk readback. Cold stock must publish the loaded stock stub as its bar
owner. It repeats the writes under the suite bar and after selecting stock again;
identical writes return false and foreign-entry writes refuse. Full entry data
must survive the switches and native rescan. The fixture also exercises the
production State storage controller: public setters report queued acceptance,
rapid setters compose, and matching file readback confirms publication under
stock and suite bars. This is not complete migration or lifecycle acceptance.

The existing probe also checks publication, retained State across native rescan,
panel-originated settings and sibling preservation. After the native PluginBarApi
route, it injects the actual visual Bar as production WidgetSlot does and verifies
that the actual panel's restore is held until file-backed State settlement. A
fixture-only invalid-manifest pulse revokes Bar admission while State stays ready;
both State-bound and unbound restore records disappear, and subsequent readback
cannot revive them. This is cooperative admission coverage, not a native owner
switch or physical panel replacement. It closes and removes its explicitly
created widget before testing bar-owner switching and re-selection in that engine. That is **closed-widget fixture coverage**, not open-widget/output
teardown or the production transactional restart boundary. Legacy Bar-owned
storage is not used by production State. The same-engine return requires
the stock stub to be loaded and selected, but reports its root-owner publication
separately: this fixture observed `publishedOwner:false` after the hot switch.
That is not successful production bar-owner handoff; the required restart boundary
is unchanged. The positive cold-stock ownership check remains mandatory.
Owned process groups retain their leader
until cleanup, and the outer PID namespace and temporary directory are removed.
IPC capture, total runtime and files have separate finite bounds. Config/log
reads use no-follow descriptors and bounded reads, including replacement-race
checks; the log tail is bounded on failure. A separate 16 MiB per-file allocation
ceiling permits Qt startup allocations without widening the 1 MiB text-log or
64 KiB IPC caps. Cgroup cleanup kills only that owned group and requires it to
be empty before removal.

The catalog extension additionally constructs one inert third-party fixture
service beside the three suite roots. This is a declared fixture manifest, not
an added production ID. A test-only CC service subclass (no extra Runtime import or second catalog)
checks the production facade has no native reader before demand, then exercises
actual helper/QProcess/native IPC DTO identity and no configuration writes by reads. Public native commands enable and
disable the inert service; the demanded catalog observes its changed enabled
field and the final config matches the original. Widget revision also changes
because this host re-registers existing widget metadata; the initially assumed
unchanged-revision assertion was invalid and its failure is retained. This test
measures convergence, not the necessity of polling. After release it spans a full
five-second interval with no new request, no native Loader and no publication.
A separate maintained fallback gate adds a read-only observer and inert failing
bar only to the private materialized native fixture. Exact log lines/counts prove
the native async load failure, and the last public-hint DTO differs from the
later live DTO while service/API identity remains stable. A calibrated native
mutation emits a later real public hint and must fail the original gap assertion;
the staged root is then restored byte-for-byte for a final positive. This proves
the missed-hint need, not a stale production response or a host extension.

The native-root fixture exercises both Bar and page catalog consumers. Its
initially disabled third-party widget covers current-observation activation,
settled deactivation and refusal to remove an active widget before process
start. Fixed Shibumi groups use the State-only channel. A catalog-only Audio
provider covers serialized V1/V2 replacement, return to Shibumi, exact undo and
stale-postimage refusal without relying on a preloaded component. These are
isolated native-host flows, not rendered desktop or physical-output evidence.

`tests/state-storage-regression.py` isolates the actual controller with an explicit
own-entry writer and private configuration files. It exercises debounce, in-flight
composition, preservation, foreign conflicts, false/no-op convergence, readback
failure, synchronous revocation from pending/status/value notifications, and
immediate requested-state preview with rollback to file truth. The corresponding
service gate proves that activation, nested AI selection, workspace and launcher
requests preview before authoritative publication.
`tests/state-service-regression.sh` exercises the actual public State setters with
file-backed assertions after settlement: bulk V1/V2 enablement, nested settings,
appearance resets, variant memory, pickers, launcher, layouts, optional center,
separators, Reactor, external edits, and unknown-field preservation. These fakes
cannot call a production writer. Positive QML runs require exit zero, their
success marker, and no runtime/binding errors.

The State service gate also passes `--transition-controls`. Actual public setters
batch V1/V2 layout, boundaries, separator presence and per-variant family state
in one commit; tests require one dispatch, no optimistic publication, exact
restoration of absent flags and preservation of unrelated data. Invalid patch
shapes and saturated widget normalization refuse the whole request. Conditional
compensation is tested against pending work, newer serials, mismatched field
scopes and an intervening external file publication. Four captured-Service
mutations calibrate normalization-loss, field omission, serial and published-
projection assertions, alongside the existing preservation control and a restored
positive. The normalization guard makes field omission refuse before enqueue;
its expected diagnostic is `atomic transition refused`.

The pinned native fixture also applies this combined State patch under the stock
bar and confirms compensation through actual own-entry writes/readback. It checks
that neither State-only request changes the native Bar object. String plugin
entries before and after the State entry are preserved. A separate extension
then exercises actual Bar/LayoutController/State-to-native sequencing: queued
State cannot mutate native layout immediately; State readback precedes the
native mutation, and separately injected Bar configuration confirms the moved
entry while retaining opaque data. A constructed unregistered entry stays empty,
with no fabricated manifest or original-component substitution. This tests the
API chain, not a rendered V2 desktop. An incomplete scoped State override lacks
one atomic method and must reject legacy layout/family fallback without writes.

`tests/layout-transition-regression.py --controls` exercises actual coordinator,
LayoutController and captured Bar planning methods with complete inert State and
native replacements. Twenty-five cases cover delayed/synchronous State,
no-op/false returns, separate native publication, exact serial/projection gates,
missing entries, owner loss, busy/phase/serial reentry, conditional compensation,
reset field presence and indeterminate post-assignment failure. Six calibrated
captured-source mutations are bracketed by positives. No production writer,
compositor, helper or service fallback is reachable in this fixture.

The maintained Bar gate additionally creates a separate actual Bar (no output
surfaces), inert output-local panels and separate fake publication clocks. After
State settles, 1.8 seconds of native publication delay must spend zero restore
attempts; only then may the replacement reopen on its saved page. The restore
control driver now includes ten mutations, including removal of this native hold.
The delayed combined restore fixture is unscoped; the native scoped API chain is
separate evidence, not a combined scoped/physical owner-handoff proof.

Family, provider and catalog requests use distinct owner/serial channels and
publish success or Undo only after observed settlement. Stale snapshots,
revocation, timeout, active-plugin removal and intervening edits fail closed.
The fixtures do not claim a durable cross-store transaction or undo of an
indeterminate native action.

The separate all-suite regression materializes all 24 admitted plugin roots in
the pinned host. It verifies the exact 18 service owners, implementation and
manifest binding, scoped host publication, and complete revocation when the
Runtime retires. Platform owners are withheld and no output surface is created.
This is not complete-host, renderer, hardware or desktop acceptance; complete
notifications, idle/lock behavior, package lifecycle, restart and physical
multi-output evidence remain open.

## Live validation

After the complete contract passes:

```bash
./scripts/shibumi-suite update --dry-run
./scripts/shibumi-suite update
./scripts/shibumi-suite status
```

Maintainers then verify the affected user flow in a real Wayland session. For
UI changes, inspect Top and Bottom placement, open and closed state, Escape and
outside dismissal, focus transfer, theme changes, bar switching, shell reload,
and idle/screensaver behavior when relevant.

Use screenshots and Quickshell logs as evidence. Record the exact Omarchy
version, output geometry, scale, source commit, and any physical state that
could not be exercised.

## Hardware and output gates

Fixtures prove deterministic unavailable, degraded, and error states. They do
not replace:

- physical mixed-scale and hotplug behavior;
- enterprise Wi-Fi authentication and recovery;
- Bluetooth pairing, routing, disconnect, and forget;
- suspend, resume, DPMS, and device-specific behavior.

Open physical gates stay explicit in
[release readiness](../release-readiness.md).
