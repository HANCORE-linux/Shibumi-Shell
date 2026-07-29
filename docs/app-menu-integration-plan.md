# Shibumi App Menu integration plan

> **Document status: Normative supporting contract.** This document defines
> App Menu ownership and its separation from G1. `../ARCHITECTURE.md` overrides
> it if a product-wide premise changes.

## Decision

The Shibumi App Menu belongs in this repository as the independent
`hancore.shibumi.menu` plugin. It is not a child or additional kind of
`hancore.shibumi.bar`. The same menu must be summonable with any Shibumi or
compatible Omarchy bar without copying its data model, windows, or processes.

Its target manifest declares only its own runtime boundary:

```json
{
  "id": "hancore.shibumi.menu",
  "kinds": ["menu", "service"],
  "keepLoaded": true,
  "entryPoints": {
    "menu": "Menu.qml",
    "service": "Service.qml"
  }
}
```

The Shibumi bundle installer stages and enables this plugin explicitly. It
remains in the same repository, requires no second `ShellRoot`, and is not
implicitly enabled merely because a Shibumi bar is selected.

## Source Assessment

`Quickshell-Dots/plugins/omarchy-menu/` is an interaction and visual reference,
not code to copy wholesale. Its useful product decisions include:

- one navigable Omarchy command tree;
- an integrated application route;
- keyboard and pointer navigation;
- favorites and hidden applications;
- Shibumi presentation controls.

Its current implementation cannot be used as a Quattro plugin because it:

- owns two V1-specific `PanelWindow` implementations;
- mutates V1 root properties directly;
- calls the old dash-separated `omarchy-menu` routes;
- references a missing `load-apps.py` helper;
- stores product configuration in V1 cache files;
- contains obsolete Mako, Walker, Waybar, and SwayOSD setup/update actions;
- duplicates menu data that Quattro now owns in JSONC.

## Runtime Ownership

### Host

Omarchy Shell owns discovery, enabling, summon/hide/toggle routing, plugin
loading, active-output context, and rollback to the official menu.

### AppMenuService

One service instance owns:

- the normalized application index from `DesktopEntries.applications`;
- search terms and stable sorting;
- validated favorite and hidden desktop-entry ids;
- menu presentation settings from versioned Shibumi configuration;
- the parsed current Omarchy JSONC menu model;
- refresh/revision state shared by every menu view.

No Python application scan or per-open process is allowed.

### Menu view

`menu/Menu.qml` owns presentation and short-lived interaction state only:

- focused output and window mapping;
- current route, query, selection, and navigation stack;
- keyboard/pointer handling;
- row rendering and Shibumi motion;
- calls into the service and narrow action adapter.

It implements the Quattro `open(payloadJson)`, `close()`, and `refresh()`
lifecycle. It does not create another shell root.

### G1 Control Center

G1 is not an App Menu launcher. The wordmark widget and Shibumi settings panel
belong to `hancore.shibumi.control-center`. App Menu invocation is an independent
menu lifecycle action, normally reached through an explicitly configured
Omarchy shortcut or another deliberate menu button.

## Data Contracts

### Applications

Use Quickshell `DesktopEntries.applications.values`, the same native source used
by Quattro's launcher. Launch by validated desktop id through `gtk-launch` or a
host adapter. Favorites and hidden entries use stable desktop ids, not display
names.

### Omarchy actions

Read the current Quattro sources:

- `$OMARCHY_PATH/default/omarchy/omarchy-menu.jsonc`;
- `~/.config/omarchy/extensions/omarchy-menu.jsonc`.

Normalize the current dotted route ids and merge user overrides using Quattro's
documented semantics. Do not preserve the prototype's stale dash-separated
route table. Shibumi-only actions live in a small separate extension model and
must use fixed, reviewed adapter calls.

### Configuration

App Menu settings use a versioned plugin-owned namespace in host-managed
configuration, not `bar.shibumi` and not files in `~/.cache`:

```text
hancore.shibumi.menu.version
hancore.shibumi.menu.favorites
hancore.shibumi.menu.hidden
hancore.shibumi.menu.presentation
```

Malformed values fail to compiled defaults. Loading the plugin never rewrites
configuration.

## Compatibility And Fallback

- The official `omarchy.menu` remains installed and summonable as a recovery
  path.
- The Shibumi installer enables the menu as an explicit bundle member;
  selecting or switching a Shibumi bar does not change menu ownership.
- Disabling or removing the Shibumi menu returns shortcut ownership to the
  documented official-menu recovery path without deleting Omarchy menu files.
- Shibumi does not silently replace global keybindings. Documentation may offer
  the explicit summon command after the menu is stable.
- V1's standalone menu remains unchanged; this is a Shibumi-native port.

## Implementation Slices

1. **Foundation implemented in the prototype:** migrate the existing menu and
   service lifecycle into the independent manifest. Prove host summon, hide,
   service resolution, coexistence, and fallback without a bar dependency.
2. **Application data complete locally:** add the `DesktopEntries` application model with deterministic search,
   favorites, hidden entries, and no subprocess polling.
3. **Command runtime complete locally:** parse and merge current Omarchy JSONC
   sources; evaluate `when` and `checked` expressions in one timeout-bounded,
   fail-closed batch; load only the reviewed `fonts` and `power-profiles`
   providers through one queued worker; and dispatch applications/actions
   through narrow adapters. No recurring process or timer is introduced.
4. **Visible workflow complete locally:** port the Shibumi menu presentation,
   command/application navigation, search, keyboard and pointer control,
   favorites, hidden-app editing, provider states, and screen-local lazy
   surface onto the native lifecycle. Obsolete V1 actions are not included.
5. **Invocation routing:** preserve invoking-screen context through the native
   menu lifecycle. Shortcut integration is explicit and reversible; it does
   not make G1 an App Menu button.
6. **Presentation complete locally:** retain the inline App Menu settings over the
   shared configuration contract, preserve the approved V1 default, gradient,
   and glide selection modes, and render off/search/full wallpaper backgrounds
   from Quattro's existing `omarchy.background` service without another watcher
   or process. Bar, widget, split, Reactor, and appearance settings move to the
   separate G1 Control Center rather than remaining in the App Menu.

The foundation entry point is intentionally non-visual. It must not expose an
unfinished menu merely because the manifest contract is active.

## Acceptance Gates

- first open and warm reopen on real Wayland;
- keyboard navigation, search, back, escape, and focus restoration;
- application launch, favorite, hide, and invalid desktop-id handling;
- current Quattro action tree and user extension merge;
- top and bottom bar positions;
- two-output active-screen ownership and hot-unplug while open;
- no second menu window, service, or application scanner after close/reload;
- no recurring process while closed;
- bounded PSS change across 20 open/close cycles;
- official menu still summons after Shibumi is disabled;
- plugin update and rollback preserve valid menu configuration.

## Local Visible-Workflow Evidence

Validated offscreen on 2026-07-16 without installing or selecting the private
plugin:

- command and application routes share one controller and one search field;
- descendant command search, back, escape, page movement, pointer selection,
  application launch, and action dispatch are covered by model/runtime tests;
- favorites and hidden desktop ids persist only through the host configuration
  mutation API;
- the visible card uses the V1 260px base width and 38/42px command/app row
  rhythm while consuming Quattro `Color`, `Style`, `Border`, and `Ui` tokens;
- top, bottom, and constrained-screen card geometry is pure and
  regression-tested; left/right calculations remain defensive host handling,
  not a V1 parity or release requirement;
- an invalid or missing target screen cannot expose the Wayland surface;
- open creates the surface and close destroys it; cold open, close, warm reopen,
  and second close are verified without a `PanelWindow` backend;
- provider loading, failure, and empty-search states have explicit UI text;
- 20 consecutive full contract suites passed after process-exit hardening and
  each suite left its dedicated temporary root empty.

Not yet accepted:

- the actual `MenuSurface.qml` on Wayland;
- visual comparison of the settings, selection, wallpaper, and 60%, 80%, and
  100% scale modes;
- top and bottom on a real output;
- invocation, hot-unplug, and focus ownership across two outputs;
- 20-cycle closed-PSS measurement;
- final placement of the menu controls in the future shared control-center
  workflow; the underlying settings contract and inline UI are complete.

## Notifications And OSD

They are separate projects, not App Menu subfeatures.

The first notification step may add Shibumi views over Quattro's existing
`omarchy.notifications` service. It must not instantiate another
`NotificationServer`.

The official `omarchy.osd` remains active. Replacing it requires an upstream
exclusive-owner selection contract because Quattro currently routes feedback
to that first-party plugin. Adding a second OSD would create duplicate visual
feedback and is not accepted.
