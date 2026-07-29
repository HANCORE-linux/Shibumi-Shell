# Shibumi documentation index

> **Document status: Canonical documentation index.** Start with
> [`../ARCHITECTURE.md`](../ARCHITECTURE.md). It is the only document that may
> define or change the product-wide Shibumi contract.

This index separates binding contracts from current validation evidence and
historical implementation records. A detail document never overrides
`ARCHITECTURE.md`.

## Status definitions

- **Canonical contract**: defines product-wide premises and release rules
- **Normative supporting contract**: defines one bounded surface in more detail
- **Current validation gate**: records the latest proven and unproven behavior
- **Validation evidence**: records a test run or audit that supports a gate
- **Historical record**: preserves decisions or migration evidence but does not
  describe the current release state
- **External dependency register**: tracks missing host contracts and bounded
  workarounds

## Required reading order

1. [`../ARCHITECTURE.md`](../ARCHITECTURE.md): product boundary, premises,
   ownership, lifecycle, performance, safety, and release gates
2. [`v1-presentation-contract.md`](v1-presentation-contract.md): binding V1
   visual and interaction contract
3. [`phase2-ownership-map.md`](phase2-ownership-map.md): binding G1-G15 state,
   action, widget, and panel ownership
4. [`host-facade-v1.md`](host-facade-v1.md): versioned contract between feature
   plugins and selectable bar hosts
5. [`plugin-suite-migration-plan.md`](plugin-suite-migration-plan.md): plugin
   boundaries, repository layout, bundle lifecycle, and migration rules
6. [`multi-bar-extension-plan.md`](multi-bar-extension-plan.md): supported
   procedure and release gates for additional Shibumi bar hosts
7. [`release-readiness.md`](release-readiness.md): current private release gate

## Normative supporting contracts

| Document | Binding scope |
| --- | --- |
| [`v1-presentation-contract.md`](v1-presentation-contract.md) | Binding QS Rise V1 reference geometry, surfaces, controls, typography, icons, motion, and interaction for Shibumi parity |
| [`phase2-ownership-map.md`](phase2-ownership-map.md) | G1-G15 owners, adapters, actions, and configuration boundaries |
| [`host-facade-v1.md`](host-facade-v1.md) | Reusable widget-to-bar application programming interface (API) |
| [`plugin-suite-migration-plan.md`](plugin-suite-migration-plan.md) | Independent plugin boundaries, packaging, installation, update, rollback, and removal |
| [`control-center-v4.md`](control-center-v4.md) | ContextOwl/shadcn control-center design, Quattro plugin management contract, security confirmation, runtime evidence, and remaining gates |
| [`multi-bar-extension-plan.md`](multi-bar-extension-plan.md) | Quattro-compatible registration, shared ownership, switching, fallback, and validation rules for additional Shibumi bars |
| [`app-menu-integration-plan.md`](app-menu-integration-plan.md) | Independent App Menu ownership and its separation from G1 |
| [`v1-output-lifecycle-audit.md`](v1-output-lifecycle-audit.md) | Multi-output, hotplug, Display Power Management Signaling (DPMS), suspend, hibernate, and resume requirements |
| [`../styles/README.md`](../styles/README.md) | Rules for adding another selectable Shibumi bar presentation |

Machine-readable contracts under [`../contracts/`](../contracts/) and current
source code define exact schema fields, plugin IDs, and executable defaults.

## Current status and release evidence

| Document | Purpose |
| --- | --- |
| [`release-readiness.md`](release-readiness.md) | Current `v0.1.0` alpha evidence, private acceptance, and public-release blockers |
| [`../CHANGELOG.md`](../CHANGELOG.md) | User-visible changes by version |
| [`project-state-2026-07-27.md`](project-state-2026-07-27.md) | Earlier V1, V2, Quattro, Shibumi, and Machine2 continuation snapshot |
| [`v1-parity-matrix.md`](v1-parity-matrix.md) | Product-wide QS Rise V1 outcome and current Shibumi status by feature |
| [`v1-widget-parity-audit.md`](v1-widget-parity-audit.md) | G1-G15 capability, presentation, and runtime evidence |
| [`current-v1-discrepancy-audit.md`](current-v1-discrepancy-audit.md) | Dated comparison between the current read-only V1 worktree and the Shibumi contract |
| [`phase3-validation.md`](phase3-validation.md) | Split, drag-and-drop, persistence, and interaction evidence |

When status summaries disagree, `release-readiness.md` is current. The other
files retain the detailed evidence behind that summary.

## Historical validation and migration records

| Document | Historical scope |
| --- | --- |
| [`project-state-2026-07-29.md`](project-state-2026-07-29.md) | Pre-alpha Control Center `color08` and shadowless V2 Notch handoff |
| [`runtime-validation.md`](runtime-validation.md) | Phase 1 combined-plugin and early Machine2 runtime evidence |
| [`phase2-validation.md`](phase2-validation.md) | Phase 2 combined-plugin and feature-slice evidence |
| [`plugin-suite-inventory.md`](plugin-suite-inventory.md) | File ownership ledger used during extraction into independent plugins |
| [`qs-rise-predecessor-release-evidence.md`](qs-rise-predecessor-release-evidence.md) | Last full Machine2 release evidence for the pre-rename `hancore.qsrise.*` suite |

These documents may describe transitional paths or incomplete phases that no
longer match the current tree. Use them to understand provenance, not to decide
whether the current release passes.

## External dependency register

[`omarchy-quattro-contract-gaps.md`](omarchy-quattro-contract-gaps.md) records
host capabilities that Quattro does not expose through a stable plugin API.
Each entry states the current workaround and whether the gap blocks release.

## Local reports

Files under `~/Projects/Reports` contain V1 audits, measurements, architecture
options, pull request reviews, and earlier decisions. They remain useful
evidence, but they are outside this repository and are not normative. Any
decision that still applies must also appear in `ARCHITECTURE.md` or a linked
normative supporting contract.

## Updating the contract

Every change to a Shibumi premise must update:

1. `ARCHITECTURE.md`
2. the affected normative supporting contract
3. the relevant parity or release gate
4. executable defaults or machine-readable contracts when behavior changes
5. regression and runtime evidence required by the blast radius

A conversation, test note, or phase report alone does not change the product
contract.
