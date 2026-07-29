# Shibumi

Shibumi is an independent bar and plugin suite for Omarchy Quattro. It ports the approved QS Rise V1 and V2 behavior into Quattro's native plugin runtime. Shibumi is not an official Omarchy project.

## Project status

Version `0.1.0` is a private alpha. The repository contains one full-bar plugin and 24 widget, menu, and service plugins. All 25 plugins run inside the existing Omarchy Shell process.

Machine2 passes the complete source contract against Omarchy Quattro `4.0.0.r1441.g9174fbf-1`. Physical multi-monitor, enterprise Wi-Fi, and Bluetooth-device gates remain open. Keep the repository private while those public-release gates are open.

## Why installation uses a suite adapter

Quattro's `omarchy plugin add` command reads one root `manifest.json` and installs one plugin ID. Shibumi has 25 plugin roots, so the repository root has no installable manifest.

Each child plugin passes `omarchy plugin validate`. The bundled `shibumi-suite` command stages, activates, updates, rolls back, and removes all 25 plugins as one transaction. Don't run `omarchy plugin add` against this repository.

## Install the private alpha

Install from a trusted checkout on an Omarchy Quattro system:

```bash
git clone git@github.com:HANCORE-linux/Shibumi-Shell.git
cd Shibumi-Shell
./scripts/shibumi-suite install --dry-run
./scripts/shibumi-suite install
```

The installer validates every plugin, snapshots `shell.json`, stages the complete payload, and verifies the running shell. A failed gate restores the previous plugins and configuration.

## Migrate from QS Rise

Use the migration command only for a suite-managed QS Rise predecessor:

```bash
./scripts/shibumi-suite migrate --dry-run
./scripts/shibumi-suite migrate
```

Migration preserves unrelated `shell.json` data, layout order, widget options, and Shibumi settings. It refuses unmanaged directories and ambiguous old/new state.

## Update the alpha

Quattro doesn't provide a multi-plugin repository updater. Update the trusted checkout, review the plan, then apply one suite transaction:

```bash
git pull --ff-only
./scripts/shibumi-suite update --dry-run
./scripts/shibumi-suite update
```

The Update Center covers Arch packages and installed Git themes. It doesn't fetch Shibumi source revisions.

## Manage the active bar

Use these commands to inspect or change the installed suite:

```bash
./scripts/shibumi-suite status
./scripts/shibumi-suite activate --dry-run
./scripts/shibumi-suite activate
./scripts/shibumi-suite deactivate --dry-run
./scripts/shibumi-suite deactivate
./scripts/shibumi-suite uninstall --dry-run
./scripts/shibumi-suite uninstall
```

The Control Center's **Bars** page also switches between Shibumi and Omarchy. It stores each bar layout separately and keeps the return path available.

`omarchy bar reset` selects the built-in bar but retains the Shibumi layout and settings. Run `shibumi-suite activate` to select Shibumi again.

`omarchy bar defaults` replaces the complete `bar` object with Omarchy defaults. This also removes `bar.shibumi` and its personal settings. `shibumi-suite activate` restores the managed Shibumi layout, but it cannot reconstruct settings that the defaults command deleted.

## Security boundary

Quattro plugins execute unsandboxed in the desktop shell. Install Shibumi and third-party catalog plugins only from sources you trust.

Shibumi rejects symlinked plugin payloads, special files, foreign ownership markers, unsafe manifest entry points, and unreviewed replacement directories. Theme updates disable Git hooks and filters, require an unchanged reviewed target, and apply fast-forward updates only.

## Alpha limitations

Version `0.1.0` has these acceptance limits:

- Machine2 has one `1920x1080` output at scale `1.0`, so physical mixed-scale and hotplug tests remain open
- No enterprise Wi-Fi credentials were supplied for a real authentication test
- No paired Bluetooth test device was available for pairing and audio-route tests
- Shibumi updates require a trusted source checkout and `shibumi-suite update`

Fixtures cover unavailable, degraded, and error states where hardware isn't available. They don't replace physical acceptance.

## Documentation

`/home/hancore/Projects/Quickshell-Dots` is a read-only QS Rise V1 reference during this work. Shibumi may port approved host-neutral behavior from it, but it must not share runtime paths, lifecycle state, or platform ownership.

Read [`ARCHITECTURE.md`](ARCHITECTURE.md) for the product contract, [`docs/release-readiness.md`](docs/release-readiness.md) for current evidence, and [`docs/README.md`](docs/README.md) for the documentation map.
