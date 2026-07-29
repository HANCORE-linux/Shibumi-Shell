# Shibumi Shell for Omarchy

Shibumi is a native bar and plugin suite for Omarchy Quattro. It brings the
approved QS Rise V1 and V2 layouts, controls, widgets, panels, and interaction
model into Omarchy's existing shell process. Shibumi is an independent
third-party project, not an official Omarchy product.

> [!IMPORTANT]
> Version `0.1.0` is a private alpha. Keep the repository private until the
> physical multi-monitor, enterprise Wi-Fi, and remaining Bluetooth workflow
> gates in [release readiness](docs/release-readiness.md) pass.

> **Screenshot placeholder:** Shibumi desktop overview with the default bar,
> Control Center, and one connected panel. Target:
> `docs/screenshots/readme/shibumi-desktop.webp`.

## What Shibumi changes

Shibumi provides a complete bar experience without replacing Omarchy's plugin
system or starting a second Quickshell process.

- One selectable Shibumi bar with Top and Bottom placement
- V1 and V2 layouts, split controls, drag-and-drop, and responsive hiding
- Control Center pages for bars, widgets, appearance, layout, and advanced
  settings
- App Menu, workspace, notification, telemetry, media, quick-access, network,
  Bluetooth, power, brightness, temperature, GPU, and storage surfaces
- Theme-aware Shibumi colors, borders, radii, typography, and panel behavior
- Transactional install, migration, update, activation, rollback, and removal
- Per-bar layout continuity when switching between Shibumi and Omarchy

> **Screenshot placeholder:** Side-by-side captures of the Bars page and
> Appearance page. Targets:
> `docs/screenshots/readme/shibumi-bars.webp` and
> `docs/screenshots/readme/shibumi-appearance.webp`.

## Requirements

- An up-to-date Omarchy Quattro installation
- Git for installation from this private repository
- A trusted local checkout; Shibumi does not fetch its own source updates

The current alpha is validated on Machine2 against Omarchy Quattro
`4.0.0.r1441.g9174fbf-1`. See
[release readiness](docs/release-readiness.md) for the exact environment and
remaining physical gates.

## Install

Clone the private repository on the target Omarchy system, preview the
transaction, and install:

```bash
git clone git@github.com:HANCORE-linux/Shibumi-Shell.git
cd Shibumi-Shell
./scripts/shibumi-suite install --dry-run
./scripts/shibumi-suite install
```

The suite adapter validates and stages all 25 plugin roots, snapshots the
current shell configuration, activates the complete payload, reloads Omarchy
Shell, and verifies the running revision. A failed gate restores the previous
plugins and configuration.

Do not run `omarchy plugin add` against the repository root. Quattro installs
one root manifest at a time, while Shibumi is one managed suite of 25
independent plugins.

See [install and update](docs/install.md) for migration, recovery, and removal
details.

## After installation

- Open the Shibumi wordmark to reach the Control Center.
- Use **Bars** to switch between the Shibumi and Omarchy bar hosts.
- Use **Widgets** to enable, disable, configure, or place bar widgets.
- Use **Appearance** for color, border, radius, style, and workspace controls.
- Use **Layout** for split and separator behavior.
- Continue changing themes and wallpapers through Omarchy; Shibumi follows the
  active theme.

Shibumi stores its configuration under `bar.shibumi` in Omarchy's
`~/.config/omarchy/shell.json`. Read [configuration](docs/configuration.md) for
the ownership and persistence model.

## Make it yours

The Control Center exposes the supported product settings:

- switch between the V1 and V2-derived shell styles;
- choose the Shibumi accent from Omarchy's semantic theme colors;
- enable borders, panel borders, frost, and supported radius modes;
- choose workspace presentation, picker style, and per-widget appearance;
- rearrange widgets and control split or separator boundaries;
- keep independent layouts for the Shibumi and Omarchy bars.

## Update

Update the trusted checkout, preview the suite transaction, and apply it:

```bash
git pull --ff-only
./scripts/shibumi-suite update --dry-run
./scripts/shibumi-suite update
```

The Update Center handles Arch packages and installed Git themes. It does not
download Shibumi source revisions.

## Switch, reset, and remove

Inspect or change the installed suite:

```bash
./scripts/shibumi-suite status
./scripts/shibumi-suite deactivate --dry-run
./scripts/shibumi-suite deactivate
./scripts/shibumi-suite activate --dry-run
./scripts/shibumi-suite activate
./scripts/shibumi-suite uninstall --dry-run
./scripts/shibumi-suite uninstall
```

`deactivate` restores the stock Omarchy bar while retaining the managed
plugins and Shibumi settings. `activate` restores the Shibumi bar and its
managed layout.

`omarchy bar reset` also selects the stock bar and preserves the current
layout. `omarchy bar defaults` replaces the complete Omarchy `bar` object,
including `bar.shibumi`; use it only when you intentionally want to discard
those settings.

## Security boundary

Omarchy plugins execute unsandboxed inside the desktop shell. Install Shibumi
and third-party catalog plugins only from sources you trust.

The suite adapter rejects symlinked payloads, special files, unsafe manifest
entry points, foreign ownership markers, and unknown replacement directories.
It hashes the staged payload and verifies the running revision before
committing a transaction.

## Project status

Version `0.1.0` contains one full-bar plugin and 24 widget, menu, and service
plugins. The complete source and runtime contract passes on Machine2.

Current private-alpha limits:

- physical mixed-scale, hotplug, and unplug-during-drag acceptance is open;
- enterprise Wi-Fi authentication and recovery need real credentials;
- a live Bluetooth connection and panel behavior pass, while pairing, audio
  routing, disconnect, and forget still need complete acceptance;
- source updates require a trusted checkout and `shibumi-suite update`.

Fixtures cover unavailable, degraded, and error states. They do not replace
physical hardware acceptance.

## Documentation

Start with the [documentation map](docs/README.md). The
[architecture contract](ARCHITECTURE.md) defines the product boundary, and
[release readiness](docs/release-readiness.md) records the current validation
evidence.

## Contributing

Read [CONTRIBUTING.md](CONTRIBUTING.md) before changing QML, plugin contracts,
tests, or documentation. Shibumi tests run only on Machine2.

## License

Shibumi is released under the [MIT License](LICENSE).
