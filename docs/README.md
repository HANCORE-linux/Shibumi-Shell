# Shibumi documentation

Status: canonical documentation index

Shibumi separates user guides, stable architecture contracts, current
validation evidence, contributor workflows, and historical implementation
records. Supporting documents never override the canonical
[architecture contract](../ARCHITECTURE.md).

## Reading paths

For users:

1. [Get started](getting-started.md)
2. [Install and update](install.md)
3. [Configuration](configuration.md)
4. [Plugin catalog](plugins/README.md)
5. [Plugin compatibility](plugin-compatibility.md)
6. [Troubleshooting](development/troubleshooting.md)

For maintainers:

1. [Architecture overview](architecture/overview.md)
2. [Shibumi host compatibility record](architecture/quattro-compatibility.md)
3. [Canonical architecture contract](../ARCHITECTURE.md)
4. [Host facade](host-facade-v1.md)
5. [Plugin suite migration and lifecycle](plugin-suite-migration-plan.md)
6. [Testing](development/testing.md)
7. [Packaging and AUR strategy](development/packaging.md)
8. [Release workflow](development/release.md)
9. [Current release readiness](release-readiness.md)

For design and UI work:

1. [Shibumi design entry point](../DESIGN.md)
2. [V1 presentation contract](v1-presentation-contract.md)
3. [Control Center contract](control-center-v4.md)
4. [Style extension guide](../styles/README.md)
5. [Screenshot plan](screenshots/README.md)

For parity and release evidence:

1. [V1 parity matrix](v1-parity-matrix.md)
2. [V1 widget parity audit](v1-widget-parity-audit.md)
3. [V1 output lifecycle audit](v1-output-lifecycle-audit.md)
4. [Current V1 discrepancy audit](current-v1-discrepancy-audit.md)
5. [Quattro contract gaps](omarchy-quattro-contract-gaps.md)

## Document classes

- **Canonical contract:** product-wide premises and release rules
- **Supporting contract:** one bounded interface or presentation surface
- **Current validation gate:** latest proven and unproven release behavior
- **Validation evidence:** dated test or audit evidence
- **Historical record:** implementation or migration context that may no
  longer describe the current tree
- **External dependency register:** missing host contracts and bounded
  workarounds

## Current references

| Document | Purpose |
| --- | --- |
| [Get started](getting-started.md) | Control Center, bar switching, customization, and saved state |
| [Install and update](install.md) | Install, migrate, activate, update, deactivate, and remove the suite |
| [Configuration](configuration.md) | Omarchy shell settings, Shibumi state, and ownership |
| [Plugin catalog](plugins/README.md) | The 24 plugin roots, roles, and host dependencies |
| [Plugin compatibility](plugin-compatibility.md) | Supported use with stock, Shibumi-compatible, and third-party bars |
| [Architecture overview](architecture/overview.md) | Short runtime and ownership map |
| [Host compatibility record](architecture/quattro-compatibility.md) | Exact accepted Omarchy Quattro and Quickshell package baseline |
| [Testing](development/testing.md) | Local automation and maintainer release-validation workflow |
| [Packaging and AUR strategy](development/packaging.md) | Arch package boundary, dependencies, rehearsal, and AUR publication gates |
| [Troubleshooting](development/troubleshooting.md) | Recovery paths for install, bar, panel, and runtime failures |
| [Release workflow](development/release.md) | Beta preparation, immutable assets, and publication gates |
| [Release readiness](release-readiness.md) | Current acceptance evidence and public-release blockers |
| [Development handoff](project-state-2026-07-30.md) | Resume coordinates, latest implementation slice, open issues, and next work |
| [Changelog](../CHANGELOG.md) | User-visible changes by version |

Machine-readable contracts under [`../contracts/`](../contracts/) and the
current source define exact schema fields, plugin IDs, and executable defaults.

## Supporting contracts

| Document | Scope |
| --- | --- |
| [V1 presentation contract](v1-presentation-contract.md) | Geometry, surfaces, controls, typography, icons, motion, and interaction |
| [Phase 2 ownership map](phase2-ownership-map.md) | G1-G18 state, action, widget, and panel ownership |
| [Host facade v1](host-facade-v1.md) | Reusable widget-to-bar API |
| [Widget provider contract](widget-provider-contract.md) | Widget registration and provider behavior |
| [Control Center v4](control-center-v4.md) | Control Center design and runtime contract |
| [Health diagnostics](health-diagnostics.md) | Read-only runtime, error, and source-drift contract |
| [Multi-bar extension plan](multi-bar-extension-plan.md) | Registration and validation rules for additional bar hosts |
| [V1 output lifecycle audit](v1-output-lifecycle-audit.md) | Multi-output, scale, hotplug, DPMS, suspend, and resume behavior |

## Validation and historical records

The dated project-state, phase-validation, inventory, migration, and
predecessor-evidence documents remain in this directory so existing links stay
valid. Use them for provenance, not for the current release decision. When
summaries disagree, [release readiness](release-readiness.md) is current.

## Updating the contract

Every product-level behavior change must update:

1. `ARCHITECTURE.md`;
2. the affected supporting contract;
3. the relevant parity or release gate;
4. executable defaults or machine-readable contracts when behavior changes;
5. regression and runtime evidence appropriate to the change.

A discussion, screenshot, or test note alone does not change the product
contract.
