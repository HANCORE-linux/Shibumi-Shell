# QS Rise V1 Presentation Contract

> **Document status: Normative supporting contract.** This document defines
> the binding visual and interaction surface for the default Shibumi bar.
> `../ARCHITECTURE.md` remains the product-wide authority.

The default `hancore.shibumi.bar` plugin preserves the approved V1 geometry and
surface language while Shibumi remains a native Omarchy plugin suite. Quattro services may replace V1
backend implementations, but the host's stock 26 px bar presentation is not
the Shibumi visual target.

## Non-Negotiable Visual Contract

V1 is the normative visual and interaction reference for every Shibumi bar
widget, tooltip, panel, picker, and Control Center surface. Shibumi may replace the
implementation behind a surface, but it may not silently replace the approved
surface with the stock Quattro design.

At the same theme, output scale, state, and bar position, Shibumi must preserve V1's:

- panel width, content order, inset, spacing, alignment, and anchor position;
- background, border, radius, shadow, separator, and opacity treatment;
- typography, labels, icon family, icon size, and optical alignment;
- button, tile, slider, meter, menu, hover, active, disabled, and focus states;
- open, close, navigation, loading, and state-change motion; and
- empty, degraded, error, and populated-state hierarchy.

Quattro tokens remain useful as host inputs for scaling and theme integration,
but they must be mapped into the V1 semantic roles. They do not authorize a
different visible geometry, control style, color role, or interaction model.
A stock Quattro control is acceptable only when its rendered result matches the
V1 reference. Otherwise Shibumi supplies a local presentation component over
the authoritative Quattro service and action boundary.

An intentional visible difference requires an explicit product decision and a
recorded exception in the parity matrix. Backend convenience, an existing host
component, or a broadly similar appearance is not such an exception.

The following panel-width extensions are explicit product decisions rather
than accidental visual drift:

| Panel | V1 width | Shibumi plugin width | Reason |
| --- | ---: | ---: | --- |
| Network | 300 px | 380 px | Retains the approved available/saved Wi-Fi, DNS, security metadata, speed-test, connect, and forget workflow without compressing the V1 row hierarchy. |
| Display | 280 px | 380 px | Retains the approved per-display brightness, scale, enable/disable, and display-state controls while preserving V1 control sizes and spacing. |
| Bluetooth | 300 px | 380 px | Retains the approved radio, discovery, device-state, pairing, connection, forget, and audio routing presentation without truncating device rows. |

These exceptions change only the outer content width needed by the additional
workflow. Surface color, border, radius, shadow, typography, control geometry,
spacing, motion, and state styling remain governed by the V1 contract. Power
Profile has no such extension and therefore retains the V1 220 px width.

V1 presentation parity does not freeze the feature set. A useful Quattro panel
capability may be retained when it has a stable service/action contract, does
not introduce a second state owner, is lifecycle-bounded, and can be expressed
without weakening the V1 hierarchy or density. Such additions still use the
V1 surface, control, typography, icon, state, and motion language. Each panel
review therefore records the V1 baseline, available Quattro additions, and the
explicit keep/adapt/exclude decision before that panel is accepted.

## Token Mapping

| V1 source | Shibumi token | Default |
| --- | --- | --- |
| `BarSlot` bar strip | `barHeight` | 35 px |
| `BarSlot.exclusiveZone` | `exclusiveHeight` | 38 px |
| `BarSlot.island.height` | `islandHeight` | 32 px |
| `BarSlot.island` horizontal inset | `islandInsetX` | 5 px |
| `Theme.pillH` | `pillHeight` | 24 px |
| `Theme.pillRadius` | `pillRadius` | 12 px |
| `Theme.islandRadius` | `islandRadius` | 16 px |
| Widget content padding | `pillPaddingX` | 9 px per side |
| Full/compact row spacing | `contentGap` / `compactGap` | 5 / 4 px |
| Static labels | `labelSize` | 12 px |
| Compact material glyphs | `iconSize` | 15 px |
| Invalid drag return | `invalidDropDuration` | 230 ms |

Values use the host spacing and font scales so Quattro accessibility settings
remain effective. At the default scale they reproduce V1 exactly.

## Ownership

- `shared/` owns the canonical Shibumi presentation contract during
  development; deterministic vendored copies keep runtime plugins
  self-contained.
- Every bar host exposes the versioned visual-token subset through the common
  host facade.
- Services, adapters, layout persistence, and panel state do not depend on a
  selected bar implementation.
- Official Quattro widgets remain temporary backend-compatible fallbacks until
  their complete Shibumi view and workflow pass the parity matrix.

## Current Evidence

CPU, memory, audio, media, workspaces, the G1 launcher, and the G8 center are
the first token-backed widget slices. CPU and memory normal/compact states use the same shared telemetry owner and preserve
the V1 pill, label, graph/ring, numeric, and compact-glyph structure. The
workspace view preserves V1 pill padding plus default, numbers, and magic
geometry while retaining the native Shibumi service/action boundary.

G1 preserves the V1 wordmark and icon modes, exact approved image assets, pill
geometry, and lifecycle-gated wave feedback. It now lives in
`hancore.shibumi.control-center` and opens the screen-local Control Center rather
than the App Menu.

The bounded, scrollable Control Center owns the V1 bar controls:
the eleven user-toggleable widget groups, all eight compact modes, current V1
colors 01-07 plus foreground, workspace mode/style, picker style, top/bottom
placement, split/reset actions, Reactor modes, and presentation choices.
Mutations delegate through the active bar-host facade and then through
Quattro's configuration writer; a group disabled there unloads its complete
group tree, including configured optional Quattro children. The eight-choice
palette, canonical color01 default, migration aliases, contrast-aware labels,
four-column layout, atomic theme reload, and live radius propagation pass their
focused and complete validation-system gates.

The G8 center uses one shared minute-precision service for every output and
keeps the V1 24-hour default, optional 12-hour label, date typography, timezone
action, and lazy calendar. Weather uses one process-wide Shibumi source because
Quattro currently exposes weather state only inside its stock panel; that
source honors Quattro's persisted location while the bar and lazy detail panel
retain V1 presentation. Idle and notification state continue to use their
official Quattro owners. The normal/compact/minimal stage uses a per-output free
span, 24 px downshift slack, and 48 px upshift slack; optional G8 siblings are
removed from the available width before staging. Component and model evidence
is complete locally; real Wayland, top/bottom, and multi-output visual
acceptance remains a separate parity gate.

G6 preserves the V1 `VOL` label, capsule fill, percentage, compact
`graphic_eq` glyph, tooltip, wheel step, and right-click mute behavior. The
view does not own audio state. It overlays one registered Shibumi interaction
surface on the hidden official `omarchy.audio` component, whose stock button
and popup stay inactive. The lazy local panel restores V1 output/input volume,
description-first device labels, device switching, per-app mixing, microphone
feedback, and mute actions while delegating every mutation to the official object.
Full/compact geometry, lazy model release, action routing, and bridge teardown
are proven locally; the real Wayland mixer window and multi-output anchors
remain open acceptance gates.

G9 must preserve V1's idle note, previous/play/next controls, fixed-width
marquee, playing pulse, tooltip, cover/progress panel, and selectable
FULL/muse outcome: 24-band real Cava, vinyl mark, transport state, click
play/pause, and wheel previous/next. State, player selection, source selection,
and every transport action come from the single official `omarchy.media`
service. One lazy process-wide Shibumi spectrum service may own the bounded
Cava process and degraded state; no per-output, per-panel, or per-view process
copy is permitted. The default row, lazy panel, and FULL/muse outcome now
exist. the validation system accepts a real player, available/unavailable/crash paths,
bounded retry and cleanup, Top/Bottom rendering, and the focused
single-output resource slice. Multiple-real-player source switching, remaining
media-panel states, and physical multi-output remain acceptance gates.

`tests/shibumi-presentation-smoke.qml` proves at component-load time that:

- the 35/38/32/24 px geometry contract is active;
- CPU and memory follow the Shibumi bar height;
- compact variants reduce width instead of merely hiding content; and
- normal and compact variants instantiate against one shared telemetry owner.

Real Wayland visual comparison, top/bottom positioning, mixed-scale output,
and multi-monitor interaction remain release gates. Offline component smokes
do not replace those checks.

For each visible panel, acceptance requires a side-by-side QS Rise V1/Shibumi comparison at
the same theme and scale. The comparison covers at least the closed trigger,
normal populated panel, relevant hover/active state, and an empty or degraded
state when the panel supports one. Functional, lifecycle, and performance
evidence remains required in addition to this visual gate.
