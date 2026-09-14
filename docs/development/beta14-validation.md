# Beta.14 candidate validation

Status: candidate validation record; not release or physical acceptance.

## Performance scope

General performance investigation is paused pending actionable reporter data.
The reported slowdown is not limited to animation stutter; neither the picker
fix nor idle CPU/PSS alone establishes restored responsiveness. No speculative
optimization or additional one-/four-hour profiling requirement is part of this
Beta.14 closure. The Native Catalog memory gate below now measures cold
initialization separately from warm steady-state retention.

The picker presentation facade fixes missing color properties on a scoped host.
The regression uses private real image fixtures, permits only the two explicitly
expected action-failure warnings, and rejects the old facade handoff in a staged
negative control. This proves the warning defect, not the cause of every report.
Health reports owner-attributed warnings from its existing bounded on-demand log
sample. It does not invent a boot/hour rate from the last 400 lines.

Isolated offscreen native measurements found two catalog acquisitions per logical
plugin enable/disable mutation in both Beta.13 and the candidate. Across three
runs per source, median catalog settlement was approximately 385/381 ms and host
CPU was 0.15 s per ten mutations. Snapshot-copy timing was below a useful
millisecond-resolution attribution threshold. These results do not support
speculative JSON/GC/timer changes or a claim of improved desktop performance.
The process-wide catalog still reconciles approximately five seconds after drain
while demanded. Removing its freshness work requires separate correctness proof.

### Native Catalog warm-state memory gate

The PSS ceiling remains exactly **512 KiB**. The gate now records three cold
Catalog acquire/release reconstructions separately, sets the warm baseline to
the third cold-cycle sample, and then checks the unchanged maximum-over-baseline
assertion across exactly three warm acquire/release cycles. It neither invokes
GC nor changes production cleanup behavior. Cold growth remains visible in the
structured output but is not mislabeled as repeated warm-state retention.

This definition is evidence-bound. Under the earlier pre-cold-cycle window,
cross-substitution runs failed at 1,116 KiB, 892 KiB, and 848 KiB while a scoped
presentation-module/Control-Center-BarWidget negative control passed at 252 KiB.
Those results did not isolate a retained production owner. The controlled 3+3
split then measured 0 KiB warm growth for the candidate while a touched synthetic
2 MiB-per-cycle retention mutant grew by 5,980 KiB and failed. This showed that
the former window could stop on transient cold reconstruction while the warm
window still discriminated deliberate per-cycle retention.

The maintained gate requires the exact 3+3 record and the 512 KiB ceiling. Its
first retained run used the complete current fixture roster and exact Beta.13
Git blobs from commit `2760cdb8272255790d5e4613fed8a48cb63c3555` for the
24-plugin source arm. Acquisition uses pinned `/usr/bin/git`, disables and
refuses replacement refs, admits only the exact 24 root pathspecs, and enforces
the 16 MiB archive bound while reading as well as during extraction. The
measured native fixture loads the exact State, Bar, and Control Center roots
from that arm. Exact Beta.13 passed with 832 KiB cold
initialization growth and 0 KiB warm growth; the candidate passed with 848 KiB
cold growth and 0 KiB warm growth. The synthetic retention mutant failed at
5,928 KiB warm growth, and the byte-restored candidate passed at 0 KiB. The
bounded log is `/tmp/shibumi-beta14-native-catalog-resource-warmup-final-r3.log`
(SHA-256 `18807f12f1b861beb32ca1c3ceaa929dd1a1944ffe6c647763af2ab483dfe240`).
These isolated results satisfy the resource contract; they are not a production
memory fix, a general responsiveness result, or physical desktop acceptance.

### Aborted allocation diagnostic

The tcmalloc allocation diagnosis was not completed. The investigation was
aborted after r1 exposed a nondeterministic Quickshell Boolean-option conversion
failure when mmap profiling and UTF-8 locale state interacted (the observed
locale race), and r2 stopped on an invalid cross-namespace device-number identity
rule for executable mappings. No r3 run, product A/B comparison, accepted
difference-in-differences result, or symbolization followed. The existing r1/r2
artifacts and their recorded hashes remain unchanged. This setup failure and
aborted diagnostic establish **no product finding** and do not explain either
PSS behavior or reported responsiveness.

## Issue #54: scoped Loader admission fix

The stock bar passes the current host-published Component directly to its Loader.
Shibumi additionally required the JavaScript property `component.status` to equal
`Component.Ready`. The isolated output-loss comparison shows that property
becoming `undefined` while the Component remains instantiable. Restoring that
extra guard in a staged candidate reproduces the failure.

The scoped resolver now checks exact current configuration/metadata identity and
`instanceof Component`, then lets the Loader determine load success. The actual
`instanceof` implementation, not a guard-free substitute, is exercised by the
native regression. Legacy locally created Components retain their status checks.

The typed `Loader.sourceComponent` getter also projects null after output loss
in this fixture. One controlled source setter therefore records actual submission
provenance. Only `onLoaded`, real `Loader.Ready`, the exact completed item and
current submitted/resolved/registry identity may establish success. Source
replacement, disable, revocation and reentrant injection invalidate stale loads.
Slots register before source submission. The [focused review](../audits/beta14-loader-admission-review-2026-09-13.md)
found and rechecked a correction for reentry during completion invalidation.
Atomic request ownership prevents a stale outer request from loading a superseded
source. Returning to the same still-resident, already confirmed item does not
require an invented `onLoaded` event or duplicate Ready report. Why these
JavaScript projections are lost remains unexplained; the fix does not depend on
an assumed Qt root cause.

The second rescan, its lock probe and recovery state machine have been removed.
Only the existing exact-PID startup prime remains, at most once per process.
After a proved output-loss/return sequence, a previously loaded but now unresolved,
still-configured/enabled widget may emit one sanitized exhaustion warning after
ten existing resolution attempts. This is passive and its process-wide budget
survives replacement Bars. No additional process, timer, retry loop or auth
access is introduced.

Census version 2 preserves the integer status fields and adds `componentPresent`
and `componentStatusKind` (and corresponding resolved-slot fields). Missing
handles are distinct from `undefined`, numeric, other or unavailable status
projections. `currentLoadReady` reports the current submitted/completed tuple;
`outputLifecycle` records bounded chronology and warning state, not recovery
activity. Historical Beta.13 instrumentation explicitly marks its unavailable
lifecycle observation and cannot claim the new load-provenance check.

### Native A/B evidence

Run the isolated nested-Wayland fixture with the admitted native source:

```bash
python3 tests/widget-pipeline-native-regression.py \
  --native-shell /path/to/omarchy-v4.0.3/shell
```

The host shell is pinned to commit
`0534987009061cbe2dacdde4ad564092ab698d12`. Native authentication/backend
manifests are withheld; there is no lock fixture or lock query. A disclosed
host-side counter observes calls to the public rescan entrypoint. The fixture
does not exercise a real session lock or physical monitor.
Beta.13 is taken from exact commit
`2760cdb8272255790d5e4613fed8a48cb63c3555` plus a disclosed read-only diagnostic
overlay. The candidate is bound by staged plugin fingerprints, not its HEAD alone.

The [current census and identities](../audits/evidence/beta14-widget-pipeline-loader-admission-2026-09-13.json)
record three real `1 -> 0 -> 1` nested-output cycles. Beta.13 loses component
admission in each cycle and requires three explicit control rescans (four total,
including startup). The candidate creates four marked widgets, destroys three,
retains `currentLoadReady=true` on every returned output and makes exactly one
rescan total: the startup prime. Registry revision stays unchanged and no
passive warning is emitted. The marked widget must reach a visible backing
window on the current nested output, not merely exist as an Item.

The staged status-guard mutant loses the widget, emits exactly one passive
warning and makes no additional rescan. A separate missing-entry-point control
requires a real BarPanel and unresolved WidgetSlot. These controls demonstrate
Shibumi's admission defect, not a general host registry-removal failure.

The [earlier workaround census](../audits/evidence/beta14-widget-pipeline-2026-09-13.json)
is historical evidence only. Its `-1` conflated missing handles with unavailable
status projections, and its additional recovery rescan is no longer candidate
behavior. No old restore interval is attributed to the new implementation.

## Physical acceptance still required

After separate candidate-installation approval, on both Omarchy 4.0.3 hosts:

- compare Beta.13, the exact candidate and the stock bar with documented plugin
  and service configuration;
- test V1 and V2, top/bottom, repaired functions and stock-bar return;
- use the monitor power button and prove actual output loss and return, not just
  DPMS darkness; require automatic recovery without a manual rescan;
- test repeated flaps without any additional native rescan; the one startup
  prime is not replenished by output or Bar-owner changes;
- compare census, 24 plugins, 18 owners, one production process, settled lifecycle
  and coredumps before/after; a new coredump stops acceptance;
- record PID plus process start identity, exact payload, host versions and timed
  warning counts; a truncated sample cannot provide a complete warning rate.

The local desktop's incomplete widget configuration and the isolated single-marker
fixture are not a passed full-suite installation. Full widget/function acceptance
must be explicit on both hosts after authorized candidate installation.
General performance sampling remains paused. Mark physical multi-output
`SKIPPED` until two physical outputs are active. Keep #54 open pending reporter
confirmation; do not post diagnostics, restart a desktop or publish a candidate
without separate approval.

## Safe reporter checklist

Request the selected bar variant, affected actions, cold/warm behavior, time
since shell start, Omarchy/Quickshell/Qt/compositor/driver versions, and whether
the same workload affects the stock bar on that host. For #54 also request the
bounded `debugWidgetPipeline` report from the exact shell instance and a redacted
log window around the event. Select exactly one instance using its registered
configuration path and PID; do not use broad `pgrep -f` matches or request the
entire user journal. Never request credentials or AI session history.
