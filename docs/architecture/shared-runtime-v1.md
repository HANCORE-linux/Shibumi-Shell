# Shared Shibumi runtime V1

Status: normative supporting contract, authorized 2026-09-09; implementation
and 4.0.3 acceptance in progress. ARCHITECTURE.md remains authoritative.

## Scope

The suite retains its 24 separately registered plugin IDs and one production
Quickshell process. The sole production shared module lives at
`hancore.shibumi.state/runtime/`. It is maintained there directly, not copied
into every plugin. Other canonical/vendored sources still use the sync scripts.
Installation, update, repair and removal continue to operate on the complete
admitted suite. This dependency does not grant permission to weaken admission,
load a partial mixed-version set, or import arbitrary sibling/repository paths.

The runtime connects cooperating Shibumi services, consumers and the active
Shibumi bar. It does not discover foreign plugins, create backend instances,
read authentication objects, traverse the host graph, or own output windows.
It is not a QML sandbox or an enforceable security boundary against arbitrary
code executing in the same user session. Native object and process ownership
remain in the existing feature services. Views receive existing feature
facades, not newly exposed native backend objects. The client shell adapter
retains the host's bar-state surface; it does not export the entire active
Shibumi bar. The coordinator retains internal provider references, exposes
bar presence/owner checks and a detached bar-config snapshot. State owns its
service-entry persistence directly; the coordinator has no State write broker.
Underscore-prefixed internals are conventions,
not an enforceable access-control boundary.

The exact importer roster is maintained in `scripts/shared_runtime_contract.py`.
Both source-boundary checks permit only its literal QML import directives and
require the complete, non-symlinked sibling module. This is the sole exception
to plugin self-containment; arbitrary sibling paths and alternate copies are
not granted an import exception.

## Lifetime and version

One module instance per production QML engine is required and tested from
multiple importer directories. One instance in a five-line probe does not
prove the host's complete load/reload lifecycle.

A provider declares its exact ID, role, executing implementation version,
current injected manifest and scoped host. Registration waits for these inputs
and the runtime's own managed marker. Missing or mismatched inputs refuse;
invalid replacement inputs, including getter failures, revoke the old lease.
Two overlapping providers for one ID make that ID unavailable; no last writer
wins. Revocation removes only its own lease and cannot remove a replacement.
Bindings observe availability, creation, removal and scope replacement.
Semantically equivalent retained-manifest refreshes keep the same lease.
Actual replacements publish a final lease set atomically, never an intermediate
set that briefly exposes an overlapping provider.

The runtime uses the suite marker at its own State plugin location. Marker
failure or a marker change retires the runtime for that engine; it does not
silently upgrade an existing engine to different installed bytes. The existing
transactional drain-before-publication and complete payload validation remain
mandatory. Registration is a wiring/lifetime check, not independent proof of
all source-file hashes. Full payload identity remains the installer's and
activation checks' responsibility.

## State writes

State owns schema-1 settings in its unique `plugins[]` entry, marked by
`shibumiStateSchemaVersion: 1`, and writes the complete entry through its own
native `updateEntryInline` capability under stock and suite bars alike. Unknown
entry fields survive. A layout-placed, duplicate, missing or malformed canonical
entry makes State unavailable. Runtime never revives legacy `bar.shibumi`.
The drained suite lifecycle performs the one-way migration and binds its storage
version to the admitted payload. See ARCHITECTURE.md for native destructive
disable, dormant `--keep-settings` and rollback behavior.

Two read-only FileViews watch user `shell.json` and the official defaults.
Missing/zero-length user files use defaults; corruption and read errors refuse.
The views follow native local-file acquisition semantics, not bounded streaming
acquisition. No subprocess reads the settings. A 75 ms one-shot debounce merges
rapid changes against pending desired state. Dispatch rereads the full entry
and preserves unrelated fields. Each dispatch/readback has a two-second
one-shot deadline; admission loss cancels queued work and stale settlement.
There is no recurring readback poll.

A setter returning true accepts a queued request, not a successful save.
`config` and `revision` follow authoritative file reads only. `writePending`,
`writeStatus`, `writeSerial` and `persistenceSettled(throughSerial, result)`
expose completion separately. `confirmed` means a changed native call followed
by equal full-entry readback; `unchanged` also requires equality, because the
native false result is ambiguous between refusal and no-op. Timeout, conflict,
invalid input and revocation are not successful settlement.

Comparison is structural JSON equality: object-key ordering is insignificant,
array ordering and values remain significant. Observed publication is not an
fsync/crash-durability guarantee or host-wide CAS. No direct runtime file writes,
retained revoked capability, fake bar kind or shadow settings store is allowed.
The pinned native fixture exercises queued writes and file readback under cold
stock and suite bars; consumer, complete-host and desktop acceptance remain
separate gates. The runtime coordinator is not the persistence owner.

### Atomic layout/family State requests

`setLayoutFamilyTransition(patch)` batches the State part of a transition into
one existing own-entry commit. It accepts a nonempty selection of `v1Layout`
(`order` and `splits` together), `v2Layout`, `v2Boundaries`, `separators` (group to
boolean/null), and `familyStates` (group to complete `v1`/`v2` boolean/null pair).
Null restores field absence, not explicit false. Unknown fields, invalid layouts,
non-string slot IDs and incomplete pairs refuse the whole patch. The bounded
widget normalizer must retain the complete affected projection; partial
normalization refuses before enqueueing. The old layout and bulk-family setters
use this same implementation. No settings schema or native ownership changes.

`layoutFamilySnapshot(patch)` captures only the requested fields from published
State. `compensateLayoutFamilyTransition(expectedSerial, expectedPatch,
rollbackPatch)` is a conditional queued request, not a completed rollback: it
requires readiness, no pending write, the current State serial, identical field
and group scopes, and matching affected file-backed values. It rechecks the
serial and draft projection inside the commit. All unrelated State fields remain
outside the patch. The caller must retain and revalidate the same State owner
and its own admission; serial values are not cross-owner identities. These local
preconditions do not provide a host-wide or filesystem compare-and-swap.

### V2 State-to-native layout sequencing

The persistent Bar owns one `core/LayoutTransition.qml`. V2 layout edits,
reconciliation with native sync, and reset submit one patch through it. Busy
transitions reject competing layout edits; they do not queue stale plans. Each
operation captures exact State/native writer identities, State serial, affected
preimage/target and a transient native intent. State settlement must match that
serial and the published projection before native work is deferred to a later
turn. Synchronous settlement is captured without running native code inside the
setter. Admission/owner loss revokes work, including after synchronous busy or
phase notifications. Explicit busy/phase publication avoids binding feedback.

A necessary native edit plans from the current callback's complete Bar/layout,
not a snapshot taken before the State write. Opaque Bar/entry data survives.
Only separately injected `barConfig` equality confirms the native postcondition;
a truthy method return does not. An already-present injected target needs no
native write, avoiding a no-op registry/reconciliation loop. A matching native
false/no-op can also satisfy the postcondition. One Bar-owned one-shot timer
bounds State/compensation phases at five seconds and native publication at 2.5
seconds; it stops on settlement/revocation and performs no readback polling.

If no requested native layout could have been assigned (including a pre-assignment
throw), only the still-owned State projection may be conditionally compensated.
Its readback must settle too. After possible native assignment, a timeout/throw
is indeterminate: it must not trigger a speculative State rollback followed by a
late native publication. Cancellation cannot undo an applied native action.
This is not a durable cross-store transaction, native/global CAS, or confirmation
of native filesystem durability.

Control Center restoration additionally holds its output-local records through
the full transition, not just the first State settlement. The rebuild window
starts after that hold releases. Late completions cannot revive user-cancelled,
revoked or replaced restore identities.

The multi-step family/provider/catalog and clone flows are still unfinished.
Their old synchronous chains refuse when the atomic State API is present;
scoped hosts with an incomplete State API cannot fall back to them either.
Only unscoped legacy presentation hosts retain that legacy route. This temporary
fail-closed behavior is an explicit acceptance blocker, not a reduced release
feature contract. Full V1/family/native restoration and catalogue integration
remain separate work. All transition boolean returns mean request acceptance,
not completed persistence.

## Public catalog service foundation

The existing process-wide Control Center `PluginUpdateService` owns its local
`NativeCatalog`, command/model and read-interest registry. The admitted service
passes its exact scoped shell identity and injected `omarchyPath`; no Runtime
importer or provider boundary is added. Opaque, holder-bound interest tokens can
request only a detached observation or queued refresh and confer no native
identity or mutation authority. Interest survives transient provider loss while
the holder lives, but catalog publication and work are revoked immediately.
The final holder release stops acquisition and reconciliation independently of
the update-check worker and its separate consumers. At most 64 live catalog
holders are admitted. The admitted scoped Bar now holds one persistent catalog
consumer for native family read classification; the page-bound Control Center
consumer remains separate and unwired. Provider loss releases the Bar's exact
service/token pair, and replacement reacquires without consulting the legacy
registry. Bar destruction releases the final demand. The complete mutation
workflow and Control Center presentation remain acceptance blockers.

A read invokes only `quickshell ipc --pid <Quickshell.processId> call -- shell
listPlugins`; separate bounded `/proc` checks bind that PID to the injected
`<omarchyPath>/shell` process path before and after IPC. Its detached
`native-listPlugins` DTO retains native
`id/name/kinds/enabled/active/canDisable/firstParty/clonedFrom` identity and adds
only bounded display/search metadata from the matching package manifest. It is
not an `installedPlugins` manifest map, component resolver, settings store or
native revision. Manifest discovery is count/byte/probe bounded; every path
component and final file is opened without following symlinks, and changed or
ambiguous files refuse publication. This enrichment grants no mutation right:
a current exact host component selection is revalidated before activation, so
`defaultSection` can only suggest placement after that authority exists. Native
ordering is retained. Empty-but-valid is ready; malformed, ambiguous or
unavailable is not. JSON keys and catalog IDs must be unique; booleans, Unicode,
structural depth and sizes are checked before publication.
Ancestry must complete within one immutable current observation and 32 entries,
without missing or cyclic parents, mixed `entries`/`byId` rows, or inherited
prototype lookup. Classification validates the complete chain before accepting
a known capability, rejects contradictory known identities, and uses no display
name or category heuristic. An enabled direct clone suppresses classification of
its original ID; the clone keeps its own render ID and never falls back to the
original component. Missing, stale or malformed scoped observations classify as
empty. Legacy unscoped manifest classification remains unchanged. Local
generations/serials are observations, not CAS or authenticated mutation
authority.
One accepted read retains its exact owner, directory, backend and serial until
completion **and** drain. Backend replacements also wait, including A-B-A; a
QObject-typed guard observes destruction of an old backend without a drain
signal. An incomplete explicit override suppresses native construction, including
when that override loses support after publication. Admission/demand/source loss
clears authority before cancellation; old callbacks cannot republish. A throwing
cancel delegate cannot abort invalidation bookkeeping or count as completion.
For accepted work, exact drain wins over an invalid/stale `busy` value. Immediate
`refresh()` refuses busy work. `requestRefresh()` means accepted/queued and
coalesces one follow-up after drain; actions must not mistake either return for
a fresh native postcondition. Normal refresh retains display data until its
result, but that old observation cannot independently authorize mutations.

The Python helper caps simultaneous stdout/stderr acquisition at 262144/8192
bytes and three seconds; strict UTF-8/JSON rejects duplicate keys and nonfinite
values. The native shell PID selects the IPC server; bounded `/proc` identity
checks bind that PID to the exact shell directory before and after the read, so
an overlapping older instance of the same path cannot answer. It exposes no
native stderr. The QML command owns a five-second one-shot
deadline and TERM-to-KILL cancellation with a 1.5-second grace. A separate
short-lived custodian owns the IPC process group, permits launch only after its
ready/start handshake and retains group identity until cleanup. Launcher death,
including QProcess destruction/SIGKILL, makes the custodian kill the reserved
group. Owned cancellation signals are unblocked even when the caller inherited
a blocked mask. This covers the trusted IPC client and same-group descendants, not
malicious children escaping into new sessions. No second shell or platform owner
is launched; these are IPC acquisition/cleanup processes only.

One demand/admission-bound five-second single-shot reconciliation starts only
after the preceding operation has drained and is stopped on final demand release
or owner loss. Queued explicit refreshes remain separate. Public scoped
`barConfigChanged` and widget-registry revision are non-authoritative refresh
hints, not a catalog revision. An isolated pinned-native test proves that async
bar-loader fallback can change effective active-Bar DTO fields after the final
public hint; a calibrated staged-host counterexample supplies the otherwise
missing later hint and makes that gap assertion fail. This justifies a bounded
fallback, but does not establish that five seconds is optimal. Isolated cadence
and native tests show post-drain spacing and silence after release. The pinned
resource gate bounds the one launcher/custodian/IPC acquisition tree to three
processes, includes observed descendants in warm-cycle CPU accounting and checks
host PSS retention with calibrated QML/helper CPU and retention counterexamples.
Real-consumer resource acceptance remains open. The timer and incomplete Control Center consumer/mutation integration are not
production release acceptance. Catalog publication can update the Bar's
read-only family projection; it does not start a Bar mutation or layout
reconciliation timer.

## Remaining integration gates

Foreign component/manifest and clone selection remain host-authoritative.
Only confirmed host mutations may update plugin state. Runtime cooperation
alone supplies no native notification rows or targeted actions. Notification
ownership is unchanged by this contract; a sole-owner clone handoff would
require a separate explicit decision. No second notification server is allowed.
Idle's public status must be consumed without changing policy or confusing
window visibility with secure lock state. Physical acceptance stays separate
from isolated QML tests.
