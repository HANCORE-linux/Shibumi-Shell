# V2 feature port plan

The product decision is fixed: every user-visible V2 outcome is to be available
in Shibumi wherever the Omarchy plugin contract permits it. The executable list
is [`contracts/v2-feature-port.json`](../contracts/v2-feature-port.json); every
entry is required to have `decision: "port"`.

“Port” means preserving the behavior and presentation outcome, not copying the
old standalone architecture. Shibumi keeps Quattro's process-wide owners,
action boundaries, plugin lifecycle, screen objects, and panel routing. Legacy
pollers, shell update scripts, duplicate media/network/Bluetooth owners, and
standalone layer-window ownership are adapted to those official contracts.

The implementation order is:

1. Pure presentation over existing owners: Kanji, Rings, Aurora and already
   accepted Tanzaku, Hearthstone, and FULL/muse.
2. Bar host geometry: Full, Fit, Dock, Notch, borders, and responsive staging.
3. Shared presentation/state: connected silhouettes, pointers, per-widget
   palette, fill/border modes, separators, compact, and icon-only modes.
4. Optional feature slices: temperature source/widget, thermals, GPU, storage,
   MPRIS artwork, tray drawer/menu, and update controls.
5. Control Center exposure after the user-directed menu redesign is specified.
6. Final physical multi-output, mixed-scale, hotplug, enterprise Wi-Fi, and
   Bluetooth-device acceptance.

The V1 presentation remains available; V2 capabilities are selectable Shibumi
functions rather than an implicit replacement of the default.

Pacman is a Shibumi workspace presentation adapted from the separate
[`HANCORE-linux/waybar-themes` V2.1-2 configuration](https://github.com/HANCORE-linux/waybar-themes/tree/main/config/V2.1-2).
It is available in both Shibumi layout variants, but it is deliberately not
listed as a QS Rise V2 port and does not change that repository boundary.

## Verification

The executable evidence map is
[`contracts/v2-feature-evidence.json`](../contracts/v2-feature-evidence.json).
It has an exact one-to-one ID match with all 36 required port entries and names
the production owners plus focused tests for each outcome. The complete
contract suite rejects missing IDs, missing implementation owners, missing
tests, or stale paths.

On 2026-07-28 the current Full, Fit, Dock, and Notch shells were rendered on
the validation system at 1920×1080, scale 1. Full uses the complete output width; Fit, Dock,
and Notch shrink to their natural content width; all use the original V2
33-pixel visible height and 36-pixel exclusive zone. V2 widgets render directly
on the one shared shell instead of retaining V1 per-widget pills. The contour
contract is explicit: Full has only the desktop-facing edge and directional
shadow; Fit alone has a closed perimeter; Dock leaves the screen-facing edge
open and joins its side runs to the desktop-facing rounded edge; Notch leaves
the screen-facing edge open and draws only its two V2 shoulders plus the
desktop-facing edge. Notch intentionally has no rectangular shadow.

The later connected-panel audit found that excluding the shared bar shadow was
not sufficient: `ShibumiPanel.qml` could still cast its own
`RectangularShadow` into the connected Notch. Original V2's `PillShadow.qml`
is a disabled placeholder. Shared Full, Fit, Dock, and Notch panels are
therefore shadowless, while the independent V1/Shibumi presentation may retain
its configured panel shadow. This distinction is regression-protected.

The corrected live captures are
`docs/mockups/shibumi-v2-full-open-edge.png`,
`docs/mockups/shibumi-v2-fit-closed-frame.png`,
`docs/mockups/shibumi-v2-dock-open-edge.png`, and
`docs/mockups/shibumi-v2-notch-open-edge.png`. A direct
Shibumi-to-Full transition retained the open Icons page (`opened=true`,
`panelLoaded=true`) and is captured in
`docs/mockups/shibumi-control-center-survives-shell-switch.png`.

The same the validation system pass audited the complete G1–G18 bar language against both
predecessors. Shibumi keeps the V1 acronym/detail presentations, while Full,
Fit, Dock, and Notch use the V2 symbol-plus-value presentations. In particular,
the V2 shells no longer render `MEM`, `CPU`, `VOL`, `NET`, `BAT`, `BRI`, `PWR`,
`BT`, `GPU`, or `HDD` prefixes. Storage uses the original V2 `󰋊` glyph, GPU
ships the original card asset inside its plugin, and CPU temperature uses the
original V2 thermometer glyph. Full mode, icon-only mode, and text-only mode
remain independent user choices. The two live reference captures are
`docs/mockups/shibumi-v2-widget-language.png` and
`docs/mockups/shibumi-v1-widget-language-preserved.png`.

The G3 tray drawer and DBusMenu path also passes at Top and Bottom on the
current the validation system build. A persistent root `QsMenuOpener` keeps Quickshell's
authoritative DBus menu tree alive while a second opener traverses child
handles. The application-menu card retains its root height during navigation,
so a Top submenu cannot shrink away from the pointer and expose the dismiss
surface. The deterministic fixture produced two real `item=6` nested-action
events. The corresponding retained-child captures are
`docs/mockups/shibumi-v1-g3-dbus-submenu-top.png` and
`docs/mockups/shibumi-v1-g3-dbus-submenu-bottom.png`.

The same screen-local acceptance route now covers the V1 notification card.
A uniquely tagged notification entered Quattro's single authoritative pending
model and rendered in Shibumi at Top and Bottom. Clicking the visible row
dismiss control removed the authoritative pending entry and updated the still
open Top card to its empty state. Evidence is stored in
`docs/mockups/shibumi-v1-g3-notifications-populated-top.png`,
`docs/mockups/shibumi-v1-g3-notifications-dismissed-top.png`, and
`docs/mockups/shibumi-v1-g3-notifications-populated-bottom.png`.
