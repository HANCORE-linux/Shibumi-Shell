# V1 same-state presentation matrix

The executable scope is
[`contracts/v1-state-matrix.json`](../contracts/v1-state-matrix.json). It is the
completion checklist for point 1 and complements the feature-level parity audit.

Each visible surface must be compared between the clean QS Rise V1 reference and
Shibumi with the same output, scale, theme, wallpaper, data state, and bar
position. A representative “panel open” screenshot does not cover empty,
populated, hover, active, error, or degraded presentation.

The matrix covers the closed bar, edit/split/drag state, G1-G15 surfaces,
tooltips, keyboard focus, Top, and Bottom. Its status is deliberately not
“passed”: several principal surfaces have earlier the validation system evidence, but the
complete same-state set has not yet been captured against the current payload.

Hardware-independent states are executed first. These three physical families
remain mandatory but are scheduled at the very end:

- physical second output, mixed scale, and hotplug, including unplug during drag
- enterprise Wi-Fi with real credentials
- Bluetooth pairing, connection, audio routing, disconnection, and forgetting

Fixtures may prove component behavior, but they cannot close those physical
gates.

## Current exact-state evidence

- `G2.workspaces` populated Top and Bottom now use the original compact panel
  instead of duplicating display-mode and style settings that belong in
  Icons. V1 and Shibumi both render a 240×95 outer card (238×93
  contiguous fill), with a 24 px heading, one separator, 30 px rows at 4 px
  spacing, numeric window counts, and the original text close affordance.
  Quattro keyboard navigation and the capped scrolling extension remain
  available without altering the normal V1 state. Evidence:
  `docs/mockups/v1-reference-g2-workspaces-top.png`,
  `docs/mockups/shibumi-v1-parity-g2-workspaces-top-v2.png`,
  `docs/mockups/v1-reference-g2-workspaces-bottom.png`, and
  `docs/mockups/shibumi-v1-parity-g2-workspaces-bottom-v2.png`.

- `G4.memory` Top and Bottom were captured in one the validation system session against an
  instrumented-but-visually-unchanged V1 reference. The Shibumi card now has
  the same 320×201 outer geometry (318×199 contiguous fill), 8 px bar gap,
  12 px content insets, and the same Y coordinates: fill `+44` at Top and
  `+837` at Bottom. The implementation retains Quattro keyboard focus,
  screen routing, and action ownership. Evidence:
  `docs/mockups/v1-reference-g4-memory-top.png`,
  `docs/mockups/shibumi-v1-parity-g4-memory-top-v3.png`,
  `docs/mockups/v1-reference-g4-memory-bottom.png`, and
  `docs/mockups/shibumi-v1-parity-g4-memory-bottom-v3.png`.

- `G5.cpu` was compared against the same V1 reference in populated and
  driver-degraded conditions. Shibumi now uses the original fixed geometry:
  320 px width, 12 px insets, 8 px gaps, 24 px header, 16 px CPU/GPU rows,
  8 px meters, and a 28 px action. This yields the original 150 px populated
  height (CPU + GPU) and 126 px degraded height (CPU only), with exact Top and
  Bottom anchoring. Evidence:
  `docs/mockups/v1-reference-g5-cpu-top.png`,
  `docs/mockups/v1-reference-g5-cpu-bottom.png`,
  `docs/mockups/v1-reference-g5-cpu-top-degraded.png`,
  `docs/mockups/shibumi-v1-parity-g5-cpu-top-v2.png`, and
  `docs/mockups/shibumi-v1-parity-g5-cpu-bottom-v2.png`.

- `G6.audio` now matches the current V1 default mixer state at both edges.
  Both cards have the same 280×369 outer geometry (278×367 contiguous fill),
  Top fill position `+44`, and Bottom fill position `+669`. The visible flow
  is again the V1 sequence—output meter, output device, mute action, input
  status and meter, microphone mute, and launcher—while Quattro's PipeWire
  backend, source switching, and optional application streams remain intact.
  Evidence:
  `docs/mockups/v1-reference-g6-audio-top.png`,
  `docs/mockups/shibumi-v1-parity-g6-audio-top-v4.png`,
  `docs/mockups/v1-reference-g6-audio-bottom.png`, and
  `docs/mockups/shibumi-v1-parity-g6-audio-bottom-v4.png`.

- `G8.clock` now preserves the original centered Calendar presentation rather
  than following small shifts in the clock widget anchor. V1 and Shibumi both
  render a 280×277 outer card (278×275 contiguous fill), centered at `+821`,
  with Top fill `+44` and Bottom fill `+761`. The original typography,
  unframed navigation arrows, weekday colors, 7×6 day grid, today marker, and
  selected-day ring are restored. V2 shell styles still receive Shibumi
  contract tooltips, while the V1 `shibumi` style keeps the original
  tooltip-free arrow hover. Evidence:
  `docs/mockups/v1-reference-g8-calendar-top-v2.png`,
  `docs/mockups/shibumi-v1-parity-g8-calendar-top-v3.png`,
  `docs/mockups/v1-reference-g8-calendar-bottom-v2.png`, and
  `docs/mockups/shibumi-v1-parity-g8-calendar-bottom-v3.png`.

- `G8.weather` populated Top and Bottom now retain the original G8 group
  anchor, 300×344 outer geometry (298×342 contiguous fill), 12 px insets,
  V1 text close affordance, detail rows, three-day forecast grid, and paired
  28 px actions. The shared panel primitive gained a scoped along-bar center
  offset so this panel can reproduce V1's one-pixel G8 anchor without shifting
  Calendar or other panels. Evidence:
  `docs/mockups/v1-reference-g8-weather-top.png`,
  `docs/mockups/shibumi-v1-parity-g8-weather-top-v3.png`,
  `docs/mockups/v1-reference-g8-weather-bottom.png`, and
  `docs/mockups/shibumi-v1-parity-g8-weather-bottom-v3.png`.
