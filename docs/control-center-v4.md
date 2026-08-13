# Control Center

## Information architecture

The Control Center is a keyboard- and pointer-friendly control surface for
Shibumi and its Omarchy Quattro plugins. Its layout follows the approved
`g-refined-combo` reference while preserving the active Shibumi visual
language:

- **Quick** keeps the active bar, plugin installation, shell reload, Bars,
  Pickers, and the four Omarchy session actions immediately available. The
  compact surface beside Quick/Configure divides the Active Bar width between
  direct Health and Plugins routes. Health shows `PASS` in `color03` after a
  fully successful run, `REVIEW` in the accent color when warnings remain, and
  turns to `color01` with the error count when diagnostics contain errors. It
  stays neutral before the first report. Plugins keeps its label neutral and
  renders the abbreviated Shibumi/Omarchy/external counts in `color03`. The
  redundant bar-position statistic is omitted.
- **Configure** opens a content-matched route landing page for Bars, Icons,
  Logo, Workspaces, Pickers, Plugins, and Health. Focusing a route updates its
  semantic preview at the right; every miniature mirrors the route's current
  control language instead of using a generic placeholder. The larger landing
  previews may compare several representative choices; the compact preview in
  an editor header shows exactly one example so it cannot overlap its bounded
  stage. Selecting a route
  fades the landing graph and moves the complete route list into a compact left-hand
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
caption/regular details. Bar choices, header status, and the compact action
deck therefore share one visual grammar while keeping their different
interaction roles explicit.

Every page uses a contained semantic preview of the settings behind that route.
The preview is static until its route or represented state changes; no
decorative timer, frame loop, random preset rotation, or background animation
remains. Editor-header previews use one short opacity-and-scale transition when
the page changes. Configure landing previews switch directly without dimming
or scaling, and crossing the gap between route cards retains the last preview
instead of flashing back to Bars. Hovering a selector previews its appearance
without changing the active bar. In Shibumi, the settled Active Bar preview
retains its hover state and opens Bars; in the Omarchy return-only surface it
remains passive.

## Bar switch and Quick-action logic

The Quick landing area stacks three independent, fully rounded bar choices next
to the active-bar preview. Node connections link each choice to the active-bar
stage: the current route uses the accent color, a hovered route previews the
possible destination, and inactive routes stay muted. Connections communicate
real selection and workflow state; they are not used as decoration.
Circular ports are used at both ends of a connection; the three source ports
sit just outside the card borders instead of obscuring them. Chevrons are
reserved for real navigation. The active route derives from the active theme's
`color04` role and retains its position and shape when the theme changes.

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
inside its actual pointer hit-test bounds. Entering Configure by pointer starts
with a neutral route overview; the first route receives focus styling only
after keyboard navigation enters the route list.

Bars adds one contextual child node, `Gap Animations`, only while the V1 Bars
editor is active. It is a real detail route containing the nine direct Reactor
previews; selecting Bars returns to the compact V1 editor without changing the
selected mode. Position/Layout and the compact surface controls share one
two-column row above Bar Form. The child node disappears for V2, the stock
Omarchy bar, and every other Configure route. When the child is active, the
complete branch from the Bars node to `Gap Animations` uses the accent rather
than highlighting only the final connector.

The selector distinguishes three separate outcomes:

- **V1** selects the Shibumi split-bar presentation immediately.
- **V2** selects the Shibumi full-bar presentation immediately.
- **Omarchy Bar** starts the guarded host handoff. Switching the host bar is
  not a cosmetic toggle because it requires apply, verification, and exact
  rollback on failure.

While Omarchy Bar is active, the Shibumi launcher becomes a return-only
surface. It renders only V1, V2, and Omarchy Bar with their preview. Search,
Quick actions, Configure routes, Plugins, and stored deep links cannot be
opened, because Shibumi does not configure the stock bar. V1 and V2 remain
valid return targets.

Shibumi's mutable configuration and the independent Shibumi/Omarchy layouts
remain outside the deployed QML payload. Every successful transition retains
the inactive bar exactly as it was left. The manager uses one temporary
transaction snapshot only for rollback and removes it after success or
recovery; it does not create a growing snapshot history.

V2's selected shell form is stored independently as `v2ShellStyle`. Switching
to V1 changes only the active generation marker; returning to V2 restores the
remembered Full, Fit, Dock, or Notch form. The Quick preview renders that
effective form rather than a generic V2 bar.

V2-only per-group fill, border, radius, and padding settings do not suppress
or reposition V1's original widget-owned pills. V1 run borders retain the
integer-aligned geometry of the approved standalone V1 implementation. V1 and
V2 also persist independent bar-border choices; changing either generation no
longer changes the other generation when the user returns to it.

The Bars Configure route owns the complete bar-layout workflow without another
visible submenu. Its right-hand editor begins with the effective state
(`V1 ACTIVE`, `V2 ACTIVE`, or `OMARCHY ACTIVE`) and position. A theme-driven
visual selector previews V1 Islands and the four implemented V2 shells:
Full, Fit, Dock, and Notch. These are miniature renderings of the real shell
geometry, not decorative generic thumbnails.

The selector never mixes bar generations. With V2 live it shows only Full,
Fit, Dock, and Notch; with V1 live it shows only Islands. Switching between
V1 and V2 remains a Quick-level action, while Bars configures the active type.

The remaining controls are capability-gated in place. V1 exposes **Edit slots**,
split, merge, restore, and all nine gap-animation modes. Slot editing retains
the locked `7 / 1 / 7` base, adds at most two positions per outer side, and
renders empty or temporarily unavailable positions as compact drop targets.
Only an empty extra position exposes removal; restoring V1 removes every extra.
Compatible plugins installed from the Plugins page automatically receive a
stable plugin-derived V1 G-group in an outer extra position. That group uses
the same per-output rendering and shared split/drag state as the built-in V1
groups. Uninstall removes the group without renumbering any remaining plugin.
If all four optional V1 positions are occupied, the add action fails closed.
The bulk Split all and Merge all actions sit directly below Top/Bottom in the
V1 `Position & Layout` column, using the height beside V1's three surface rows
instead of consuming another full-width row below.
V2 exposes a single bar edit mode for adding slots and placing dividers, plus
layout restore. The active generation uses only its concise **V1 LAYOUT** or
**V2 LAYOUT** heading, without a redundant explanatory paragraph, followed by
one balanced three-control row: **Edit**, its variant-specific **Lock V1/V2
layout** toggle, and **Restore**. Edit and Restore retain the established
horizontal action style; the middle control uses a visible toggle track instead
of a lock icon. The compact Bars panel derives its fitted height from that
active page so the complete main route remains visible without scrolling.
Protection is an independent preference for each generation and both default off. When
enabled, direct split, divider, and section-boundary clicks require the
matching edit mode;
leaving edit mode restores protection without disabling deliberate Bars-page
bulk or restore actions. Bars does not duplicate slot-capacity controls in a
second editor. V2 never exposes V1 gap-animation or split-island controls. The former
Layout deep links remain compatible by resolving directly to Bars; there is no
second Layout editor in Configure, search, Icons, or Bars navigation.

V1 keeps the Islands form preview on the compact Bars page. Its nine Reactor
modes live in the Bars child route **Gap Animations** as direct `3 × 3` preview
tiles: Off/Stream/Stream 2, Reactor/Surge/Surge 2, and
Quotes/Bolt/Bolt 2. A tile never hides another mode behind repeated clicks.
Only the selected or hovered preview animates, while the actual selection is
persisted through the shared state service. Returning through the Bars node
restores the compact page; the child route is absent when V2 is active.

Accent swatches keep a neutral one-pixel border. Selection is communicated by
the QS-Dots two-pixel underline beneath the palette number or `FG`, while a
short scale transition supplies pointer hover feedback. Bar presentation
mutations preserve the active Control Center route across owner rebuilds.
During V2 layout editing, compact bar forms include empty drop-slot width in
their temporary editor surface so targets remain inside the visible bar frame.

The eight-tile Quick deck contains `+ Add plugin`, `Reload Shibumi`, `Bars`,
`Pickers`, `Screensaver`, `Lock`, `Reboot`, and `Shutdown`. Four vertically
stacked Shibumi actions sit on the left and four authoritative Omarchy session
actions on the right. A compact node-and-line spine uses the same connection
language as Configure instead of a generic divider. Only its vertical spine
and route nodes remain visible at rest; hovering an action reveals only that
action's branch to the spine. The left and right action columns align exactly
with the bar selector and Active Bar preview above. Add plugin opens the same
direct Git installer as Plugins; Bars and Pickers open their existing Configure
editors; Health is available from the compact header; reload remains owned by
the Shibumi shell.
All action tiles remain visually neutral at rest; emphasis is reserved for
pointer hover and destructive-action confirmation.
Session actions delegate to the
authoritative Omarchy commands instead of duplicating their behavior. Reboot
and Shutdown require an in-panel second activation within five seconds.
Escape first dismisses an open installer or active search state and closes the
Control Center on the next unconsumed press.

## Layout capability matrix

The Bars page selects its layout section from the active Shibumi presentation:

| Capability | Shibumi V1 | Shibumi V2 |
| --- | --- | --- |
| Split and merge islands | Yes | No |
| Animated gaps / reactor modes | Yes | No |
| Locked base slots | `7 / 1 / 7` | Yes |
| Optional outer slots | Up to two per side | Style-defined capacity |
| Persistent manual dividers | No | Yes |
| Independent direct-edit protection | Yes | Yes |
| Restore active layout | Yes | Yes |

V1 controls are not merely described as incompatible on V2: they are removed
from the V2 interaction surface. V2 slot and divider controls are likewise
absent from V1. The only Bars child route is V1-only Gap Animations; all layout,
surface, accent, form, slot, and divider controls remain on their owning
profile's compact Bars page.

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

The Plugins route uses a compact panel height sized to keep the complete
Configure navigation visible. Expanding either catalog section keeps that
height and makes the catalog scroll, avoiding unused space in the collapsed
state.

The page summary uses three equal provider rows for Shibumi, Omarchy, and
third-party plugins. All three rows share the same type, spacing, and optical
icon size. Their counts come from the same catalog model as the cards.
Activation is deliberately not described as installation.

The compact provider chip and the three summary rows intentionally count
different surfaces. The chip is a host-registry inventory: it counts every
discoverable Shibumi-managed, Omarchy first-party, and external plugin, while
excluding the currently selected bar from the hostable Omarchy total. The
summary rows are the installable widget catalog: they count only entries that
can be presented as catalog cards, omit Shibumi's fixed G1 launcher, and omit
disabled external plugins that are unavailable to the current host. A larger
chip total therefore does not indicate a catalog mismatch.

The theme-aware gloss runs once when the page opens and again only after a
provider count changes; reduced motion keeps a static highlight.

**Check plugins** below **Add plugin** first performs a bounded read-only scan of
every independently installed Git-managed plugin. A compact text line below
the button reports the result, for example `0 available`, while the tooltip
and accessibility description spell out checked, unmanaged, and failed totals
without duplicating the provider inventory above. The scan is shared across
outputs, invalidated when the plugin registry changes, and stopped when no
plugin catalog is visible.

The terminal reports the number of available updates and offers a
multi-selection. Only the selected plugins are then passed individually to
Omarchy's validating `omarchy-plugin-update` command. Omarchy remains the owner
of changed-code review: long diffs use its normal pager, which is exited with
`q` before the final confirmation. Non-Git plugin directories are reported as
not automatically checkable rather than treated as current. Shibumi does not
silently update third-party code.

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

The plugin catalog is generation-independent. Temperature, GPU, and Storage
use the fixed G16-G18 groups in V2 and the same persistent extension-slot
mechanism as other added bar plugins in V1. Their V1 placement therefore does
not duplicate or overwrite their V2 layout. When all four V1 extension slots
are occupied, activation stays discoverable and reports the concrete capacity
constraint instead of hiding the plugin or failing silently.

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
  active, occupied, and empty state before it is applied. V1 and V2 expose the
  same Default, Numbers, Magic, Kanji, Frame (persisted as `rings`), and Aurora
  choices. V1's Radius 12/6 setting affects the Numbers and Frame marker
  geometry only; V2 keeps its fixed marker radii. The shared Workspaces route
  uses the same content-matched compact panel height as Pickers, without a
  redundant explanation below the self-describing marker previews.
- **Pickers** exclusively owns the theme/wallpaper browser and the
  screenshot/video browser. Themes and wallpapers default to Omarchy's
  carousel, with Tanzaku and Hearthstone as the two Shibumi alternatives.
  Screenshots and videos retain Tanzaku, Hearthstone, and Carousel. The same
  picker routes, choices, and persisted selections are used by V1 and V2. The
  shared Pickers route uses a content-matched compact panel height instead of
  inheriting the taller generic Configure surface.
- **Bars** owns the active bar's supported surface and accent settings. V1
  exposes border, frost, shadow, and Radius 12/6. V2 exposes Bar Border and
  Panel + Tooltip; its fixed V2 radii and unsupported V1 effects are not
  presented as editable settings. Both generations expose the eight palette
  roles supported by the accepted references: `color01` through `color07` and
  foreground. The same tokens are consumed by both the V1 and V2 renderers.
- **Logo** owns launcher wordmark/icon format and visual choices. Its selection
  is authoritative in V1 and V2: choosing a wordmark or icon immediately sets
  that launcher presentation, independent of stored per-widget appearance.
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
  capability context; the Launcher omits the generic Presentation control
  because Logo owns its identity. Split, gap, slot, and bar-divider ownership
  remains in Bars and is not duplicated here. Icons alone uses a shorter semantic page
  preview, which remains centered and disappears during focused editing. In
  each overview, `RESET V1 DEFAULTS` or `RESET V2 DEFAULTS` follows
  `ACTIVE WIDGETS |` in the same header typography. It uses semantic
  `color03`; its confirmation changes to `color01`. It requires a second
  confirmation click, resets every official widget appearance for the active
  generation in one transaction, and preserves the other generation's
  appearance, launcher identity, activation, placement, splits, dividers, and
  nonvisual settings. Active/inactive transfer controls use a full-height,
  softly tonal tile-edge strip without an internal divider. Hover and keyboard
  focus promote the strip and arrow with semantic `color03`.

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
24-plugin self-containment checks, suite manifest contract, and Quattro
contract regression passed on 2026-07-30 on the validation system against Omarchy
`4.0.0.r1458.gfa6b5fc-1`. Runtime screenshots separately verify Quick,
Configure, search, V1 layout, and V2 layout states.

The real Wayland lifecycle test on the validation system also completed install, switch to
the stock Omarchy bar, update while preserving that host, Shibumi reactivation,
and uninstall. It used an isolated temporary home and did not mutate the live
user configuration.

Evidence:

- [Quick mode](mockups/control-center-refined-quick.png)
- [Configure mode](mockups/control-center-refined-configure.png)
- [Settings search](mockups/control-center-refined-search.png)
- [V1 layout capabilities](mockups/control-center-refined-v1-layout.png)
- [V2 layout capabilities](mockups/control-center-refined-v2-layout.png)

## Remaining acceptance

The following remain final hardware or credential gates and are not closed by
the single-output live render:

- physical second monitor, mixed scale, and hotplug;
- Enterprise WLAN with real credentials;
- real Bluetooth pair/connect/disconnect/forget and Bluetooth audio;
- installation of a reviewed disposable third-party plugin through the visible
  confirmation flow, followed by removal and state restoration.
