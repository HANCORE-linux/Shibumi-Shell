# Shibumi host compatibility record

Status: beta-candidate reference (updated 2026-08-13)

Shibumi Shell is built exclusively for Omarchy Quattro. This record ties each
Shibumi candidate to a measured host baseline. Versions not listed here have
not yet passed Shibumi's release gates.

## Current tested host

The `0.1.1-beta.8` candidate is reviewed against this internal validation
baseline:

| Component | Observed value |
| --- | --- |
| Omarchy package reference | `omarchy-dev 4.0.0.r1664.gb99fd91-1` |
| Immutable source-parity revision | `b99fd91cf11db92b03bbd69e4fff908662bd74a3` |
| Immutable forward-compatibility revision | `d6b21f80750ccaf488373973f1ee25db21de7d26` |
| Quickshell package | `quickshell-git 0.3.0.r20.g28771c7-1` |
| Validation date | 2026-08-13 |

The package reference declares `provides = omarchy` and remains the accepted
host-build identity. The complete immutable source-parity checkout is pinned to
the same `b99fd91` revision; the separate `d6b21f80` snapshot proves bounded
forward compatibility without following a moving branch.

The package-managed baseline records these authoritative production anchors:

| Contract-sensitive file | SHA-256 |
| --- | --- |
| `shell/services/PluginRegistry.qml` | `63371e4224f948e5444531282ad9f7c74ca2e578470b549f4c6b898c3a15c50f` |
| `shell/shell.qml` | `9f1db77dcc3c111ceccc860ac472d19b35d385958a63d270ea51e413ab86f1f0` |
| `shell/Ui/KeyboardPanel.qml` | `96245f2da8d38baa0017caa285d596c485bd19a3a4d2cd1675bee9d84ffba42d` |
| `shell/plugins/bar/Bar.qml` | `8bbe27ad7c617da1a3770fd5731b8cc79935ac34f04873c3933f7ff581a7cb15` |
| `shell/plugins/bar/BarModel.js` | `908f30edce60dcba46d2039ba3d501fd0faa35fa1f90b7dbda69439288f8a8d0` |

The table is a human-readable set of important anchors, not the complete
machine identity. Three separate manifests bind every file or symlink below the
consumed `shell`, `bin`, and `config` subtrees without conflating their claims:

- [`omarchy-installed-package-b99fd91.json`](../../contracts/baselines/omarchy-installed-package-b99fd91.json)
  records the package-managed layout at `b99fd91`;
- [`omarchy-installed-source-parity-b99fd91.json`](../../contracts/baselines/omarchy-installed-source-parity-b99fd91.json)
  records the full Git checkout of that same installed revision;
- [`omarchy-forward-compat-d6b21f80.json`](../../contracts/baselines/omarchy-forward-compat-d6b21f80.json)
  records the immutable forward-compatibility snapshot from the engineering
  audit. It does not follow the moving remote branch.

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

Run the repository contract suite separately against all three host proof axes:

```bash
./tests/omarchy-installed-package-contract-regression.sh
SHIBUMI_INSTALLED_SOURCE_OMARCHY_PATH=/path/to/omarchy-b99fd91 \
  ./tests/omarchy-installed-source-parity-contract-regression.sh
SHIBUMI_FORWARD_COMPAT_OMARCHY_PATH=/path/to/omarchy-d6b21f80 \
  ./tests/omarchy-forward-compat-contract-regression.sh
```

If any recorded host file changes, Shibumi remains on the previous accepted
baseline until the affected contracts and live workflows pass again. Only then
are the package version and hashes in this record advanced.

A complete aggregate run ends with `Shibumi complete contract regression
passed` and names the accepted baseline and full source revision. Absence of
that marker is not complete-contract evidence.

## Recovery boundary

Shibumi does not replace Omarchy's stock recovery path. The lifecycle
uninstaller restores the previous bar state transactionally; the native
fallback remains:

```bash
omarchy bar reset
```
