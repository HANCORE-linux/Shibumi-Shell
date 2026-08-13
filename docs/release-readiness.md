# Is Shibumi 0.1.1-beta.8 ready for prerelease testing?

> **Document status: Current validation and release gate.** This page records the latest Shibumi evidence. It cannot override [`../ARCHITECTURE.md`](../ARCHITECTURE.md).

Shibumi `0.1.1-beta.8` is an automated prerelease candidate. Its complete
contract is revision-bound across the installed-package, installed-source-parity,
and forward-compatibility proof axes. Destructive live Wayland acceptance is
retained only for the exact revisions that produced it; the release workflow
must record fresh checksummed evidence for the tagged candidate. Physical
multi-monitor, enterprise Wi-Fi, and the remaining Bluetooth workflows still
block a stable public release.

## Current test target

The current acceptance target is an internal validation system. Its hostname,
account, and network address are intentionally not part of the public product
documentation and are not required by Shibumi users.

- **Omarchy**: `4.0.0.r1664.gb99fd91-1`
- **Runtime**: `/usr/share/omarchy/shell`
- **Display**: `DP-1`, `2560x1440`, scale `1.0`
- **Candidate**: 24 plugins under `hancore.shibumi.*`
- **Policy**: Maintainers run destructive runtime acceptance only on the
  isolated validation system

The read-only V1 and V2 reference is pinned by repository revision and content
digests in
[`quickshell-dots-d0896fc-v2-deec8103.json`](../contracts/baselines/quickshell-dots-d0896fc-v2-deec8103.json);
no maintainer-local checkout path is part of the acceptance contract.

## Prerelease acceptance summary

The beta.8 source candidate plus explicitly retained prior acceptance currently
provides these results. Rows marked historical do not become beta.8 evidence
until the revision-bound release collector reruns them:

| Gate | Result |
| --- | --- |
| V1 source inventory | Passed: 72 QML and JavaScript surfaces mapped |
| Standalone V2 source inventory | Passed: 80 QML and JavaScript surfaces mapped |
| Embedded V2 differences | Passed: 26 intentional differences classified against `d0896fc` |
| Quattro compatibility | Passed against package and source-parity `b99fd91`, plus forward snapshot `d6b21f80` |
| Plugin validation and self-containment | Passed for all 24 plugins |
| Complete installed-package contract | Passed against `omarchy-dev 4.0.0.r1664.gb99fd91-1` with 214 bound shell entries |
| Complete installed-source-parity contract | Passed against immutable `b99fd91cf11db92b03bbd69e4fff908662bd74a3` |
| Complete forward-compatibility contract | Passed against immutable `d6b21f80750ccaf488373973f1ee25db21de7d26` |
| Agents integration contract | Passed against immutable `b99fd91cf11db92b03bbd69e4fff908662bd74a3` |
| Suite lifecycle unit tests | Passed: 99 of 99 |
| Control Center manager tests | Passed: 29 of 29 |
| Health tests | Passed: 31 of 31 |
| INC-013 convergence contract | Passed: 14 of 14 |
| Baseline locale matrix | Passed under C, C UTF-8, and en_US UTF-8 |
| Transactional live update | Beta.7 to beta.8 sandbox pass; exact final-commit live acceptance and clean-commit collector still required |
| Generic plugin-manager recovery | Passed: individual Bluetooth disable detected and repaired transactionally |
| Ownership repair | Passed: all 24 current markerless plugins adopted and marked |
| Bar continuity | Passed: Shibumi to Omarchy to Shibumi |
| Configuration continuity | Passed: `shell.json` returned semantically unchanged after repeated transitions |
| Runtime process count | Passed: one Quickshell process after each switch |
| Network label runtime | Passed on Ethernet and Wi-Fi across repeated V1, V2, Omarchy, and V2-return transitions |
| Current QML log | Passed: no Shibumi type, reference, loader, or binding-loop error |
| Control Center **Bars** view | Passed on the physical Wayland session |
| Bluetooth connection and panel | Passed with a live connected phone |
| Idle/screensaver panel cleanup | Passed in the bar-host regression and deployed live |
| Temperature sources | Passed: CPU and core live; absent sources disabled |
| Workspace styles | Passed: seven supported styles and geometry checks |

The hardened center smoke fails on unavailable QML types or a missing `PanelWindow` backend. The earlier WeatherPanel false pass no longer exists.

## Fixed prerelease blockers

The audit fixed these release blockers:

- Bounded V1/V2 Network labels use independent text metrics instead of a cyclic `width`/`implicitWidth` binding
- The **Bars** page can return from Omarchy to Shibumi
- Suite activation excludes stock Omarchy widgets, and the continuity manager rejects mixed-layout contamination before saving a Shibumi profile
- The continuity manager discovers the current `/usr/share/omarchy` install when `OMARCHY_PATH` is absent
- Markerless suite-owned alpha installs can update without accepting foreign plugin directories
- Temperature selection supports CPU package, hottest core, GPU, NVMe, and memory sources
- The standalone and embedded V2 workspace styles remain available, including Frame and Aurora streak
- The Shibumi Pacman style is available in both layout variants and remains
  explicitly separate from the QS Rise V2 port inventory
- The Control Center waits for all seven workspace-style controls
- V1 and V2 evidence covers every source surface instead of selected feature samples
- The center smoke rejects missing production panel types
- Bluetooth reports the live connection without presenting an untrusted phone battery value
- Active panels close before an idle or screensaver bar pre-hide can invalidate their anchor
- Standard non-Shibumi panels use one provider-neutral hosted-panel adapter;
  WireGuard proves the same V2 bar cutout and native panel-tip geometry used
  for compatible Quattro built-ins and future third-party plugins
- The Plugins page opens a direct, validation-gated Git installer and reports
  real Shibumi, Omarchy, and third-party provider counts

## Lifecycle and supply-chain boundary

Quattro validates and loads each plugin, but it doesn't update this multi-plugin repository. `shibumi-suite` owns the source update as one transaction.

The lifecycle adapter enforces these controls:

- It validates all 24 manifests with the official Omarchy validator
- It rejects symlinks, special files, unsafe entry points, foreign markers, and unknown replacement directories
- It hashes each plugin and the complete suite before activation
- It prepares and publishes recovery transactions atomically before live mutation
- It durably orders installed plugins, `shell.json`, install state, generated menu state, journals, archive copies, and cleanup
- It validates complete recovery state before changing files or stopping the shell
- It retains the recovery journal and snapshots if rollback itself fails
- It restarts for bar-owner/provider handoff and reserves hot reload for unchanged ownership
- It verifies the exact running payload after reconciliation
- It restores the previous payload and configuration after a failed gate

The theme updater disables Git hooks, executable filters, prompts, and external protocols. It applies only an unchanged reviewed commit with a fast-forward merge. The audit found no critical or high-severity security or supply-chain issue.

The V1 and V2 shell-update interface is adapted to `shibumi-suite`. The Update Center checks Arch packages and installed Git themes. It doesn't fetch a new Shibumi source revision.

## Private alpha limits

The alpha may be committed and pushed to the private repository with these limits:

- The complete visual state matrix remains partial for uncommon hover, degraded, account-backed, and device-backed states
- the validation system has no physical second display for mixed-scale, hotplug, or unplug-during-drag acceptance
- No enterprise Wi-Fi credentials were supplied for a real authentication test
- A live Bluetooth phone connection and panel pass; pairing, audio routing,
  disconnect, and forget still need complete physical acceptance
- A Shibumi update starts from a trusted repository checkout

Fixtures cover unavailable and error behavior, but they don't replace the physical gates.
The predecessor's multi-monitor and mixed-scale implementation is mapped into
the Shibumi source and automated contracts, but inherited behavior does not
replace a physical Shibumi run on the target Quattro release.

## Public release blockers

Before making the repository public:

1. Complete the remaining rows in [`../contracts/v1-state-matrix.json`](../contracts/v1-state-matrix.json)
2. Test a physical second display, mixed scale, hotplug, and unplug during drag
3. Test a real enterprise Wi-Fi authentication failure and reconnect
4. Test Bluetooth pairing, audio routing, disconnect, and forget
5. Repeat the complete validation contract on the exact public-release commit

## Release evidence

`scripts/collect-release-evidence` runs the manager, suite, health, package,
INC-013, mutation, dry-run, three complete host-contract jobs, and isolated
Quattro runtime gate. It records the exact candidate identity, commands, exit
codes, host versions, baseline identities, bounded log paths, and SHA-256 log
digests. The tag workflow runs this collector on the isolated validation runner
before publication and publishes both the manifest and its log bundle. Missing
baseline paths, failed commands, or a non-clean tagged candidate fail closed.

The detailed contracts and historical measurements remain available in:

- [`v1-parity-matrix.md`](v1-parity-matrix.md)
- [`v1-widget-parity-audit.md`](v1-widget-parity-audit.md)
- [`current-v1-discrepancy-audit.md`](current-v1-discrepancy-audit.md)
- [`qs-rise-predecessor-release-evidence.md`](qs-rise-predecessor-release-evidence.md)
- [`omarchy-quattro-contract-gaps.md`](omarchy-quattro-contract-gaps.md)
