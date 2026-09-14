# Beta.14 Loader admission review

Scope: issue #54 scoped Component admission, current Loader completion, removal
of the output-recovery rescan, passive diagnostics and focused regressions.
This is a targeted follow-up, not a second overall Beta.14 review or release
approval. The candidate remains uncommitted on base
`3cb7f6d26df47b0e2d697575e4b42ba48e405c1d`.

## Independent finding

**Medium — invalidation reentry could dispatch a superseded source.**
`WidgetSlot.submitLoaderSource()` invalidated completion before claiming its new
source/generation. While replacing loaded A with B, a synchronous observer of
`loadedSourceComponentChanged(null)` could publish A again. The nested request
returned as unchanged, then the stale outer request dispatched B. The reviewer
reproduced a fixture timeout with mismatched resolved/submitted source.

The correction claims one atomic request before invalidating completion and
checks ownership after each signal-emitting write. A still-resident, previously
confirmed A item can satisfy a newer A request if no intervening setter was
dispatched; this does not invent an `onLoaded` event or duplicate its Ready
report. Resident identity must still match the actual Loader item, dispatch
provenance and current resolver. Teardown and actual replacement revoke it.
There is still exactly one controlled `sourceComponent` setter and no new timer
or process.

The maintained scoped-loader regression reproduces the original ordering in a
private copied source. It must fail with `invalidation reentry dispatched stale
source B`; the unmodified candidate must then pass. Existing injection/completion
reentry, type refusal, Loader.Error, disable, configuration removal, registry
replacement and legacy checks remain required.

## Verification after correction

- Scoped-loader ordering negative control and candidate: passed.
- Bar-host regression and production-boundary checker: passed.
- Complete production-boundary regression: 18 tests passed after an earlier
  240-second harness timeout; the successful rerun took 263 seconds.
- Documentation, panel vendoring, seven startup-prime modes, bounded census IPC
  and host-facade contracts: passed after the correction.
- Census classifier: eight tests passed, including first-versus-later output
  chronology and refusal of stale Loader provenance.
- Final native comparison: all four arms passed their required outcomes. The
  actual candidate survived three real nested-output cycles, with current load
  provenance after every return, one startup rescan total and no passive warning.
- [Source-bound native evidence](evidence/beta14-widget-pipeline-loader-admission-2026-09-13.json)
  contains the final identities, 20 census records, four results and raw-log hash.

Focused independent re-review confirmed the finding fixed, with no new
concrete findings in this scope. The reviewer reran the negative/candidate
scoped-loader regression and verified the source/log hashes and all native
result records; the native Wayland run itself was not repeated by the reviewer.
Complete release gates, the original PSS failure, physical tests on both hosts
and reporter confirmation are separate. A single inert widget is not full-suite acceptance;
the user's currently incomplete desktop bar is not an accepted installation.
