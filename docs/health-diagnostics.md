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
status, value, bounded detail, affected component, and an optional next action.
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
- bounded QML loader, type, reference, binding-loop, and provider compatibility
  failures since the current configuration was loaded;
- for a source install: branch, commit, upstream, dirty state, and cached
  ahead/behind state;
- for a package install: local Pacman version, staged Shibumi payload version,
  and package ownership;
- Shibumi, Omarchy, and Quickshell versions.

The page shows every warning or error, including its bounded evidence and next
step. In the healthy state only the active bar, installed Shibumi components,
and recent runtime errors remain as quiet icon-and-text rows. Other successful
implementation checks stay hidden: they provide no user action and surface
automatically if their state becomes abnormal.

An expanded error exposes a stable `SHIBUMI-HEALTH/<CHECK-ID>` code and two
explicit actions. **Copy** places the bounded code, result, version,
component, evidence, and suggested action on the clipboard. **Open issue**
opens this repository's GitHub issue form with the same report prefilled; it
does not submit anything. The Copy action briefly changes to **Copied** as
feedback. Warnings remain review-only and do not encourage a
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
