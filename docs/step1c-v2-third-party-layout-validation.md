# Step 1C V2 third-party layout validation

Status: implementation validation on the Step 1C worktree. This is not live
acceptance and does not replace the physical multi-output gate.

## PR #28 assessment

PR #28 was not cherry-picked, merged, or otherwise used. Its one commit was
open and had no recorded CI checks or review decision when inspected.

Its narrow guard is directionally valid for one defect: the V2 provider path
could invoke V1-only reconciliation. A temporary isolated Quickshell harness
against the Step 1C baseline recorded:

```text
unguarded-v2-reconcile: writes=1 v1DynamicIndex=7 v2DynamicLocation=null v2LayoutUnchanged=true
guarded-v2-reconcile: writes=1 v1StateUnchanged=true
v1-reconcile-evidence: PASS
```

This proves an unintended V1 state write while V2 is active. It does **not**
prove that the current `v2Layout` is directly overwritten: the same harness
showed the V2 layout unchanged. The PR therefore does not cover the complete
Step 1C behavior, and its timer/startup path would remain incomplete if only
its three transactional call sites were guarded.

## Step 1C implementation evidence

The worktree now keeps V2 dynamic third-party groups in the V2 layout model,
uses the existing provider-neutral drag controller, synchronizes the shared
host `bar.layout` on cross-region and same-region moves, and leaves V1
reconciliation isolated to V1. Generic fixtures cover activation, requested
region changes, same-region reorder, cross-region movement, removal, settings
entry preservation, and all four V2 styles (`full`, `fit`, `dock`, `notch`).

Validated against the pinned installed-source Omarchy baseline
`f0020448ca87329199de7cb12f2015ebc4a3e5e7` (`v4.0.0`):

- `./tests/bar-host-registry-regression.sh` — passed
- `./tests/state-service-regression.sh` — passed
- `./tests/control-center-regression.sh` — passed
- `QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input tests/shibumi-config-regression.qml` — passed
- `tests/layout-model-regression.qml` and `tests/layout-controller-regression.qml` — passed
- full pinned `./tests/contract-regression.sh` — passed, including 24 plugins
- `./scripts/sync-bar-host.sh --check` and `./scripts/sync-shared.sh --check` — passed
- `git diff --check` — passed

No physical multi-monitor, hardware, top/bottom live, or visual-freeze
acceptance is claimed by these fixture and offscreen results. Those remain
explicit approval gates before Step 1C completion.

## Controlled live run

A controlled live run was performed on 2026-08-20 against the active Wayland
session (`Omarchy 4.0.0-1`, Hyprland 0.56.2, Quickshell 0.3.0). The private
worktree payload was staged only into the two affected user plugin directories;
`/usr/share/omarchy` was not modified.

Passed:

- cold shell restart with exactly one production Quickshell process and a
  successful `omarchy-shell shell ping`
- real third-party `hancore.omaq` activation through the Shibumi suite IPC;
  `G:hancore.omaq` was persisted in V2 and the host entry retained
  `shibumiModule: true`
- real third-party `hancore.bongocat` activation and removal, with the same
  V2 dynamic-group lifecycle
- moving OmaQ from right to left through the host bar command; the persisted
  V2 group followed to left without changing the fixed V1 groups
- a subsequent user-visible V2 Edit Layout drag moved OmaQ to the left section;
  after a cold shell restart the host entry and `G:hancore.omaq` remained in
  the left section at the persisted positions
- cold style matrix for `full`, `fit`, `dock`, and `notch`, with the dynamic
  group retained and one Quickshell process in every case
- V1 `shibumi` cold load and return to V2 `notch`; the fixed V1 order remained
  unchanged and the dynamic V2 group survived the switch
- live top and bottom position captures, removal rollback, and final shell
  restart

The original `shell.json` SHA-256
`5c304a1c7d46b460bef77e1d419996cd20b09f09e481123cc35c55a45c9ca429` was restored
byte-for-byte. The original Shibumi bar and state payload hashes were also
restored, optional third-party plugins were disabled, and the final shell had
one production process. Captures and raw logs remain outside the repository at
`/tmp/shibumi-step1c-live-20260820150247/`.

An initial attempt used the generic `omarchy plugin enable` command and was
abandoned after a rescan produced unrelated provider substitutions. It is not
counted as acceptance evidence; the controlled run used the Shibumi suite IPC.
The final interactive drag was performed by the user after unlocking the
session and completed with one Quickshell process and successful ping after
restart.

After the live run, startup injection and rollback guards were hardened without
changing the exercised valid-provider path. The pinned complete contract suite
was rerun successfully on the final diff.

This run exercised one physical output only. The user subsequently exercised a
monitor-scale change on that output and reported that the shell remained
functional. This is recorded only as a single-output scale check; physical
multi-output, mixed-scale, hardware, and any visual-freeze comparison remain
open gates.
