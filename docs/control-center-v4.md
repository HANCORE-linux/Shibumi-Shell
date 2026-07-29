# Control Center V4

## Product mode

Control Center V4 is a keyboard- and pointer-friendly control surface for the
Shibumi bar and Omarchy Quattro plugins. Its visual hierarchy follows the
approved ContextOwl-inspired two-column concept:

- a quiet, text-first navigation rail;
- one task-focused content surface;
- sparse accent use for selection and primary actions;
- progressive disclosure through a shadcn-style command palette;
- stable geometry instead of nested dashboard cards.

The overview keeps bar position, active bar widgets, discovered plugins, quick
actions, and the Shibumi compatibility contract visible. Existing Shibumi
configuration remains available under Appearance, Layout, and Preferences.

## Control language

The button-state logic follows the square, restrained controls used by the
Omarchy Plugins catalog while remaining fully theme-driven:

- production Control Center buttons use zero corner radius;
- normal, hover, selected, and primary states use the active theme's ANSI
  `color8`, exposed by Shibumi as `color08`;
- selected and primary states are distinguished with the active theme accent
  on border and text, not with a second fill color;
- page and card surfaces retain the dark panel palette instead of inheriting
  the button fill;
- circular indicators and other semantic geometry do not inherit the
  zero-radius button rule.

The current Machine2 theme resolved `color08` to `#3A4849`; this is runtime
evidence, not a hard-coded product color. `bright_black` and legacy `color8`
remain accepted palette inputs.

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
contract regression pass on 2026-07-29.

The complete suite was then updated transactionally on Machine2 running
Omarchy `4.0.0.r1441.g9174fbf-1`. The live eDP-1 render reports
`opened: true`, `panelLoaded: true`, retained the Quickshell PID, and produced
no QML type, reference, binding-loop, load, assignment, crash, or core errors.

Evidence:

- [approved visual concept](mockups/control-center-final-contextowl-shadcn-v4.png)
- [Machine2 live render](mockups/control-center-v4-machine2-final-en.png)
- [square color08 buttons and shadowless Notch](mockups/control-center-color08-buttons-notch-machine2.png)
- [color08 Appearance controls](mockups/control-center-color08-appearance-machine2.png)

## Remaining acceptance

The following remain final hardware or credential gates and are not closed by
the single-output live render:

- physical second monitor, mixed scale, and hotplug;
- Enterprise WLAN with real credentials;
- real Bluetooth pair/connect/disconnect/forget and Bluetooth audio;
- installation of a reviewed disposable third-party plugin through the visible
  confirmation flow, followed by removal and state restoration.
