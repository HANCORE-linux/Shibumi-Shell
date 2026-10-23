# Shibumi host compatibility record

Status: revision-bound host compatibility reference

Shibumi Shell is built exclusively for Omarchy Quattro. This record ties
Shibumi's host contracts to exact baselines. Unlisted versions are not covered
by this evidence.

## Current pinned host

Beta.16.5.1 pins the exact official Omarchy 4.0.6 validation baseline. These pins are not
physical release acceptance. The historical Beta.13 physical host acceptance
below applies to its recorded single-output Omarchy 4.0.3 setup:

| Component | Observed value |
| --- | --- |
| Pinned Omarchy package reference | `omarchy 4.0.6-1`, `omarchy-settings 4.0.6-1` |
| Pinned official Omarchy source tag | `v4.0.6` (`237f1b4071a0bff2296c6d740ba2b9fd695ebfa0`) |
| Pinned source-parity revision | `237f1b4071a0bff2296c6d740ba2b9fd695ebfa0` |
| Native catalog source-only reference | `v4.0.4` (`c668141e9c42b13c80c9ca4ea108e11708c5e8a5`, 183 shell files) |
| Immutable Agents reference | `v4.0.0` (`f0020448ca87329199de7cb12f2015ebc4a3e5e7`) |
| Immutable forward-compatibility revision | `246f33a2fef66411c990860d88e0823ae83987fc` |
| Quickshell package | `quickshell 0.3.2.r7.g2b4501a-1` |
| Recorded Beta.13 physical validation date (4.0.3) | 2026-09-13 |

The installed package is the primary host-build identity. The new complete
source-parity checkout is pinned to the official `v4.0.6` tag. The 4.0.4, 4.0.3 and
4.0.2 package/source manifests and 4.0.5 source manifest remain immutable history. The older Agents-only gate remains explicitly pinned to `v4.0.0`;
the separate
`246f33a2` snapshot supersedes `4c1b4cb3` as the bounded forward reference;
all earlier manifests remain unchanged.
Historical focused forward checks do not establish a new-stack candidate pass;
complete candidate gates must be recorded separately. No pin follows a moving branch.

The package-managed baseline records these authoritative production anchors:

| Contract-sensitive file | SHA-256 |
| --- | --- |
| `shell/services/PluginRegistry.qml` | `8466127c53037b80b582544610b0bdf78a86764e4f037a3b9ce360d107359803` |
| `shell/shell.qml` | `1c390bb1703a8372a7d3a614bc44513b6cc91eee21f4bd507198e8601310e617` |
| `shell/Ui/KeyboardPanel.qml` | `c8b3b0fd52d8a79469675e925ff851e1dd0588eb1eeb90bd4df004a4c7d72a0a` |
| `shell/plugins/bar/Bar.qml` | `a8f27b3d8f29f8b8c14a5e578ad0617e6035375ccab0178a28c435e80a2822f0` |
| `shell/plugins/bar/BarModel.js` | `908f30edce60dcba46d2039ba3d501fd0faa35fa1f90b7dbda69439288f8a8d0` |

The table is a human-readable set of important anchors, not the complete
machine identity. Three separate manifests bind every file or symlink below the
consumed `shell`, `bin`, and `config` subtrees without conflating their claims:

- [`omarchy-installed-package-v4.0.6.json`](../../contracts/baselines/omarchy-installed-package-v4.0.6.json)
  records the package-managed `omarchy 4.0.6-1` and
  `omarchy-settings 4.0.6-1` layout;
- [`omarchy-installed-source-parity-v4.0.6.json`](../../contracts/baselines/omarchy-installed-source-parity-v4.0.6.json)
  records the full Git checkout of the official `v4.0.6` source tag;
- the immutable 4.0.3 package/source manifests retain the previous physical
  acceptance baseline without claiming that acceptance for 4.0.6;
- [`omarchy-forward-compat-246f33a2.json`](../../contracts/baselines/omarchy-forward-compat-246f33a2.json)
  records the immutable forward-compatibility snapshot at the recorded upstream
  revision. It does not follow the moving remote branch.

`tests/lib/baselines.sh` validates subtree counts, all path inventories,
directory, regular-file, and symlink structure, executable state, declared
package-link targets, and file contents before a host-bound test uses them.
Empty directories are bound; FIFOs, sockets, devices, and other unsupported
node types are rejected. `shell` and `config` reject payload symlinks; the
package-managed `bin` subtree binds every absolute link target. A relocated
tree is accepted only through its matching installed-package,
installed-source-parity, or forward-compat job; callers cannot supply their own
manifest.

## Six native sections, three presentation regions

At `246f33a2fef66411c990860d88e0823ae83987fc`, native layout coordinates are
`left`, `centerBegin`, `center`, `centerEnd`, `right`, and `tray`. Identity,
conflicts, snapshots, State shadow checks, lifecycle persistence and native
inline deltas cover all six. Missing extension arrays are valid legacy input;
present malformed arrays are refused. Suite normalization preserves extensions
on 4.0.4 instead of relying on its three-section `Util.normalizeLayout()`.
V1/V2 group orders, capacities and presentation regions remain left/center/right.

The visible center is a projection of `centerBegin + center + centerEnd`.
Complete native entries, their order, section/index and duplicate instances stay
in native storage; there is no flattened-layout write-back. A native section
move takes the structural reconciliation path even if the projected order is
unchanged. Shape-stable unique-provider inline changes use native coordinates;
ambiguous duplicate-ID changes use structural reconciliation, never an ID-only
in-place patch. Group-slot settings remain separate from native provider entries.

The three-region V2 editor preserves a center entry's native section when it
stays in the center. Reordering within one native section is reversible; a swap
across the invisible native center-section boundaries is refused atomically.
An explicit move between outer and center presentation regions uses the host's
native default target. V1 group order remains presentation-only. To deliberately
change centerBegin/center/centerEnd membership, edit the native layout explicitly;
Shibumi does not infer such a move from flattened drag order. Legacy centerAnchor
handling requires an already-present anchor and no split-center keys; no new
anchor field is introduced.

Catalog transport retains the six-name native manifest declaration, separately
from the consumer's presentation-region mapping; unknown names are refused.
`HostContract.nativeDefaultSection` resolves placement using the host's public
`Util.barSections` contract: missing/default `center` becomes `centerEnd` on the
six-section host, and remains `center` on 4.0.4. This is not inferred from the
user's layout. Standalone hosted widgets receive optional `fixedEdge` before
`bar`, reactively from their actual suite anchoring. The hidden Status tray
backend and shared embedding allowlist are unchanged.

### Deferred tray-drawer widgets

`bar.layout.tray` entries remain intact across switching, keep-settings,
uninstall and reinstall, and participate in identity/conflict checks. They are
not group providers or visible extras, are not relocated by catalog or automatic
family reconciliation, and are not instantiated in a custom Shibumi drawer.
The hidden native tray backend does not acquire a native drawer section host.
The Control Center health warning and one admitted-Bar journal notice explain:

> Tray-drawer bar widgets are preserved but not shown by Shibumi. Open Control
> Center > Bars and switch to Omarchy (stock bar) to use them.

This limitation does not change Shibumi's existing application-tray views. The
forward geometry fixture did not reproduce a clipping-forwarding failure; the
shared panel click-forwarding implementation remains unchanged.

### Quickshell provenance and evidence limits

The active package/parity/forward manifests record Omarchy-repository
`quickshell 0.3.2.r7.g2b4501a-1`, binary revision
`2b4501a282689792b62e94f3fb30d8f512324fe6`. Historical Arch `0.3.1-1`
validation is not relabeled. The upstream install list names unversioned
`quickshell`; migration `1787399318` is historical context, not current package
provenance. A reported edge host uses `0.3.2-6`; no result here establishes
that package's live acceptance. Source contracts and isolated component fixtures do not establish
real stock-bar switching, physical output behavior or desktop acceptance on it.

## What Shibumi validates

The Quattro source contract binds `SuiteRuntime.HostContract` as one layer for its first-party IDs, IPC targets and host marker/theme paths; it adds no host authority or runtime version discovery.

Before mutating user state, the Shibumi lifecycle verifies the Quattro APIs
used by its own 24-plugin suite: plugin validation and discovery, bar selection
and configuration, plugin-registry injection, and the shared keyboard-panel
border contract. A missing contract stops install, update, or repair with an
explicit incompatibility error.

An Omarchy update is accepted only after these areas have been reviewed:

1. plugin discovery, validation, enablement, rescan, and entry-point loading;
2. full-bar selection, layout normalization, widget injection, and panel
   routing;
3. stock-bar reset and recovery behavior;
4. keyboard-panel border and surface integration;
5. the complete source contract suite and live lifecycle/switch
   matrix.

Run the repository contract suite separately against all four host proof gates:

```bash
./tests/omarchy-installed-package-contract-regression.sh
SHIBUMI_INSTALLED_SOURCE_OMARCHY_PATH=/path/to/omarchy-v4.0.6 \
  ./tests/omarchy-installed-source-parity-contract-regression.sh
SHIBUMI_AGENTS_OMARCHY_PATH=/path/to/omarchy-v4.0.0 \
  ./tests/omarchy-agents-contract-regression.sh
SHIBUMI_FORWARD_COMPAT_OMARCHY_PATH=/path/to/omarchy-forward-compat-246f33a2 \
  ./tests/omarchy-forward-compat-contract-regression.sh
```

The 4.0.6 manifests record exact observed bytes and package provenance; it
does not by itself establish live acceptance. If any recorded host file changes,
Shibumi remains on the previous accepted baseline until the affected contracts
and live workflows pass again.

A complete aggregate run ends with `Shibumi complete contract regression
passed` and names the accepted baseline and full source revision. Absence of
that marker is not complete-contract evidence.

## Historical Omarchy 4.0.3 source evidence

The Beta.13 candidate targeted the exact `v4.0.3` host at commit
`0534987009061cbe2dacdde4ad564092ab698d12`. Isolated tests cover own-file marker
validation, permission-scoped State writes and readback under stock and suite
bars, Control Center restoration through file-backed settlement, and the
monitor's scalar-Bar bridge. They also exercise the PID-bound native catalog,
independent Bar and page consumers, selected-provider changes and exact V1/V2
undo, stale-snapshot refusal, and all 24 plugin roots with the exact 18 scoped
service owners. It also proves the one-shot exact-PID public registry prime:
the pre-prime Bar remains unavailable, a replacement Bar is required, and a
missing replacement fails bounded and without retry. This works around the
pinned host's first-mutation loss without retaining a revoked Component or
patching Omarchy. The all-suite test withholds platform owners and creates no
output surfaces.

These source and fixture results establish the exact 4.0.3 contract but do not
transfer physical acceptance to later Shibumi releases. The public widget snapshot is not a global
manifest or service registry; denied or missing capabilities must not be
replaced by private host traversal, a guessed original provider, undeclared
sibling imports, duplicate backends, or authentication access. Physical
acceptance is separate: package-bound lifecycle and recovery, a coredump-free
production restart, complete notification and idle/lock behavior, output
lifetime, hardware-adjacent actions, and Top/Bottom checks must be recorded for
the exact host. The historical setup had only one output, so it provides no
multi-output acceptance; 4.0.2 compatibility evidence cannot replace a 4.0.3 gate.

## Recovery boundary

Shibumi does not replace Omarchy's stock recovery path. The lifecycle
uninstaller restores the previous bar state transactionally; the native
fallback remains:

```bash
omarchy bar reset
```
