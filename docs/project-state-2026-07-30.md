# Project state on 2026-07-30

> **Document status: Current development handoff.** The commit containing this
> document is the resume baseline. Product rules remain authoritative in
> [`../ARCHITECTURE.md`](../ARCHITECTURE.md), and release decisions remain in
> [`release-readiness.md`](release-readiness.md).

## Resume coordinates

- source workspace: `/home/hancore/Projects/shibumi`
- validation target: isolated internal Omarchy Quattro system; connection
  details intentionally omitted from product documentation
- runtime: `/usr/share/omarchy/shell`
- tested Quattro package: `4.0.0.r1458.gfa6b5fc-1`
- physical output: `eDP-1`, 1920×1080, scale 1.0
- read-only V1 reference:
  `/home/hancore/Projects/Quickshell-Dots/versions/V1`
- read-only V2 reference:
  `/home/hancore/Projects/Quickshell-Dots/versions/V2`

All runtime tests belong on the validation system. Do not deploy Shibumi into the
`Quickshell-Dots` reference tree.

## Accepted implementation slice

### Hosted bar and panel geometry

- The horizontal bar host remains edge-local so standard Omarchy panels read
  the real bar height. Full-output edit dismissal and drag feedback live in
  separate per-output overlay windows.
- V2 Full, Fit, Dock, and Notch own their negative space in the filled
  silhouette. The connected bar cutout is not simulated with a
  background-colored shadow or erase layer.
- `core/HostedPanelConnector.qml` supplies one screen-local, input-transparent
  connected panel edge for every compatible non-Shibumi widget.
- `core/WidgetSlot.qml` applies the same adapter to Quattro built-ins and
  third-party plugins. WireGuard is the live acceptance example; it is not a
  special case.
- The hosted connector replaces the foreign straight card border below its
  native-shaped caret. Regression coverage locks the bridge below the
  replacement edge so the caret shoulders cannot be clipped again.

### Control Center plugin workflow

- **Add plugin** opens the Git installer directly and does not repeat the
  installed catalog.
- The Git field accepts HTTPS, SSH, and `git@` syntax. A valid value receives
  theme `color03`; the risk control remains disabled beforehand.
- Typography and button rendering use the shared Control Center standard.
- Installed and available summaries report real Shibumi, Omarchy, and
  third-party provider counts.
- Existing provider replacement, Undo countdown, Favorites, predictive search,
  click-away dismissal, and removal behavior remain the accepted baseline in
  [`control-center-v4.md`](control-center-v4.md).

### Documentation and tracked follow-ups

- GitHub issue
  [#1](https://github.com/HANCORE-linux/Shibumi-Shell/issues/1) tracks an
  explicit host wrapper for third-party plugins that do not expose the
  standard Omarchy panel contract.
- GitHub issue
  [#2](https://github.com/HANCORE-linux/Shibumi-Shell/issues/2) tracks optional
  V1 side slots and their atomic layout migration. The design plan exists
  under `/home/hancore/Projects/Reports/quickshell-v1-side-slots/`; the feature
  is not implemented.
- Physical mixed-scale multi-monitor, enterprise Wi-Fi, and remaining
  Bluetooth workflows stay open in
  [`release-readiness.md`](release-readiness.md).

## Validation evidence

the validation system uses 25 managed Shibumi plugins. The affected regression passes on
2026-07-30 include:

```text
./tests/style-contract-regression.sh
OMARCHY_PATH=/usr/share/omarchy ./tests/control-center-regression.sh
OMARCHY_PATH=/usr/share/omarchy ./tests/quattro-contract-regression.sh
./scripts/shibumi-suite update --yes
```

The live WireGuard panel was opened on the physical Wayland session after the
suite update. Its bar cutout and panel tip match the native Shibumi geometry,
the panel closed normally, and the active log contained no new Shibumi QML
type, loader, reference, or binding-loop error.

The first complete-contract attempt exposed that `core/DragSession.qml`
imported Quickshell only to test whether its drag source had a window. That
made the pure Qt layout-controller model test unloadable. The implementation
now uses the native `QQuickItem.window` property, preserving the runtime
capture while keeping the model host-independent. After this correction,
`OMARCHY_PATH=/usr/share/omarchy ./tests/contract-regression.sh` passed in full
on the validation system.

## Continue from here

1. Continue Control Center work from the current Configure routes; do not
   restore the retired cross-style editor or duplicate navigation labels.
2. Keep V1-only and V2-only capabilities hidden outside their active style.
3. Use the generic hosted-panel path for compatible external widgets. Do not
   add per-plugin caret, radius, border, or bar-cutout patches.
4. Implement issue #2 only as an explicit V1 layout migration; do not modify
   the fixed V1 layout opportunistically while working on V2.
5. Before a release tag, run the complete validation contract on the exact commit
   and complete the remaining physical gates listed in release readiness.
