# Project state on 2026-07-29

> **Document status: Historical implementation handoff.** This snapshot
> predates the `v0.1.0` alpha audit. Use `release-readiness.md` for the current
> gate state and `ARCHITECTURE.md` for the product contract.

## Resume coordinates

- workspace: `/home/hancore/Projects/shibumi`
- read-only V1 reference:
  `/home/hancore/Projects/Quickshell-Dots/versions/V1`
- read-only V2 reference:
  `/home/hancore/Projects/Quickshell-Dots/versions/V2`
- runtime target: isolated internal Omarchy Quattro validation system
- the validation system physical output: `eDP-1`, 1920x1080, scale 1.0
- active runtime: official Omarchy Quattro shell with the Shibumi suite

Do not clean, reset, or recreate the working tree. Most of the product tree is
currently untracked and is not yet a release commit. The filesystem, rather
than Git history, contains the current candidate.

## Last accepted implementation slice

The Control Center button language now maps the interaction logic observed on
`https://omarchyplugins.com/index.html` onto Shibumi's live theme palette:

- `color08` is the canonical Shibumi ID for ANSI `color8`; parsers retain
  `bright_black` and legacy `color8` compatibility.
- Standard, hover, selected, and primary buttons keep the same `color08` fill.
  Selection and primary emphasis use the active theme accent on the border and
  text instead of changing to an unrelated fill.
- Cards and content surfaces retain the dark Control Center panel colors.
  `color08` is button chrome, not a page- or card-background override.
- Production Control Center buttons are square through
  `controlRadiusOverride: 0`. Circular semantic controls, indicators, and icon
  geometry remain exempt.
- `color08` is exposed in the widget and appearance palette selectors.

the validation system resolved `color08` to `#3A4849` during the accepted run. The value is
not hard-coded and follows the active Omarchy theme.

The residual shadow visible inside the V2 Notch was also removed. The shared
bar shadow already excluded Notch. The remaining contour came from
`ShibumiPanel.qml`'s `RectangularShadow`, which cast into the connected notch.
The original V2 `PillShadow.qml` is a disabled placeholder, so shared V2
panels and their connected Notch must be shadowless. The optional panel shadow
is now restricted to `shellStyle === "shibumi"`; V1 retains its independent
shadow behavior.

## Principal implementation owners

- `hancore.shibumi.control-center/ControlCenterPanel.qml`
- `hancore.shibumi.control-center/CompactSettingChoice.qml`
- `hancore.shibumi.control-center/ControlSettings.qml`
- `hancore.shibumi.control-center/WidgetAppearanceWorkbench.qml`
- `hancore.shibumi.control-center/BarFunctionsPage.qml`
- `shared/state/ThemePaletteModel.js`
- `shared/state/ThemePalette.qml`
- `shared/state/ShibumiConfig.js`
- `hancore.shibumi.state/Service.qml`
- `shared/presentation/ShibumiPanel.qml` and its generated plugin copies

`scripts/sync-shared.sh --write` was used after the shared presentation/state
change. Do not patch generated copies independently.

## Accepted evidence

The following completed successfully against the current tree:

```text
OMARCHY_PATH=/tmp/omarchy-quattro-latest ./tests/control-center-regression.sh
./tests/style-contract-regression.sh
OMARCHY_PATH=/tmp/omarchy-quattro-latest ./tests/theme-palette-runtime-regression.sh
OMARCHY_PATH=/tmp/omarchy-quattro-latest ./tests/contract-regression.sh
```

The complete contract log contained no `Binding loop`, `Unable to assign`,
`TypeError`, or `ReferenceError`. the validation system retained exactly one official
Quickshell process after payload reload. Its final live log contained no new
Shibumi/QML error, and checksum-mode `rsync -ainc` reported no differing
deployed files; only directory timestamps differed.

Retained visual evidence:

- `docs/mockups/control-center-color08-buttons-notch.png`
- `docs/mockups/control-center-color08-appearance.png`

## Continue from here

1. Treat the square `color08` button system and shadowless V2 Notch as the
   current accepted baseline.
2. Continue the Control Center simplification and remaining Icons/widget
   controls without reintroducing card-colored buttons, rounded button chrome,
   or a V2 panel shadow.
3. Preserve V1/Shibumi behavior separately from V2-only features and capability
   gates. Unsupported V2 actions must not appear for V1.
4. Keep the final real-device gates until the end as requested: physical
   second monitor with mixed scale and hotplug, Enterprise WLAN credentials,
   and Bluetooth pair/connect/disconnect/forget plus audio.
5. Do not claim a release checkpoint until the current untracked working tree
   has been reviewed and intentionally committed.
