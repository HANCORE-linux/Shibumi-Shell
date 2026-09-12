# Shibumi host compatibility record

Status: beta-candidate reference (updated 2026-09-12)

Shibumi Shell is built exclusively for Omarchy Quattro. This record ties each
Shibumi candidate to a measured host baseline. Versions not listed here have
not yet passed Shibumi's release gates.

## Current tested host

The `0.1.1-beta.13` candidate is reviewed against the current official
Omarchy Quattro baseline:

| Component | Observed value |
| --- | --- |
| Omarchy package reference | `omarchy 4.0.2-1`, `omarchy-settings 4.0.2-1` |
| Official Omarchy source tag | `v4.0.2` (`346e69e1cec6c4e8924531874af6ba010a1bc99e`) |
| Immutable source-parity revision | `346e69e1cec6c4e8924531874af6ba010a1bc99e` |
| Immutable Agents reference | `v4.0.0` (`f0020448ca87329199de7cb12f2015ebc4a3e5e7`) |
| Immutable forward-compatibility revision | `ed7bae4ac5a570e9df307486e0202fdafcc6ee24` |
| Quickshell package | `quickshell 0.3.1-1` |
| Validation date | 2026-09-05 |

The stable package is the accepted host-build identity. The complete immutable
source-parity checkout is pinned to the official `v4.0.2` tag. The older
Agents-only gate remains explicitly pinned to `v4.0.0`; the separate
`ed7bae4a` snapshot proves bounded forward compatibility without following a
moving branch.

The package-managed baseline records these authoritative production anchors:

| Contract-sensitive file | SHA-256 |
| --- | --- |
| `shell/services/PluginRegistry.qml` | `63371e4224f948e5444531282ad9f7c74ca2e578470b549f4c6b898c3a15c50f` |
| `shell/shell.qml` | `9f1db77dcc3c111ceccc860ac472d19b35d385958a63d270ea51e413ab86f1f0` |
| `shell/Ui/KeyboardPanel.qml` | `96245f2da8d38baa0017caa285d596c485bd19a3a4d2cd1675bee9d84ffba42d` |
| `shell/plugins/bar/Bar.qml` | `1f345f795fe6633a7eb0934b677b86f6c359e0b062567521eeeec7dbf46987c1` |
| `shell/plugins/bar/BarModel.js` | `908f30edce60dcba46d2039ba3d501fd0faa35fa1f90b7dbda69439288f8a8d0` |

The table is a human-readable set of important anchors, not the complete
machine identity. Three separate manifests bind every file or symlink below the
consumed `shell`, `bin`, and `config` subtrees without conflating their claims:

- [`omarchy-installed-package-v4.0.2.json`](../../contracts/baselines/omarchy-installed-package-v4.0.2.json)
  records the package-managed `omarchy 4.0.2-1` and
  `omarchy-settings 4.0.2-1` layout;
- [`omarchy-installed-source-parity-v4.0.2.json`](../../contracts/baselines/omarchy-installed-source-parity-v4.0.2.json)
  records the full Git checkout of the official `v4.0.2` source tag;
- [`omarchy-forward-compat-ed7bae4a.json`](../../contracts/baselines/omarchy-forward-compat-ed7bae4a.json)
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

## What Shibumi validates

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
SHIBUMI_INSTALLED_SOURCE_OMARCHY_PATH=/path/to/omarchy-v4.0.2 \
  ./tests/omarchy-installed-source-parity-contract-regression.sh
SHIBUMI_AGENTS_OMARCHY_PATH=/path/to/omarchy-v4.0.0 \
  ./tests/omarchy-agents-contract-regression.sh
SHIBUMI_FORWARD_COMPAT_OMARCHY_PATH=/path/to/omarchy-forward-compat-ed7bae4a \
  ./tests/omarchy-forward-compat-contract-regression.sh
```

If any recorded host file changes, Shibumi remains on the previous accepted
baseline until the affected contracts and live workflows pass again. Only then
are the package version and hashes in this record advanced.

A complete aggregate run ends with `Shibumi complete contract regression
passed` and names the accepted baseline and full source revision. Absence of
that marker is not complete-contract evidence.

## Omarchy 4.0.3: candidate implemented, acceptance pending

The Beta.13 candidate targets the exact `v4.0.3` host at commit
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

These fixture results do not make 4.0.3 supported. The public widget snapshot
is not a global manifest or service registry; denied or missing capabilities
must not be replaced by private host traversal, a guessed original provider,
undeclared sibling imports, duplicate backends, or authentication access. Final
acceptance still requires the package-bound lifecycle and recovery run, a
coredump-free production restart, complete notification and idle/lock behavior,
output lifetime, hardware-adjacent actions, and physical Top/Bottom and
multi-output checks on unchanged 4.0.3. Existing 4.0.2 evidence does not
transfer to this candidate.

## Recovery boundary

Shibumi does not replace Omarchy's stock recovery path. The lifecycle
uninstaller restores the previous bar state transactionally; the native
fallback remains:

```bash
omarchy bar reset
```
