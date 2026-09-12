# Configuration

Status: user reference

Shibumi keeps Omarchy-owned shell configuration and suite bookkeeping
separate.

## Omarchy shell configuration

The active bar, plugin activation, bar layout, and Shibumi settings live in:

```text
~/.config/omarchy/shell.json
```

Shibumi settings live in the unique `plugins[]` entry whose `id` is
`hancore.shibumi.state`. That entry has `shibumiStateSchemaVersion: 1` and a
`shibumi` object with `version: 1`. State validates the canonical envelope and
normalizes its settings for presentation; invalid canonical storage makes State
unavailable rather than silently falling back. The settings include:

- V1 and V2 widget order, explicit V1 base/extra slot roles, and split
  boundaries;
- per-widget enabled state and appearance;
- bar style and semantic accent;
- V1 border, frost, shadow, and Radius 12/6 settings;
- V2 bar-border and panel/tooltip-border settings;
- workspace mode and presentation;
- G1 launcher identity;
- image and media picker styles;
- the selected thermal sensor and its persisted Celsius or Fahrenheit display;
- V1 Reactor mode, selected through **Bars → Gap Animations** from nine direct
  preview tiles;
- independent V1 and V2 layout-protection preferences.

Use the Control Center for normal changes. Manual JSON edits can be rejected or
normalized when they violate the schema. Setters accept queued changes; only
matching file readback confirms persistence. Unknown fields in the State entry,
including nested settings, survive ordinary settings writes.

### Appearance IPC

Maintainer automation must name the owning appearance profile explicitly:

```text
qs ipc -p /usr/share/omarchy/shell call shibumi-suite \
  setWidgetAppearanceForVariant G1 v2 widgetPadding '"roomy"'
```

The accepted variants are `v1` and `v2`. Variant-scoped values such as display
mode, color, border, padding, radius, and opacity are stored only below the
matching `widgets.Gx.appearance.<variant>` object. Updating one profile cannot
change the other profile.

The legacy `setWidgetAppearance` IPC method remains available only for the
group-wide `separator` boolean. It returns `variant-required` for scoped
appearance keys instead of writing an ignored top-level fallback.

### V1 layout slots

V1 keeps seven base slots on the left, one in the center, and seven on the
right. **Bars → Edit slots** exposes those positions as drop targets and allows
up to two additional slots on each outer side and one in the center (two
center positions total; default: G8 alone). The existing `+` appears in
edit mode; adding the second position does not move G8. A saved one-position
center stays unchanged until you explicitly add a slot. Only empty extra slots
can be removed. The center has no internal divider; the existing section
boundaries and split schema stay unchanged.

- `+` adds an empty slot up to nine positions per outer side or two in the center.
- Dragging a group onto an occupied slot swaps the two groups; dragging it onto
  an empty slot moves it there and leaves its former base position available.
- Base positions remain locked drop targets. Only an empty extra position can
  be removed.
- A disabled, hardware-unavailable, or responsively hidden V1 group remains a
  compact proxy while editing, so its position can still be changed.
- Outer splits remain positional. Adding or removing an outer slot changes
  its split array in the same validated transaction. Center changes preserve
  the existing split arrays and section boundaries.
- **Restore layout** returns V1 to its fixed `7 / 1 / 7` default and removes
  every extra position.

### Layout protection

The Bars page places the **Lock V1 layout** or **Lock V2 layout** toggle
between the active profile's Edit and Restore buttons. The three controls stay
side by side, while the toggle track makes the lock state directly visible.
The preferences are independent and default to off, preserving direct live
editing for existing users.

When protection is on, direct split, divider, and section-boundary clicks on
the bar are ignored outside **Edit slots** or **Edit layout**. Entering the
matching edit mode temporarily permits those changes; leaving it with Escape
or an outside click protects the layout again. Deliberate Control Center
actions such as Split all, Merge all, and Restore layout remain available.

Existing fixed-layout configurations migrate without changing group order or
split values. Order, slot roles, and split arrays are accepted as one unit; an
invalid partial layout falls back as a unit instead of combining mismatched
pieces.

Installing an additional compatible bar widget creates one stable V1 group
named from the plugin ID (for example `G:example.weather`). The group is added
to an outer extra slot by default and participates in the same drag/drop
transactions as G1–G15. A center-bound provider can instead use an explicitly
added empty center slot. Its identity never depends on installation order, so
restarts, V1/V2 switching, and multi-monitor rendering cannot renumber it.
Removing a provider directly from an extra removes that slot atomically. If
it is in a base position, automatic repair requires exactly one occupied extra
containing a fixed group. When several extras are occupied, removal is refused
without changing the layout: the saved layout has no history to identify the
correct return slot. Move the provider back into an extra, then remove it.
The Control Center checks this before starting plugin uninstall. Direct external
Omarchy commands are outside this bar-layout transaction. No saved layout is
migrated. At most two extra positions per outer side are accepted. When all
four are occupied, an outer-bound unrelated widget is rejected instead of
silently consuming the center or rendering outside V1's managed layout.

New managed V1 family replacements require single-instance providers.
An `allowMultiple` family provider is refused without changing layout, registry
enablement or family state. These checks use the actually selected clone when
one is active, not the original manifest. A valid active clone keeps its own
ID and entry settings when explicitly added as a managed family provider.
Existing explicit placements are not converted on load; unrelated multi-instance
widgets and V2 retain their allocation/removal behavior.

A newly placed family alternative is different: it uses one displaced fixed
slot, such as G6 for an Audio replacement, without consuming an extra position.
That slot keeps its saved position and split/drag identity. The alternative
keeps its own settings and standard provider surface. Only one provider can
use a fixed slot; further providers need their own positions. Existing dynamic
placements from earlier versions remain where the user put them and are not
converted automatically. Family replacement neither adds a position nor changes
the layout schema. Separately, a center-bound unrelated provider can use an
already added empty center slot; automatic plugin placement never expands the
center. Other additions retain the existing outer-slot allocation.

On narrow outputs, unassigned provider widths count toward the existing
responsive stages. Center extras also reduce the space available to the
clock/weather group, as does a widget in the optional second center slot.
This corrects the budget; it does not add an overflow menu
or new hiding priorities, and content wider than the final stage can still
exceed the available space.

## Picker routing

The **Themes & Wallpapers** choice controls which provider handles Omarchy's
authoritative menu actions:

- **Omarchy** runs the original Quattro carousel action;
- **Tanzaku** opens the Shibumi Tanzaku picker;
- **Hearthstone** opens the Shibumi Hearthstone picker.

During installation, Shibumi adds reversible overrides for Quattro's
authoritative `style.theme` and `style.background` actions to the official
user extension at `~/.config/omarchy/extensions/omarchy-menu.jsonc`. Existing
user and plugin entries remain in place, updates are idempotent, and uninstall
removes only the Shibumi-managed block. Shibumi does not patch Quattro,
Hyprland bindings, or files below `/usr/share/omarchy`.

The existing Quattro shortcuts and App Menu actions therefore open the chosen
Shibumi provider. If the quick-access service is unavailable, declines the
request, or **Omarchy** is selected, routing falls back to the native Omarchy
picker.

Switching to the stock Omarchy bar resets the Theme & Wallpaper provider to
**Omarchy** automatically. The Screenshots & Videos choice is independent and
is retained. When Shibumi is activated again, Theme & Wallpaper remains on
**Omarchy** until Tanzaku or Hearthstone is selected explicitly.

## Bar ownership

`bar.id` selects the active full-bar host. Shibumi and Omarchy retain separate
layout snapshots through the suite's continuity manager.

- **Quick** in the Control Center switches between V1, V2, and Omarchy Bar.
- **Bars** configures only the currently active Shibumi generation.
- `shibumi-suite deactivate` selects Omarchy while retaining Shibumi.
- `shibumi-suite activate` restores Shibumi and its managed layout.
- `omarchy bar reset` selects the stock host without a full defaults reset.
- `omarchy bar defaults` replaces the complete `bar` object and its layout,
  but retains canonical State service-entry settings.
- Native disable/removal of State deletes its entry. Use suite lifecycle
  commands; `uninstall --keep-settings` retains the complete dormant entry.

`bar.transparent` belongs to the stock `omarchy.bar`. Shibumi V1 and V2 remain
opaque regardless of that value and provide no transparency control. Suite
install, update, activation, deactivation, and migration preserve an existing
preference unchanged, so returning to `omarchy.bar` restores its previous
transparent or opaque presentation.

## Plugin installation and suite state

Installed plugin payloads live under:

```text
${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugins/hancore.shibumi.*/
```

Suite ownership, revision, payload hashes, and transaction recovery data live
under:

```text
${XDG_STATE_HOME:-$HOME/.local/state}/shibumi/
```

Transient cache data lives under:

```text
${XDG_CACHE_HOME:-$HOME/.cache}/shibumi/
```

Do not copy repository-relative imports or state paths into installed plugins.
Every plugin must be self-contained at runtime.

## Theme ownership

Omarchy owns the active theme and its color files. Shibumi maps those colors to
semantic presentation tokens and owns its geometry, typography, component
states, and interaction behavior.

The configured accent stores a semantic role such as `color01`, not a raw
color value. Theme changes therefore update Shibumi without rewriting personal
settings.

## Defaults

The current defaults are defined by
[`hancore.shibumi.state/ShibumiConfig.js`](../hancore.shibumi.state/ShibumiConfig.js)
and the suite profile in
[`contracts/plugin-suite-v1.json`](../contracts/plugin-suite-v1.json).
Machine-readable contracts, not prose examples, are authoritative.
