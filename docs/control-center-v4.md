# Control Center

## Information architecture

The Control Center is a keyboard- and pointer-friendly control surface for
Shibumi and its Omarchy Quattro plugins. Its layout follows the approved
`g-refined-combo` reference while preserving the active Shibumi visual
language:

- **Quick** keeps the active bar, five direct bar-widget visibility controls,
  widget installation, and shell reload immediately available. The compact
  header beside Quick/Configure links to Widgets with its active/available
  count and shows the passive Shibumi/Omarchy/external plugin breakdown. The
  redundant bar-position statistic is omitted.
- **Configure** opens a route landing page for Bars, Widgets, Workspaces,
  Pickers, Logo, Appearance, and Advanced. Focusing a route updates its
  semantic preview at the right. Selecting a route fades the
  landing graph and moves the complete route list into a compact left-hand
  master column while revealing the matching editor on the right. Every route
  remains visible and switches the right-hand editor directly; no nested menu
  or isolated back tile is created. Selecting the top Configure mode returns
  to the landing graph. Ambiguous chevrons are not used.
- Quick and Configure use a stable panel height so their larger landing
  compositions never expose partially clipped controls.
- Search remains available in both modes. `Ctrl+K` focuses it, Escape clears
  it, and results open either the matching page or a native widget editor.
- Groups use progressive disclosure. The active page remains visible when its
  group is collapsed.

A navigation mode, page, state, or section is named only once at each level.
Eyebrows may add context, but never repeat the selected mode or the page title.
Redundant orientation labels such as a second `CONFIGURE` beneath the active
Configure control are excluded.

The header breadcrumb, sync state, close action, header divider, search field,
and content workspace share the same 20-unit left and right alignment axes.
The header never draws a wider independent underline.

The UI avoids nested cards. Hairline borders establish control boundaries,
one-pixel dividers establish hierarchy, and the active theme accent is reserved
for selection, status, focus, and the primary action.

Typography uses the host theme's menu family and four reusable roles:
caption-sized uppercase labels with demi-bold weight, regular body copy,
demi-bold values and navigation selection, and a single 24-pixel-equivalent
demi-bold page-title tier. Micro-sized one-off labels and unrelated font
families are avoided.

Every vertically scrollable Control Center surface exposes the same slim,
theme-driven side rail. It appears only when content exceeds the viewport,
uses a two-pixel thumb that grows to three pixels on hover or drag, and keeps a
wider invisible pointer target. Repeated preview and module cards use compact
geometry to reduce unnecessary scrolling while retaining readable labels and
usable pointer targets.

The Widgets source filter uses one shared caption size, medium weight, and
vertical text box for `SOURCE` and every provider option. Selection changes
color and underline only; it never shifts the option baseline or changes its
perceived type size.

Quick uses the same card anatomy throughout: themed fill, border and radius;
caption/demi-bold labels; body-small/demi-bold values and actions; and
caption/regular details. Bar choices, widget visibility tiles, header status,
and footer actions therefore share one visual grammar while keeping their
different interaction roles explicit. The Plugins header status remains
non-interactive until the Control Center has a registry page that represents
all plugins, rather than only bar-widget modules.

Every page uses a contained semantic preview of the settings behind that route.
The preview is static until its route or represented state changes; no
decorative timer, frame loop, random preset rotation, or background animation
remains. A route change uses one short opacity-and-scale transition so the image
changes smoothly without continuously consuming rendering time. The Quick
Active Bar preview remains the only interactive preview and opens Bars settings.

## Bar and widget-shortcut logic

The Quick landing area stacks three independent, fully rounded bar choices next
to the active-bar preview. Node connections link each choice to the active-bar
stage: the current route uses the accent color, a hovered route previews the
possible destination, and inactive routes stay muted. Connections communicate
real selection and workflow state; they are not used as decoration.
Circular ports are used at both ends of a connection; the three source ports
sit just outside the card borders instead of obscuring them. Chevrons are
reserved for real navigation. The five widget-visibility status dots derive
from the active theme's `color04` role and retain their position/shape when the
theme changes.

The Configure landing graph uses the same connection geometry as Quick:
source ports sit six spacing units outside each card border, every source has
the same 3.6-pixel-equivalent radius, inactive ports remain neutral, and the
shared destination keeps the 4.4-pixel-equivalent active radius. Those ports
explain the landing relationship only. In an editor, the complete route list
becomes persistent master navigation and the graph is hidden. A slim vertical
route line sits outside the unchanged card axis, with one 3.6-unit circular
node and a short card connector per Configure area. The active node uses the
accent; inactive nodes remain neutral. The landing introduction collapses
structurally when the master column opens, so every visible route remains
inside its actual pointer hit-test bounds.

Bars adds one contextual child node, `Surface & Color`, only while the Bars
editor and a Shibumi bar are active. It is an in-page anchor rather than a
nested settings page: selecting it scrolls the existing editor to the
version-gated accent/detail block after Bar Form, while selecting Bars returns
to the top of the same editor. Position and the compact border controls share
one two-column row above Bar Form. The child node disappears for the stock
Omarchy bar and every other Configure route. When the child is active, the
complete branch from the Bars node to `Surface & Color` uses the accent rather
than highlighting only the final connector. The shared scrollspy activation
line is the upper two thirds of the visible detail viewport, so a child route
activates while its section enters focus rather than only at the scroll limit.

The selector distinguishes three separate outcomes:

- **Shibumi V1** selects the V1 presentation immediately; selecting its
  already-active card opens Bars.
- **Shibumi V2** selects the V2 presentation immediately; selecting its
  already-active card or the Active Bar stage opens Bars.
- **Omarchy** opens the guarded Bars workflow. Switching the host bar is not
  presented as an instant cosmetic toggle because it requires snapshot,
  apply, and verification steps.

The Bars Configure route owns the complete bar-layout workflow without another
visible submenu. Its right-hand editor begins with the effective state
(`V1 ACTIVE`, `V2 ACTIVE`, or `OMARCHY ACTIVE`) and position. A theme-driven
visual selector previews V1 Islands and the four implemented V2 shells:
Full, Fit, Dock, and Notch. These are miniature renderings of the real shell
geometry, not decorative generic thumbnails.

The selector never mixes bar generations. With V2 live it shows only Full,
Fit, Dock, and Notch; with V1 live it shows only Islands. Switching between
V1 and V2 remains a Quick-level action, while Bars configures the active type.

The remaining controls are capability-gated in place. V1 exposes split, merge,
restore, and all nine gap-animation modes. V2 exposes divider editing, layout
restore, and left/center/right slot capacity with valid minimum and maximum
limits. V2 never exposes V1 gap-animation or split-island controls. The former
Layout route remains only as an internal compatibility target and is absent
from Configure, search, Appearance, and Bars navigation.

Accent swatches keep a neutral one-pixel border. Selection is communicated by
the QS-Dots two-pixel underline beneath the palette number or `FG`, while a
short scale transition supplies pointer hover feedback. Bar presentation
mutations preserve the active Control Center route across owner rebuilds.
During V2 layout editing, compact bar forms include empty drop-slot width in
their temporary editor surface so targets remain inside the visible bar frame.

The Bars page continues that visual grammar with labeled circular
`Snapshot → Apply → Verify` nodes. During a handoff the current stage is
accented, completed stages remain visible, and both shell cards expose the
route endpoints.

The five tiles show or hide their matching Shibumi bar widgets through the
state-service group contract. They never disable Wi-Fi or Bluetooth, mute
audio, change brightness, or cycle the power profile. Device and service values
remain read-only context beneath the explicit `Shown` or `Hidden` state.

## Layout capability matrix

The Bars page selects its layout section from the active Shibumi presentation:

| Capability | Shibumi V1 | Shibumi V2 |
| --- | --- | --- |
| Split and merge islands | Yes | No |
| Animated gaps / reactor modes | Yes | No |
| Fixed left, center, and right slots | No | Yes |
| Persistent manual dividers | No | Yes |
| Restore active layout | Yes | Yes |

V1 controls are not merely described as incompatible on V2: they are removed
from the V2 interaction surface. V2 slot and divider controls are likewise
absent from V1. The capability boundary is visible within Bars without a
second navigation level.

## Widget editor

The Widgets page separates activation from configuration. The switch at the
end of a row enables or disables the widget; selecting a native Shibumi row
opens its editor.

The editor labels the scope of every control:

- **Both · V1 + V2** contains shared widget presentation such as display mode,
  surface, color, content tone, shape, spacing, opacity, and outline width.
- **V1 only** links to split-island and animated-gap controls. Those are bar
  layout properties, not widget properties.
- **V2 only** owns the persistent divider after the selected widget group and
  the direct divider editor on the bar. These controls are disabled until a V2
  shell style is active.

The drill-down keeps Widgets highlighted in the navigation rail and returns to
the same catalog. Third-party and stock Omarchy widgets retain their original
rendering contract and do not expose Shibumi-only appearance controls.

## Workspaces and pickers

Workspace navigation and picker presentation are first-class Configure routes,
not secondary sections inside Appearance:

- **Workspaces** exclusively owns the visible-workspace count and marker style.
  Every marker choice is shown as a themed three-workspace preview with an
  active, occupied, and empty state before it is applied. V1 exposes the QS
  Rise styles Default, Numbers, and Magic. V2 additionally exposes Kanji,
  Frame (persisted as `rings`), and Aurora.
- **Pickers** exclusively owns the theme/wallpaper browser and the
  screenshot/video browser. Themes and wallpapers default to Omarchy's
  carousel, with Tanzaku and Hearthstone as the two Shibumi alternatives.
  Screenshots and videos retain Tanzaku, Hearthstone, and Carousel.
- **Bars** owns the active bar's supported surface and accent settings. V1
  exposes border, frost, shadow, and Radius 12/6. V2 exposes Bar Border and
  Panel + Tooltip; its fixed V2 radii and unsupported V1 effects are not
  presented as editable settings;
  the same tokens are consumed by both the V1 and V2 renderers.
- **Logo** owns launcher wordmark/icon format and visual choices.
- **Appearance** owns only per-widget surfaces, colors, shape, spacing, and
  opacity.

The Workspaces and Pickers controls are not repeated on another page. Quick
may still expose whether the Workspaces widget is shown; that is widget
visibility, not workspace presentation.

## Control language

The Control Center consumes the same `VisualTokens` as the active Shibumi bar
and its other panels:

- the panel surface follows `panelBackground`, derived from the current
  Omarchy `colors.toml` background;
- the outer border follows `panelBorder` and the live `panelBorder` setting;
- the outer radius follows `panelRadius`, including the different V1 and V2
  geometry;
- controls follow the live `tileRadius`, separator, idle, hover, active, text,
  muted-text, and accent roles;
- adjacent segmented controls share one rounded outer border and clipped
  one-pixel internal separators instead of drawing doubled seams;
- circular indicators, toggle knobs, and other semantic geometry retain their
  appropriate circular form.

No Control Center product color, font family, border color, or radius is
hard-coded. Theme changes propagate through Commons and Shibumi
`VisualTokens` without a separate Control Center palette.

## Quattro plugin contract

The control center consumes the injected Quattro `PluginRegistry` directly.
It does not scan plugin directories or rewrite `shell.json` itself.

- `installedPlugins` supplies manifests and source metadata.
- `isEnabled(id)` supplies effective activation state.
- `setEnabled(id, value)` performs bar/plugin placement mutations.
- `rescan()` refreshes the catalog after installation.
- `omarchy plugin add <git-url> --yes` owns clone staging and manifest
  validation.

Git URLs are passed as a `Process.command` argument array, never interpolated
into a shell command. The UI only accepts HTTPS, SSH, and `git@` forms. Because
third-party plugins execute unsandboxed inside the long-lived Omarchy shell,
the user must confirm the risk explicitly before the command may start.

The compatibility label is deliberately conservative:

- **Native**: manifest declares `x-shibumi.suiteId = hancore.shibumi`;
- **Adaptive**: a non-Shibumi `bar-widget` receives host bar/tooltip chrome;
- **Original**: panels and other plugins retain their own visible surface.

## Runtime evidence

The focused offscreen regression, complete repository contract regression,
25-plugin self-containment checks, suite manifest contract, and Quattro
contract regression passed on 2026-07-30 on Machine2 against Omarchy
`4.0.0.r1458.gfa6b5fc-1`. Runtime screenshots separately verify Quick,
Configure, search, V1 layout, and V2 layout states.

The real Wayland lifecycle test on Machine2 also completed install, switch to
the stock Omarchy bar, update while preserving that host, Shibumi reactivation,
and uninstall. It used an isolated temporary home and did not mutate the live
user configuration.

Evidence:

- [Quick mode](mockups/control-center-refined-quick-machine2.png)
- [Configure mode](mockups/control-center-refined-configure-machine2.png)
- [Settings search](mockups/control-center-refined-search-machine2.png)
- [V1 layout capabilities](mockups/control-center-refined-v1-layout-machine2.png)
- [V2 layout capabilities](mockups/control-center-refined-v2-layout-machine2.png)

## Remaining acceptance

The following remain final hardware or credential gates and are not closed by
the single-output live render:

- physical second monitor, mixed scale, and hotplug;
- Enterprise WLAN with real credentials;
- real Bluetooth pair/connect/disconnect/forget and Bluetooth audio;
- installation of a reviewed disposable third-party plugin through the visible
  confirmation flow, followed by removal and state restoration.
