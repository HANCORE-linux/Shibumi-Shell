# Project state on 2026-07-27

> **Document status: Current handoff snapshot.** This is a concise continuation
> point for Shibumi, the read-only V1/V2 references, current Quattro, and
> the validation system. `ARCHITECTURE.md` and `release-readiness.md` remain authoritative.

## State matrix

| Area | Verified baseline | Current role | State and next boundary |
| --- | --- | --- | --- |
| QS Rise V1 | Clean `versions/V1` at repository commit `0ab6477d0533e6de2981a65d518b8efa0bb6f284` | Primary behavior, geometry, and interaction parity reference | Read-only. Core G1-G15 behavior is ported; the remaining same-state visual matrix, complete Bottom coverage, and physical multi-output states still gate full parity. |
| QS Rise V2 | Clean `versions/V2` at the same repository commit | Secondary design and feature reference | Read-only. Every user-visible outcome is now committed for porting through Omarchy-compatible owners. The V1-default presentation remains selectable. |
| Omarchy Quattro source | `e55f130d55c8f9e5b7b6074c20225f5222ca063c` | Authoritative host contract | Notification center is service-only after `fc4caf3c`; enterprise 802.1X is available and keeps the password off argv; component caching changed in `64810d81`. Shibumi is adapted and the complete contract suite passes. |
| Internal validation system | `omarchy-dev 4.0.0.r1423.gc1647fa-1`, commit `c1647fab` | Isolated runtime acceptance target | One checked source commit behind online head; that commit only changes the Edge glyph. Final Shibumi update passes with one shell process, 22/22 enabled plugins, active Shibumi bar, and a real status panel open/close lifecycle on `eDP-1`. |
| Shibumi | Current working tree, 25 child plugins | Product candidate | Notification drift, enterprise UI, semantic provider replacement, and registry recovery are fixed. Full contract, focused status/network tests, transactional update, payload reload, and the validation system IPC checks pass. The source tree is not yet a clean release commit. |

## Changes completed in this continuation

- Replaced the removed `omarchy.notifications` bar-widget dependency with the
  process-wide official notification service.
- Kept Shibumi's V1 bell, badge, pending/recent tabs, DND, dismiss, mark-seen,
  and clear presentation without duplicating notification ownership.
- Added enterprise identity/password input and delegated connection to
  Quattro's `connectEnterprise` function.
- Added focused fixtures and static contracts for both host changes.
- Added the standard `panelLoaded` diagnostic to the G3 composite.
- Passed `tests/contract-regression.sh` against Quattro `e55f130d`.
- Updated the validation system transactionally. The final status panel moved from
  `opened:false/panelLoaded:false` to `true/true` and returned to `false/false`
  after hide. No test panel remained open.

## Stable validation handoff

- connection details: intentionally omitted from product documentation
- active bar: `hancore.shibumi.bar`
- managed plugins: 25
- disabled managed plugins: none
- Quickshell processes: one
- physical output: `eDP-1`, 1920x1080, scale 1.0
- normalized `shell.json` SHA-256:
  `a6f3c27edeb3054b332fc14d749669824ef5c22b1024b7bf3841f3a4ffed6035`

## 2026-07-28 widget lifecycle continuation

- All G1-G18 groups passed disable/enable recovery on the validation system.
- All 12 Quattro plugins that expose real bar-widget entry points passed
  add, semantic replacement, remove, and Shibumi-provider restoration.
- Twenty rapid `omarchy.clock` replacement cycles completed with zero failed
  Center/Media/Quick Access restorations; worst observed recovery was 800 ms.
- The exact-fit center fallback now splits a one-pixel constraint deficit
  between both legal edges instead of recentering over the asymmetric right
  run. Center and MPRIS retain an 11-12 px gap; ten additional Clock cycles
  preserved at least 12 px with zero failures.
- The full 1273-pixel logical composition now remains at responsive stage 0
  when its measured budget fits exactly. Compact mode begins only on real
  overflow, preventing the prior G9/G10 hysteresis trap.
- Service-only manifests are rejected as visual widget additions.
  `omarchy.notifications` remains correctly consumed as a service by G3.
- Final geometry contains 18 native slots, no duplicate IDs, Center 87 px,
  Media 33 px, and Quick Access 92 px at responsive stage 0. GPU is the only
  non-visible slot because the validation system exposes no available GPU telemetry owner.
- The canonical `omarchy-restart-shell` path restored exactly one Quickshell
  process after testing. No external provider remains in the layout and no
  Shibumi group remains disabled.

## Remaining priorities

1. Finish the current-V1 same-state presentation matrix before claiming full
   parity.
2. Port every V2 user-visible outcome listed in
   `../contracts/v2-feature-port.json` through Omarchy-compatible owners.
3. Redesign the Control Center menu from the user's specification once the
   underlying feature/state inventory is stable.
4. At the very end, complete physical second-output/mixed-scale/hotplug,
   enterprise Wi-Fi credential, and real Bluetooth-device gates.
5. Turn the current working tree into a reviewed clean release commit only
   after the remaining gates and versioning decision are complete.
