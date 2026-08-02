# Shibumi host compatibility record

Status: beta-candidate reference (updated 2026-08-02)

Shibumi Shell is built exclusively for Omarchy Quattro. This record ties each
Shibumi candidate to a measured host baseline. Versions not listed here have
not yet passed Shibumi's release gates.

## Current tested host

The `0.1.1-beta.1` candidate is reviewed against this internal validation
baseline:

| Component | Observed value |
| --- | --- |
| Omarchy package | `omarchy-dev 4.0.0.r1508.g12af188-1` |
| Omarchy source revision | `12af188` (encoded in the package version) |
| Quickshell package | `quickshell-git 0.3.0.r18.g10b439f-3` |
| Omarchy path | `/usr/share/omarchy` |
| Validation date | 2026-08-02 |

The validation system uses the development package, which declares
`provides = omarchy`.
It therefore satisfies the Arch package dependency while retaining the exact
host-build record above.

The package-managed host files are the authoritative compatibility baseline:

| Contract-sensitive file | SHA-256 |
| --- | --- |
| `shell/services/PluginRegistry.qml` | `598b02719d1dd9badd3547194c6772b13bf28928672fd2b3e0cdc9cf6dda2a99` |
| `shell/shell.qml` | `c1d785275dc379345e9a075dae2066efd7b8d8469bf7b1cdb4d0e91384758836` |
| `shell/Ui/KeyboardPanel.qml` | `96245f2da8d38baa0017caa285d596c485bd19a3a4d2cd1675bee9d84ffba42d` |
| `shell/plugins/bar/Bar.qml` | `955558deae28c5b8927962ab32e9f2c9cf14caee5deac7d14808c63c803f5389` |
| `shell/plugins/bar/BarModel.js` | `c1e90525e4182bee8c3d05a181a0ffeecb303804839d81ceec4ff255ec91943f` |

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

Run the repository contract suite against the package-managed host:

```bash
OMARCHY_PATH=/usr/share/omarchy ./tests/contract-regression.sh
```

If any recorded host file changes, Shibumi remains on the previous accepted
baseline until the affected contracts and live workflows pass again. Only then
are the package version and hashes in this record advanced.

## Recovery boundary

Shibumi does not replace Omarchy's stock recovery path. The lifecycle
uninstaller restores the previous bar state transactionally; the native
fallback remains:

```bash
omarchy bar reset
```
