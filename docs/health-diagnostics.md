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
- the single production Quickshell process invariant;
- managed plugin roots, ownership markers, payload digests, registry discovery,
  and enabled state;
- incomplete or failed continuity transactions;
- configuration/schema readability;
- bounded QML loader, type, reference, binding-loop, and provider compatibility
  failures since the current configuration was loaded;
- source branch, commit, upstream, dirty state, and cached ahead/behind state;
- Shibumi, Omarchy, and Quickshell versions.

The page shows every warning or error, including its bounded evidence and next
step. In the healthy state only the active bar, installed Shibumi components,
and recent runtime errors remain as quiet icon-and-text rows. Other successful
implementation checks stay hidden: they provide no user action and surface
automatically if their state becomes abnormal.

An expanded error exposes a stable `SHIBUMI-HEALTH/<CHECK-ID>` code and two
explicit actions. **Copy report** places the bounded code, result, version,
component, evidence, and suggested action on the clipboard. **Open issue**
opens this repository's GitHub issue form with the same report prefilled; it
does not submit anything. Warnings remain review-only and do not encourage a
bug report without evidence of an actual failure.

A compact information band shows the installed Shibumi version and its current
local-suite origin. The origin slot is intentionally stable so a later package
or AUR channel can replace it without changing the Health layout.

**Check for updates** is a separate explicit action. It performs only a
timeout-bounded `git fetch` of the configured upstream and never pulls,
checks out, merges, installs, or changes the working tree. A private remote
without Machine2 credentials is reported as a check failure rather than as
current or offline.

## Privacy and lifecycle

Diagnostic details replace the user's home with `~`, collapse and truncate
output, and reject lines containing credential, password, token, cookie, SSID,
or authorization terms. Complete logs and environment dumps are never exposed.
The long-lived owner rejects overlapping requests and delegates the hard
deadline to `timeout`, which terminates and then kills an unresponsive child.
