# Shibumi plugin suite migration plan

> **Document status: Normative supporting contract.** Plugin boundaries,
> repository layout, and transactional bundle lifecycle remain binding. Phase
> completion status is maintained in `release-readiness.md`.

## Decision

Shibumi is one repository containing a suite of independently
registered Omarchy plugins. The repository is not one combined
`bar`/`bar-widget`/`service` plugin.

This boundary is required for three product goals:

1. the Shibumi Control Center, widgets, and system surfaces can be
   enabled and updated as explicit plugin units;
2. the approved V1-style bar remains one selectable full-bar host; and
3. future Shibumi bar variants can reuse the same widgets and services without
   copying their implementations.

The repository root has no installable `manifest.json`. The retired combined
prototype and its application-menu declaration have been removed. The
historical extraction ledger in `plugin-suite-inventory.md` explains file
provenance but is not normative for the current tree.

## Verified Host Constraint

the validation system's Omarchy Quattro package `4.0.0.r1458.gfa6b5fc-1` implements
`omarchy plugin add` as a one-Git-repository-to-one-plugin operation. The
command clones a repository and validates `manifest.json` at its root. It does
not install a repository containing several top-level plugin manifests.
The contract was rechecked on 2026-07-30. Its new setup menu also enables,
disables, or removes one root at a time, so it retains the same suite
constraint.

Lacuna and Whiterose demonstrate the desired plugin-suite source layout, but
they use repository-owned installation logic to stage multiple plugin
directories. Shibumi therefore needs the same explicit bundle boundary until
Omarchy provides a native multi-plugin source command on the supported release.

Consequences:

- every runtime plugin is a self-contained top-level directory;
- the repository installer validates and stages the selected plugin set;
- Omarchy Shell still owns discovery, enablement, bar selection, and runtime
  lifecycle after staging;
- the installer must not patch `/usr/share/omarchy` or `/usr/bin`;
- a future native Omarchy repository-source feature may replace the staging
  implementation without changing plugin IDs or runtime boundaries.

## Target Repository Layout

```text
shibumi/
  hancore.shibumi.bar/
    manifest.json
    Bar.qml
  hancore.shibumi.control-center/
    manifest.json
  hancore.shibumi.<feature>/
    manifest.json
    <self-contained payload>
  contracts/plugin-suite-v1.json
  shared/
  scripts/
  tests/
```

`contracts/plugin-suite-v1.json` is the executable list of all 24 plugin roots,
their kinds, ownership roles, dependencies, and the default profile. A runtime
plugin is valid only when its complete implementation and owner live inside its
own directory.

## Plugin Boundary Rules

- A user-selectable bar, widget, panel surface, overlay, or reusable
  singleton service is a plugin boundary.
- A widget and its directly attached panel normally remain one plugin. It may
  declare both `bar-widget` and `service` when the state owner belongs to the
  same feature.
- Delegates, visual primitives, parsers, and style tokens are not standalone
  plugins.
- `hancore.shibumi.bar` owns output windows, groups, split state, drag-and-drop,
  top/bottom geometry, and the host facade. It does not own feature data.
- `hancore.shibumi.control-center` owns the reusable G1 widget and Shibumi bar
  configuration panel. Omarchy exclusively owns the application menu.
- Notification and OSD replacements remain separate plugins and may activate
  only when duplicate first-party ownership is prevented.
- Every plugin must remain self-contained at runtime. It may not import QML
  from a sibling plugin or the repository root.

## Shared Code Contract

`shared/` is the canonical development source for host-neutral helpers,
contracts, and generated assets. Runtime plugins receive reviewed vendored
copies under their own directories.

A deterministic sync tool and regression test must prove that vendored files
match the canonical source. This avoids sibling imports that work in a source
checkout but fail after an individual plugin is installed.

Shared state is not a reason to create a global V1-style object. Reusable live
state belongs in a narrow service plugin, such as `hancore.shibumi.state`, and
is consumed through the Omarchy service contract.

## Multi-Bar Host Contract

Every Shibumi bar variant is a separate plugin with `kinds: ["bar"]`. Use
stable semantic IDs rather than numeric implementation names:

```text
hancore.shibumi.bar
hancore.shibumi.bar.minimal
hancore.shibumi.bar.<future-name>
```

All variants must implement the same versioned host facade for widgets:

- target output and anchor resolution;
- top/bottom position and orientation;
- panel and tooltip routing;
- interaction ownership;
- group/split layout access;
- drag-and-drop mutation requests;
- Shibumi visual tokens and font access; and
- host-owned configuration mutation.

Widgets may consume this facade and standard `qs.Commons`/`qs.Ui` contracts,
but may not import a specific bar implementation. A new bar variant may change
composition and presentation; it may not fork widget state, panels, scanners,
or platform actions.

## Bundle Installation And Update

The repository-owned installer must be explicit, transactional, and
reversible:

1. select the full Shibumi profile or an intentional supported subset;
2. validate every selected plugin with `omarchy plugin validate`;
3. resolve Shibumi companion requirements before mutation;
4. stage complete plugin copies under temporary hidden paths;
5. snapshot the affected installed plugins and `shell.json`;
6. atomically expose the staged plugin set;
7. rescan, enable the required plugins, and select the requested bar;
8. request a full Quickshell configuration reload so unchanged plugin URLs do
   not retain stale cached QML components;
9. verify discovery, configured IDs, the exact payload digest, and a successful
   shell load; and
10. restore the previous batch and configuration if any gate fails.

The adapter also provides one explicit `activate` operation. It restores the
managed profile after `omarchy bar reset` or `omarchy bar defaults` without
restaging plugin payloads. The reset semantics remain those defined in
`../ARCHITECTURE.md`.

The one-time `migrate` operation accepts only an exact suite-managed QS Rise
predecessor. It moves all 22 old plugin directories and the configuration
namespace in the same transaction. A missing marker, foreign directory,
unfinished old transaction, mixed old/new settings, failed rescan, or failed
runtime verification restores the complete predecessor state.

Updates review and apply the repository revision as one release, but only copy
the installed plugin set. Uninstall removes only Shibumi-managed plugin copies
and state, restores the stock bar when necessary, rescans, and proves the
official shell still loads.

Omarchy dependency metadata is not currently enforced. Shibumi therefore
records `requires`, `recommends`, bundle membership, and stability in a
namespaced manifest metadata block and enforces it in installer tests.

The corresponding upstream host gaps, their minimum proposed contracts, and
their acceptance proofs are maintained in
[`omarchy-quattro-contract-gaps.md`](omarchy-quattro-contract-gaps.md). A gap in
that register does not permit a silent feature omission: it requires either a
bounded compatibility adapter or an explicit release gate.

## Migration Sequence

### Phase A: Freeze And Inventory

- Freeze new feature work in the combined root tree.
- Map every current file to a bar, widget, panel, service, shared helper,
  test, or obsolete transitional owner.
- Record current the validation system behavior and plugin state before moving files.

### Phase B: Contract Scaffold

- Add top-level manifests for the bar host, state service, and Control Center.
- Define and test host-facade version 1.
- Add plugin self-containment and forbidden sibling-import checks.
- Add installer dry-run, validation, dependency, and rollback fixtures.

The complete 24-plugin target set is independently loadable. Shared sources are
deterministically vendored, and the active bar satisfies host-facade V1. Every
fixed G1-G15 slot resolves a registered plugin entry point. Current completion
evidence belongs in `release-readiness.md`.

### Phase C: Core Separation

- Move the full-bar host without changing its runtime behavior.
- Keep G1 Control Center independent from Omarchy's application menu.
- Move shared configuration/state behind the narrow state service.
- Prove the current bar and Control Center load independently while Omarchy's
  menu remains functional.

### Phase D: Feature Extraction

- Migrate one complete widget slice at a time: widget, panel, service owner,
  actions, settings, and tests.
- Preserve G1-G15 placement and V1 compact/full behavior through bar layout
  configuration rather than imports back into the bar plugin.
- Keep official Omarchy backends authoritative where already approved.

### Phase E: Installer And Lifecycle Acceptance

- Fresh install, update, failed update rollback, partial profile, uninstall,
  and stock-bar recovery on the validation system.
- Verify no stale plugin directories, hidden staging paths, processes, cache
  files, or configuration IDs remain after each failure path.

The lifecycle gate requires exact Shibumi evidence for isolated failure paths
and the real the validation system runtime. Pre-rename QS Rise runs remain historical
evidence and cannot accept the Shibumi release payload.

### Phase F: V1 Product Parity

- Complete every row in the V1 parity matrix.
- Re-run top/bottom, multi-monitor, hotplug, split, drag-and-drop, picker,
  panel, CPU, PSS, and lifecycle gates against the separated suite.

### Phase G: Multi-Bar Proof

- Add a small second semantic bar variant only after the default Shibumi bar
  passes parity.
- Reuse the installed widget plugins and services unchanged.
- Prove switching bars changes only the bar host and does not duplicate
  services, panels, or persistent state.

The complete supported registration, switching, fallback, state, and
acceptance procedure is defined in
[`multi-bar-extension-plan.md`](multi-bar-extension-plan.md).

## Release Gate

The suite is not publishable until all of the following are true:

- no combined root multi-kind runtime remains;
- every installed plugin validates independently;
- every declared bar host satisfies the same host-facade contract;
- no Shibumi application-menu entry point, service, or source remains;
- installer update and rollback operate on the complete affected plugin batch;
- V1 quality, behavior, and performance gates pass on the default bar; and
- a clean uninstall restores a working stock Omarchy shell without artifacts.
