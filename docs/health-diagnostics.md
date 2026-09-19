# Health diagnostics contract

Status: implementation contract for issue #5

The Configure route formerly labelled **Advanced** is **Health**. It answers
only whether the selected Shibumi or Omarchy bar runtime is healthy, what
failed, and which safe next step is supported by current evidence.

## Retired Advanced actions

No underlying capability is silently removed:

- **Reload Shibumi** remains on Quick, its immediate operational context. The
  duplicate Configure-overview and Advanced actions are not diagnostic checks.
- **Reset bar layout** remains in Bars and its V1/V2 capability-specific
  layout sections.
- **Icons** and **Layout** were navigation shortcuts to existing Configure
  routes. Persistent Configure navigation remains authoritative.
- **Lock**, **Suspend**, **Reboot**, and **Shutdown** remain in Omarchy's
  authoritative App Menu. Health does not wrap or duplicate session actions.

## Check contract

Checks are read-only. Opening Health refreshes a missing or older-than-five-
minutes result once; no background timer polls the system. **Run checks** is
the explicit refresh action. A result has a stable identifier, group, label,
status, value, bounded detail, affected component, owner attribution, sanitized
source path, and an optional next action.
Check status is one of `ok`, `warning`, `error`, or `info`; report state is
`healthy`, `warning`, or `error`. The UI adds transient `checking` and initial
`not checked` states.

The local run covers:

- configured and actually running bar;
- bar form, position, and detected outputs;
- the single production Quickshell instance invariant, matched by the exact
  config path from Quickshell's instance registry and verified through IPC;
- managed plugin roots, ownership markers, payload digests, registry discovery,
  and enabled state;
- incomplete or failed continuity transactions;
- configuration/schema readability;
- bounded QML loader, type, reference, binding-loop, assignment (including
  `Unable to assign … to QColor`), and provider compatibility failures since
  the current configuration was loaded;
- visible runtime warnings from the same on-demand production-process log
  sample, grouped by verified owner rather than assumed to be Shibumi;
- for a source install: branch, commit, upstream, dirty state, and cached
  ahead/behind state;
- for a package install: local Pacman version, staged Shibumi payload version,
  and package ownership;
- Shibumi, Omarchy, and Quickshell versions.

For the Shibumi bar, the form comes from `presentation.shellStyle` in the
unique canonical `hancore.shibumi.state` service entry under `plugins[]`. It
never comes from `bar.style`. Current installs whose metadata requires State
entry storage report a missing, duplicate, layout-placed, or malformed entry as
an invalid configuration and leave the form unknown instead of assuming V1.
A valid pre-migration install remains reportable from its retired bar-local
settings, but any present canonical State data takes precedence and malformed
canonical data never falls back to the retired location.

The page shows every warning or error, including its bounded evidence and next
step. Runtime warning rows state the number of matches and lines in the sampled
scope. Health selects the exact production config from one `qs list` result and
caches that instance ID for the rest of the check. It does not invoke `qs log`.
Instead, it reads the selected instance's Quickshell text log directly from
`$XDG_RUNTIME_DIR/quickshell/by-id/<instance-id>/log.log` without adding a
process, poller, timer, or background sampler. The ID accepts only a bounded
ASCII filename form. Every directory component is opened without following
symbolic links, the runtime root must belong to the current user, and the final
nonblocking descriptor must be a regular file owned by that user.

The file size captured immediately after opening bounds the read and prevents
later growth from extending it. Logs up to and including 8 MiB are read in
bounded chunks. For a larger log, Health reads at most the final 1 MiB and drops
the first, potentially partial line before applying the existing 400-line
sample bound. Bytes that are not valid UTF-8 are replaced rather than causing
an unbounded fallback. Because this tail can omit earlier records, Health does
not extrapolate a since-boot or hourly warning rate unless a complete timed
observation window is actually established. The current query does not
establish one, so the rate is reported as unavailable. A missing, malformed,
symlinked, non-regular, foreign-owned, failed, or ambiguous production-process
or log selection is **Log unavailable**, never a clean zero. In the healthy
state only the active bar, installed Shibumi components, and recent runtime
errors remain as quiet icon-and-text rows. Other successful implementation
checks stay hidden: they provide no user action and surface automatically if
their state becomes abnormal.

### Ownership attribution

Every check carries an `owner` of `shibumi`, `omarchy`, `third-party`, or
`unknown`, plus a sanitized `sourcePath` and optional `pluginId`. Runtime log
errors and warnings are grouped by this attribution instead of being presented
as Shibumi findings. `/usr/share/omarchy/**` findings are Omarchy-owned;
installed `hancore.shibumi.*` roots are Shibumi-owned; and unrelated user plugin roots,
including OmaConnect, are third-party-owned only when the local install state
or plugin registry verifies the ID. Bare names and unverified explicit plugin
fields remain `unknown`. Competing Shibumi and non-Shibumi sources on one line
also remain `unknown`; a canonical Omarchy path with a competing local path or
explicit foreign plugin ID is likewise ambiguous. An Omarchy path may still
outvote an incidental, unanchored plugin name. Ownership must not be assigned
by guesswork.

The Control Center headline, its **HEALTH** chip, and the Health panel list only
Shibumi-attributed runtime log findings together with every non-log process,
payload, backend, and sensitive-detail check. An unreadable or ambiguous log
remains a primary **Log unavailable** warning. Error and warning checks
attributed to Omarchy, third-party code, or an unknown source are not listed in
the panel; `shibumi-health` reports them under their owner. `unknown` means that
responsibility is not established. This UI projection does not change
`report.overall`, remove checks, or alter the complete CLI/JSON report.

An expanded error exposes a stable `SHIBUMI-HEALTH/<CHECK-ID>` code and a
**Copy** action. Copy places only the bounded, sanitized code, result, owner,
version, plugin/source identity, evidence, and suggested action on the
clipboard. A Shibumi-owned error with `issueEligible: true` additionally gets
**Open issue**, which opens this repository's GitHub issue form with the same
report prefilled; it does not submit anything. Omarchy, third-party, and
unknown findings never receive a Shibumi issue action; their next step points
to the relevant owner or upstream support path. The Copy action briefly changes
to **Copied** as feedback. Warnings remain review-only and do not encourage a
bug report without evidence of an actual failure.

The collapsed report fits without a scrollbar. Expanding an Attention detail
uses the existing page scroll when the additional evidence needs more room.

A compact information band shows the installed Shibumi version and whether it
was staged from an `ARCH PACKAGE` or a `SOURCE CHECKOUT`.

**Check for updates** is a separate explicit action. It performs only a
timeout-bounded read-only query appropriate to the install origin. A checkout
uses `git fetch` for its configured upstream and never pulls, checks out,
merges, installs, or changes the working tree. A package install queries the
official AUR RPC for the published `shibumi-shell` version and never treats
`/usr/share/shibumi-shell` as Git. Before AUR publication, a successful empty
result is shown as **Not published**, not as a failure.

## Privacy and lifecycle

Diagnostic details replace the user's home with `~`, collapse and truncate
output, and reject lines containing credential, password, token, cookie, SSID,
or authorization terms. Complete logs and environment dumps are never exposed.
The long-lived owner rejects overlapping requests and delegates the hard
deadline to `timeout`, which terminates and then kills an unresponsive child.

## Verification baseline

The automated acceptance matrix covers healthy and dirty checkouts plus local
fixtures for ahead, behind, diverged, missing-upstream, offline, and hard-fetch-
timeout states. It also covers matching, unstaged, missing, unpublished,
update-available, and offline package states. Remote refresh is asserted to
leave `HEAD` unchanged. Malformed reports must preserve the last valid result.

The Control Center smoke test starts a deliberately slow report, navigates away,
closes and reopens the panel while it is running, and confirms that the same
long-lived owner delivers the completed report. A second request is rejected
while the first is active. Deferred Configure navigation is owned by a QML
`Timer`, so destroying the panel cancels the pending callback instead of
evaluating it in an invalid context.

Physical mixed-scale multi-monitor behavior remains a hardware acceptance gate;
the offscreen lifecycle test does not claim to replace it.
