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
| Omarchy package reference | `omarchy-dev 4.0.0.r1508.g12af188-1` |
| Immutable source-parity revision | `12af188304793b65551b5c43d20f02961dc938a9` |
| Immutable forward-compatibility revision | `fd1034f71b16aa45d5431ab41ed9e48c89fdac8e` |
| Quickshell package | `quickshell-git 0.3.0.r18.g10b439f-3` |
| Validation date | 2026-08-13 |

The package reference declares `provides = omarchy` and remains the accepted
host-build identity. For beta.8, the complete immutable source-parity checkout
at the same `12af188` revision and the separate `fd1034f` forward snapshot pass.
The mutable `/usr/share/omarchy` tree currently has 214 shell inventory entries
instead of the package baseline's 208, so its installed-package rerun is
externally blocked and is not beta.8 evidence.

The package-managed baseline records these authoritative production anchors:

| Contract-sensitive file | SHA-256 |
| --- | --- |
| `shell/services/PluginRegistry.qml` | `598b02719d1dd9badd3547194c6772b13bf28928672fd2b3e0cdc9cf6dda2a99` |
| `shell/shell.qml` | `c1d785275dc379345e9a075dae2066efd7b8d8469bf7b1cdb4d0e91384758836` |
| `shell/Ui/KeyboardPanel.qml` | `96245f2da8d38baa0017caa285d596c485bd19a3a4d2cd1675bee9d84ffba42d` |
| `shell/plugins/bar/Bar.qml` | `955558deae28c5b8927962ab32e9f2c9cf14caee5deac7d14808c63c803f5389` |
| `shell/plugins/bar/BarModel.js` | `c1e90525e4182bee8c3d05a181a0ffeecb303804839d81ceec4ff255ec91943f` |

The table is a human-readable set of important anchors, not the complete
machine identity. Three separate manifests bind every file or symlink below the
consumed `shell`, `bin`, and `config` subtrees without conflating their claims:

- [`omarchy-installed-package-12af188.json`](../../contracts/baselines/omarchy-installed-package-12af188.json)
  records the package-managed layout at `12af188`;
- [`omarchy-installed-source-parity-12af188.json`](../../contracts/baselines/omarchy-installed-source-parity-12af188.json)
  records the full Git checkout of that same installed revision;
- [`omarchy-forward-compat-fd1034f.json`](../../contracts/baselines/omarchy-forward-compat-fd1034f.json)
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
SHIBUMI_INSTALLED_SOURCE_OMARCHY_PATH=/path/to/omarchy-12af188 \
  ./tests/omarchy-installed-source-parity-contract-regression.sh
SHIBUMI_FORWARD_COMPAT_OMARCHY_PATH=/path/to/omarchy-fd1034f \
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
