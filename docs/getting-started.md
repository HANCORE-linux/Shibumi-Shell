# Get started

Status: user reference

Shibumi is a native bar and plugin suite for Omarchy Quattro. It provides the
approved QS Rise V1 and V2 layouts, controls, widgets, panels, and interaction
model without replacing Omarchy's plugin system or starting a second
Quickshell process.

Shibumi is an independent third-party project. It is not an official Omarchy
product, official Omarchy bar, or Basecamp-maintained plugin.

## Open the Control Center

Select the **Shibumi** wordmark in the bar. The Control Center keeps the
supported shell settings in seven focused pages:

- **Bars** switches bar hosts and configures the active bar layout and surface.
- **Icons** controls the icon/content mode and visual presentation of widgets
  active in the current bar layout.
- **Logo** selects the launcher wordmark or icon.
- **Workspaces** controls workspace count and marker style.
- **Pickers** selects the theme, wallpaper, screenshot, and video browser.
- **Widgets** enables, configures, and places compatible bar widgets.
- **Advanced** contains maintenance and session actions.

## Switch bar hosts

Use **Bars** to move between Shibumi and the stock Omarchy bar. Each host keeps
its own layout, and both return paths remain available after the switch.

The suite also provides transactional activate and deactivate commands for
recovery or terminal use. See [install and update](install.md#switch-bar-hosts)
for those commands and the difference between an Omarchy bar reset and a full
defaults reset.

## Customize Shibumi

The Control Center exposes the supported product settings:

- switch between the V1 and V2-derived shell styles;
- place the bar at the top or bottom and select its shell shape;
- choose a semantic accent from the active Omarchy theme;
- configure V1 border, frost, shadow, and Radius 12/6 or the V2 bar and
  panel/tooltip borders;
- choose workspace presentation and picker style;
- set per-widget presentation and enabled state; and
- rearrange widgets and control split or separator boundaries.

Continue changing themes and wallpapers through Omarchy. Omarchy owns the
active theme, while Shibumi maps its colors to semantic presentation tokens
and retains its own geometry and interaction behavior.

## Understand saved state

Shibumi stores its user-facing settings under `bar.shibumi` in Omarchy's
`~/.config/omarchy/shell.json`. It keeps suite ownership, revision, hashes, and
transaction recovery data in the XDG state directory.

Use the Control Center for normal changes. Read [configuration](configuration.md)
before editing JSON or suite state by hand.

## Know the beta boundary

Version `0.1.1-beta.8` is the current Arch-package candidate. Its package and
source contracts are tested locally; AUR publication and the complete package
lifecycle on the validation system remain release gates. Shibumi supports Omarchy Quattro
only. The exact accepted host packages are recorded in the
[Shibumi host compatibility record](architecture/quattro-compatibility.md).

Read [release readiness](release-readiness.md) for the current evidence and
open gates. Use [troubleshooting](development/troubleshooting.md) if the bar,
panel, or suite lifecycle enters an unexpected state.
