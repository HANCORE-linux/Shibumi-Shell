# Control Center

## Information architecture

The Control Center is a keyboard- and pointer-friendly control surface for
Shibumi and its Omarchy Quattro plugins. Its layout follows the approved
`g-refined-combo` reference while preserving the active Shibumi visual
language:

- **Quick** keeps the active bar, five direct bar-widget visibility controls,
  widget installation, and shell reload immediately available. The compact
  header beside Quick/Configure links to Plugins with its active/available
  count and shows the passive Shibumi/Omarchy/external plugin breakdown. The
  redundant bar-position statistic is omitted.
- **Configure** opens a route landing page for Bars, Icons, Logo, Workspaces,
  Pickers, Plugins, and Health. Focusing a route updates its
  semantic preview at the right. Selecting a route fades the
  landing graph and moves the complete route list into a compact left-hand
  master column while revealing the matching editor on the right. Every route
  remains visible and switches the right-hand editor directly; no nested menu
  or isolated back tile is created. Selecting the top Configure mode returns
  to the landing graph. Ambiguous chevrons are not used.
- Quick and Configure use a stable panel height so their larger landing
  compositions never expose partially clipped controls.
- Search remains available in both modes. `Ctrl+K` focuses it, and results
  open either the matching settings page or the Plugins registry. The global
  field and the Plugins field use the same predictive-search engine: partial
  multi-word fragments are matched directly across their metadata, with
  ordered-subsequence matching as a fallback. A maximum of four ranked
  suggestions appears with an inline ghost preview. Up and Down select a
  suggestion; Tab, Enter, or Right Arrow at the end of the query accepts it.
  Escape is staged: the first press closes visible suggestions, the next
  clears and unfocuses the field, and a following panel-level Escape closes
  the Control Center. A pointer click outside the global field and its
  suggestion surface closes suggestions and removes focus without clearing the
  current query or consuming the clicked control's action. A passive tap
  observer performs this dismissal; pointer events are never propagated into
  the panel's outer close layer.
- Predictive search shares one visual and interaction treatment in both
  contexts. The global settings search and Plugins search use the same
  four-result catalog surface. Its opaque background, neutral border, radius,
  dividers, and hover fill use the surrounding control tokens. Opening either
  suggestion list reserves its vertical space and moves the following content
  down instead of covering it. Both fields retain a neutral one-pixel outline;
  no extra focus underline or full-border accent is drawn.
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

The Plugins filter uses one shared caption size, medium weight, and vertical
text box for `FILTER` and every provider option. It can show all, active,
Shibumi, Omarchy Quattro, or third-party entries. Selection changes color and
underline only; it never shifts the option baseline or changes its perceived
type size. Entering a query in the normal catalog visibly changes an `Active`
filter to `All`, allowing inactive but style-compatible plugins to be found.
The Favorites route remains intentionally scoped to saved plugins.

Quick uses the same card anatomy throughout: themed fill, border and radius;
caption/demi-bold labels; body-small/demi-bold values and actions; and
caption/regular details. Bar choices, widget visibility tiles, header status,
and footer actions therefore share one visual grammar while keeping their
different interaction roles explicit.

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
from Configure, search, Icons, and Bars navigation.

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

## Plugins and Icons

The **Plugins** page is the only bar-plugin registry. It enables, disables, and
installs compatible bar plugins; it does not expose visual editing. V1 hides
V2-only Shibumi groups, and V2 exposes them when that style is active.
Third-party and stock Omarchy plugins retain their original rendering
contract.

Active plugins appear before available plugins. A provider switch is grouped
as one relationship: the selected Omarchy alternative is marked `ACTIVE` and
the corresponding Shibumi widget is marked `REPLACED` with the replacing
provider named in full. `ACTIVE` uses the current theme's `color03`;
`REPLACED` uses the theme's red `color01`, so the relationship remains
semantically readable across themes. The switch happens immediately without
an additional confirmation dialog. A non-modal seven-second status banner
explains which widget was hidden to prevent duplicates and offers `UNDO`;
restoring the Shibumi tile removes its active alternatives through the same
provider-family contract. `UNDO` and its two-pixel linear deadline indicator
use theme `color01`. The indicator drains over seven seconds and pauses while
the banner is hovered or the Undo action has keyboard focus. A new provider
mutation replaces the previous banner, so only the latest change is reversible
and statuses never stack. Remove confirmation remains exclusive and clears an
existing Undo state. `Add plugin` remains in the compact page header rather
than consuming a catalog tile. It opens the Git installer directly; it never
repeats the installed-plugin catalog. The repository field initially uses the
neutral input border. A syntactically valid HTTPS, SSH, or `git@` repository
changes that border to theme `color03` and enables the risk-confirmation
control. Before validation the confirmation remains visibly disabled. After
the explicit risk acknowledgement, the install action delegates to Omarchy's
plugin command. URL validation is syntactic and does not claim that the remote
repository exists before Omarchy performs the installation.

The provider filter is followed by one fixed-height interaction slot. In its
  idle state it searches plugin names, IDs, providers, authors, categories,
  capabilities, and manifest tags. Free-form descriptions are searched only
  when those primary fields produce no match, preventing relational wording
  such as `Bluetooth audio owner` from polluting a direct Audio query. Its
  matching, ranked suggestions, inline
completion, keyboard navigation, acceptance keys, and staged Escape behavior
are identical to the global settings search. The global field searches both
Configure routes and the same plugin metadata. During a mutation the Plugins
slot shows status and the hover-visible `UNDO` action in the same geometry.
Provider updates therefore never insert a new row or push the catalog
downward. Active and available sections expose counts and can be expanded
independently. Both start collapsed so a large catalog does not instantiate or
display every card on page open. A search temporarily reveals matching entries
regardless of section state.

The page summary reports installed and available plugin counts by actual
provider family. It never labels an active third-party or Omarchy plugin as a
Shibumi plugin merely because it appears in the same catalog.

Every plugin card, including a card revealed by search, exposes a star action.
Starred plugin IDs are persisted in `bar.shibumi.plugins.favorites`. The
connected **Favorites** child route below Plugins scopes the same provider
filter, predictive search, activation, and removal controls to that saved set;
selecting Plugins again returns to the complete catalog.

Only independently installed user plugins expose the trash action. Quattro
built-ins and Shibumi suite-managed plugins cannot be removed individually.
Deletion requires a second inline `REMOVE` action, then delegates to
`omarchy plugin remove <id> --yes`; arguments are passed as a process array,
the catalog is rescanned on success, and failures retain the installed plugin.
Disabling remains a separate reversible toggle.

The **Icons** page is the only per-widget visual editor. It derives its list
from the active V1 or V2 layout and immediately closes a detail view when its
widget is not part of the newly selected style. Shared presentation controls
such as display mode, surface, color, content tone, shape, spacing, opacity,
and outline width are edited here. Generation-specific layout controls remain
under Bars and are never offered through a second cross-style editor.

## Workspaces and pickers

Workspace navigation and picker presentation are first-class Configure routes,
not secondary sections inside Icons:

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
- **Icons** owns per-widget icon/content modes plus their surfaces, colors,
  shape, spacing, and opacity. It follows the active bar's canonical
  left/center/right layout order and lists only enabled groups that implement
  the Shibumi appearance contract. Provider filters do not appear in this
  editor; unsupported stock or third-party widgets remain in Plugins. The
  selected widget's live preview shares the inspector header, content and
  surface choices use visual samples, and the surface palette uses the same
  neutral-border, underline-selection, and hover-motion contract as Bars.
  Regular choices use compact radio rows without a palette underline. Surface
  exposes None, Fill, Outline, and Both directly; Fill, Outline, and Both carry
  a silhouette while None deliberately has no decorative symbol. The 0.5 px,
  1 px, 1.5 px, and 2 px outline widths remain simultaneously visible beside
  it. Fill shows one
  Fill Color palette, Outline shows one Outline Color palette, and Both shows
  both independent palettes. `Auto` retains the relevant themed default.
  Content and Content Tone form a second equal-height row: Content exposes
  Icon + text, Icon only, and Text only as radio choices, while Tone exposes
  Auto, BG, and FG in the same form. Content spans the first two columns;
  Content Tone occupies the third so its left edge aligns exactly with
  Opacity.
  Surface Color remains directly above that row. The integrated widget preview
  centers its icon and label independently on one shared vertical axis.
  Both bar generations consume the independent fill and outline values. The
  legacy coupled-outline flag remains read-compatible, but every new edit
  persists the dedicated outline color.
  Opacity sits directly to the right of Outline, so Surface, Outline, and
  Opacity form one compact three-column group with equal-height hover rows.
  Geometry communicates shape through the
  actual button silhouette and inner spacing through a progressively larger
  frame around a fixed content mark. The separate Finish section is omitted;
  100%, 80%, 60%, and 40% remain direct Opacity radio choices whose labels
  preview the respective strength.
  Content, Surface, Shape, and Inner Space share one control height, caption
  size, selection weight, border strength, and hover/active language; only a
  Shape button's radius intentionally changes. This preserves the compact
  QS-Dots control rhythm without relying on unexplained text-only choices.
  Its first state is a compact four-column active-widget grid. A small state
  point marks widgets with stored appearance changes, using their selected
  Surface Color when available and the Shibumi accent for non-color changes.
  Activation and V2-divider state do not trigger that point. Selecting one
  widget hides every other widget and opens a full-width editor; an explicit
  `ALL WIDGETS` connection node returns to the grid without a chevron or nested
  menu. The focused editor exposes every applicable shared visual setting
  without a collapsed `More` section or a second scroll surface. Surface color
  and outline width remain visible but disabled when the selected surface
  cannot consume them. A V1/V2 Active label communicates the current
  capability context; split, gap, slot, and bar-divider ownership remains in
  Bars and is not duplicated here. Icons alone uses a shorter semantic page
  preview, which disappears during focused editing.

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
