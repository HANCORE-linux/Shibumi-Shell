# Additional Shibumi bars

> **Document status: Normative supporting contract.** This document defines
> the supported way to add selectable Shibumi bar hosts. It is subordinate to
> [`../ARCHITECTURE.md`](../ARCHITECTURE.md).

## Verified Quattro capability

This contract was tested against the validation system's Omarchy Quattro commit
`1b6ab15331bfc88eb66746021d9e32c976ed438a` and package
`4.0.0.r1242.g1b6ab15-1` on 2026-07-23. the validation system matches the protected online
`quattro` head checked that day. The plugin registry, installer, manifest,
selector, and bar-loader contract remain compatible.

Quattro supports third-party full-bar plugins directly:

- each bar is one plugin directory under
  `~/.config/omarchy/plugins/<plugin-id>/`;
- its root `manifest.json` uses `schemaVersion: 1`, includes a stable unique
  ID, declares `kinds: ["bar"]`, and maps `entryPoints.bar` to a safe relative
  QML file;
- `omarchy bar use <plugin-id>` stores the selected ID in `bar.id`;
- exactly one bar option is active at a time;
- the host injects `omarchyPath`, `shell`, `manifest`, `barWidgetRegistry`,
  `pluginRegistry`, and `barConfig` when those properties exist; and
- a missing, invalid, or failed third-party bar falls back to `omarchy.bar`.

The official `omarchy plugin add <git-url>` flow currently clones one Git
repository, validates one manifest at its root, and installs that one plugin.
Plugin discovery scans one directory level below the user plugin directory.
It does not discover 22 nested plugin roots from the Shibumi monorepository.
Therefore:

- a standalone repository containing one Shibumi bar could use the native
  installer directly;
- this multi-plugin Shibumi repository cannot be installed as one native
  plugin; and
- the Shibumi suite adapter remains responsible for transactional installation
  of all selected child plugins until Quattro documents a multi-plugin source
  contract.

Primary source locations at the checked online head are
[`bin/omarchy-plugin-add`](https://github.com/basecamp/omarchy/blob/f54edbe/bin/omarchy-plugin-add),
[`bin/omarchy-bar`](https://github.com/basecamp/omarchy/blob/1b6ab15331bfc88eb66746021d9e32c976ed438a/bin/omarchy-bar),
[`PluginRegistry.qml`](https://github.com/basecamp/omarchy/blob/1b6ab15331bfc88eb66746021d9e32c976ed438a/shell/services/PluginRegistry.qml),
and
[`shell.qml`](https://github.com/basecamp/omarchy/blob/1b6ab15331bfc88eb66746021d9e32c976ed438a/shell/shell.qml).

## Product boundary

An additional Shibumi bar is a different composition or visual language, not a
fork of the desktop backend. It may own:

- its layer windows and per-output geometry;
- layout composition, responsive policy, split chrome, drag targets, and
  bar-specific motion;
- its implementation of host facade version 1; and
- bar-specific presentation settings that do not change feature meaning.

It must reuse the existing Shibumi owners for widgets, panels, menus, state,
telemetry, actions, scanners, caches, and external processes. It must not
create a second tray, notification owner, network scanner, MPRIS selector,
telemetry sampler, picker scanner, or equivalent service merely because the
bar looks different.

One active bar means one active set of bar windows. Process-wide feature
services remain one instance and survive a bar switch through Quattro's plugin
registry and the Shibumi service contracts.

## Identity and directory contract

Use stable semantic IDs and names. Do not encode order, an experiment number,
or predecessor branding in the public ID.

```text
hancore.shibumi.bar                 default approved bar
hancore.shibumi.bar.<semantic-name> future bar
```

Each future directory must be a self-contained plugin root:

```text
hancore.shibumi.bar.<semantic-name>/
├── manifest.json
├── Bar.qml
├── core/
└── styles/
```

A minimal manifest shape is:

```json
{
  "schemaVersion": 1,
  "id": "hancore.shibumi.bar.<semantic-name>",
  "name": "Shibumi <Display Name>",
  "version": "1.0.0",
  "author": "hancore",
  "description": "A selectable Shibumi bar host",
  "kinds": ["bar"],
  "entryPoints": { "bar": "Bar.qml" }
}
```

The plugin may contain reviewed vendored host code from canonical development
sources, but it may not import a sibling plugin or the repository root at
runtime. No plugin payload may contain a symlink.

## Shared host facade and state

Every bar implements [`host-facade-v1.md`](host-facade-v1.md) and exposes
`shibumiHostContractVersion == 1`. Feature plugins bind only to that facade and
standard Quattro contracts, never to a concrete bar directory.

Shared feature state remains under `bar.shibumi`. A bar switch must preserve:

- G1-G15 enablement, compact settings, order, and feature preferences;
- menu, picker, workspace, Reactor, and panel state contracts; and
- user entries outside the Shibumi-managed layout.

A variant-only option may use a namespaced `bar.shibumi.bars.<bar-id>` object
only when it has no meaning to another host. It must not copy the complete
feature configuration. Schema normalization must bound and preserve such data
when the corresponding bar is inactive.

## Registration in the suite

Adding a bar requires one deliberate contract change rather than dropping a
directory into the tree:

1. Add the child plugin to `contracts/plugin-suite-v1.json` with `kind: bar`,
   its bundle/profile availability, and stability metadata.
2. Keep `hancore.shibumi.bar` as the default active bar unless a separate
   product decision changes the default.
3. Extend the suite model so a supported profile or explicit `--bar` choice
   selects only a declared bar ID. Do not infer an active bar from directory
   order.
4. Stage and validate the new bar in the same transaction as its required
   feature plugins.
5. Preserve installed inactive bars during activation and update; only
   `bar.id` changes when switching.
6. On removal of the active optional bar, select the default Shibumi bar if it
   is installed, otherwise reset to `omarchy.bar`, before deleting payloads.

The first implementation should add an explicit suite command such as
`shibumi-suite bar use <declared-id>` that validates installation and delegates
the final selection to `omarchy bar use`. Direct `omarchy bar use <id>` remains
supported because it is the native Quattro control plane.

## Implementation sequence

### 1. Freeze the default bar

Do not build the second bar until the default bar's non-deferrable V1 parity
and lifecycle gates pass. Freeze the host-facade fixtures and record the exact
reference revision.

### 2. Extract canonical host-core sources

Identify only genuinely shared host mechanics: output filtering, host facade,
panel/tooltip routing, click targets, layout mutation requests, and service
lookup. Keep style composition and variant motion outside that core. Continue
vendoring reviewed copies into each independently installable bar plugin and
prove them with the deterministic shared-source check.

### 3. Scaffold one semantic proof bar

Choose and approve a product name before creating its public ID. Its initial
scope should be visually distinct but functionally complete enough to render
the same registered G1-G15 plugins. It must not introduce a new feature owner.

### 4. Add lifecycle controls

Extend contract parsing, dry-run output, activation drift, install state, update
rollback, and uninstall selection rules for more than one declared bar. A
failed optional bar update must restore the prior payload and `bar.id` as one
transaction.

### 5. Accept on the internal validation system

All runtime execution occurs on the validation system under the installed Quattro session.
The source V1 repository remains read-only.

## Required gates for every bar

- official manifest validation and repository self-containment;
- construction without `required` host-injected properties;
- host-facade version and callable surface parity;
- one window per real output, with placeholder outputs rejected;
- Top and Bottom geometry, tooltip, panel, and outside-dismiss routing;
- G1-G15 registry resolution and user-extra preservation;
- switching default → new → default without duplicate services, panels,
  processes, timers, or persistent feature-state changes;
- missing entry point and intentional QML load failure both falling back to
  `omarchy.bar` without a crash loop;
- update rollback restoring payload, `shell.json`, active bar, and install
  state;
- removal while active selecting a surviving supported bar before deletion;
- idle CPU, repeated proportional set size, child-process count, and panel
  worker cleanup at least as good as the accepted default bar; and
- visual review at the same theme, scale, content, and state declared by that
  bar's presentation contract.

No additional bar is release-supported merely because Quattro discovers its
manifest. Registration, ownership, switching, recovery, and the complete
the validation system gate are one feature.
