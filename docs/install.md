# Install and update

Status: user reference

Shibumi installs 24 independent plugin roots into Omarchy's normal plugin
directory. The repository root is a suite source, not a single installable
Omarchy plugin.

## Requirements

- Omarchy Quattro; other Omarchy generations are not supported
- The package workflow installs required commands and fonts through Pacman and
  skips dependencies that are already installed or provided
- The source workflow additionally needs Git, HTTPS access to the repository,
  and a trusted local checkout

The exact accepted Omarchy and Quickshell packages are recorded in the
[Shibumi host compatibility record](architecture/quattro-compatibility.md).

## Install from the Arch package

> [!NOTE]
> AUR registration is currently unavailable, so `0.1.1-beta.8` is not
> published there yet. This is the supported flow once AUR access returns and
> the package is released.

```bash
omarchy pkg aur add shibumi-shell && shibumi-shell install --yes
```

The package manager installs immutable files under `/usr/share/shibumi-shell`
and the stable `/usr/bin/shibumi-shell` command. It does not run an install
hook, select a desktop user, edit `shell.json`, or copy plugins into a home
directory. The unprivileged `shibumi-shell install` transaction performs those
user-scoped operations explicitly and verifies the resulting Quattro runtime.

Preview the same setup without changing user state:

```bash
shibumi-shell install --dry-run
```

## Install from source

For an intentional non-interactive installation:

```bash
sudo pacman -S --needed python jq curl networkmanager power-profiles-daemon upower xdg-utils libnotify wl-clipboard ttf-material-symbols-variable ttf-jetbrains-mono-nerd-basic noto-fonts-cjk adwaita-fonts
git clone https://github.com/HANCORE-linux/Shibumi-Shell.git
cd Shibumi-Shell
./scripts/shibumi-suite install --yes
```

This temporary source path installs the package-managed runtime dependencies
first. `sudo` applies only to Pacman; the suite transaction still runs as the
desktop user and never lets a package hook modify the home directory.

To inspect the transaction before installing:

```bash
git clone https://github.com/HANCORE-linux/Shibumi-Shell.git
cd Shibumi-Shell
./scripts/shibumi-suite install --dry-run
./scripts/shibumi-suite install
```

The dry run validates the suite and prints every target without changing the
system. The real transaction:

1. validates all plugin manifests with Omarchy;
2. rejects unsafe or foreign replacement targets;
3. stages and hashes the complete payload;
4. snapshots the affected plugins and `shell.json`;
5. exposes all plugins and rescans the registry;
6. activates the Shibumi bar and managed layout;
7. reloads the shell and verifies the running payload;
8. restores the previous state if a gate fails.

Shibumi's lifecycle does not edit files below `~/.config/hypr/` and does not
change Hyprland window borders, inner gaps, or outer gaps. Such changes are not
an expected effect of installing, updating, activating, deactivating, or
uninstalling Shibumi. Keep a separately run `omarchy update` distinct when
diagnosing an installation: Omarchy owns its own Hyprland defaults and config
migrations, while Shibumi only owns its plugin payload, `shell.json`, menu
routing, and Shibumi state.

Pass `--yes` only when you intentionally want to skip the confirmation prompt.
Do not run `omarchy plugin add` against the repository root. Quattro installs
one root manifest at a time, while Shibumi is a managed suite.

### Keep the current bar

Install the complete suite without replacing the active bar or its widget
layout:

```bash
./scripts/shibumi-suite install --no-activate --keep-layout --yes
```

The two flags form one safety policy and must be used together. The adapter
stages all 24 roots, enables required Shibumi services, records external layout
ownership, and verifies the running payload through the bar-independent state
service. It does not install individual plugin roots.

Add Shibumi widgets with Omarchy Settings or the active bar's supported widget
manager. See [cross-bar plugin compatibility](plugin-compatibility.md).

## Migrate a managed QS Rise installation

Use migration only when the predecessor was installed by its suite adapter:

```bash
./scripts/shibumi-suite migrate --dry-run
./scripts/shibumi-suite migrate
```

Migration preserves unrelated `shell.json` data, bar position, layout order,
widget options, and Shibumi-compatible settings. It refuses unmanaged legacy
directories, invalid state, and unfinished predecessor transactions.

## Update

For a package installation, update the system package through Omarchy and then
stage the new immutable payload into the current user's shell:

```bash
omarchy update
shibumi-shell update --dry-run
shibumi-shell update --yes
```

Pacman updating `/usr/share/shibumi-shell` does not silently change a running
desktop. The explicit update validates, stages, reloads, and verifies all 24
plugins as one transaction.

For a trusted source checkout:

```bash
git pull --ff-only
./scripts/shibumi-suite update --dry-run
./scripts/shibumi-suite update
```

An update requires a suite-managed Shibumi installation. It stages all 24
current plugin roots as one transaction and verifies that the shell executes
the accepted payload rather than a stale QML cache. For the managed Shibumi
bar, the updater drains the shell before publishing live plugin roots, then
starts it once; this prevents a plugin hot reload from overlapping IPC teardown.
Hidden staging directories
do not trigger Quattro's live plugin watcher. Immediately before replacing the
live roots, the updater requires an authoritative lock status with `locked`,
`requested`, `pending`, `sessionLocked`, and `secure` all explicitly false. An
active, incomplete, malformed, or unavailable lock status aborts the update,
discards staging, and leaves the live plugins unchanged; unlock the active
session and retry. For an external-bar installation, update preserves the
active bar and layout.

### Move from a checkout to the package

Install the package without uninstalling the existing suite, then run:

```bash
shibumi-shell update --dry-run
shibumi-shell update --yes
shibumi-shell status
```

The transaction adopts the package payload, preserves the active profile,
layout, settings, and unrelated Omarchy data, and records `package` as the new
authoritative origin. The old checkout is not deleted or modified.

### Roll back a package version

Install a previously accepted package from Pacman's cache, then explicitly
authorize staging its older payload:

```bash
sudo pacman -U /var/cache/pacman/pkg/shibumi-shell-<older-version>-any.pkg.tar.zst
shibumi-shell update --allow-downgrade --dry-run
shibumi-shell update --allow-downgrade --yes
```

Without `--allow-downgrade`, update and repair refuse to replace a newer staged
suite with an older payload. The authorized rollback still uses the normal
transaction, runtime verification, and automatic failure recovery.

## Status

```bash
shibumi-shell status
```

Use `./scripts/shibumi-suite status` for a source installation.

Status reports the source and installed revision, managed plugin count,
modified or missing payloads, active bar, and configuration drift. A nonzero
exit indicates a state that needs attention.

## Repair a partial suite

Omarchy's generic plugin manager sees the 24 Shibumi roots as individual
third-party plugins. Do not remove or disable Shibumi internals individually.
If one was removed, disabled, or modified, restore the complete payload and
managed profile with:

```bash
./scripts/shibumi-suite repair --dry-run
./scripts/shibumi-suite repair
./scripts/shibumi-suite status
```

Repair validates and stages all current plugin roots, verifies the running
payload, and rolls back to the exact pre-repair state if a gate fails. It
restores the selected Shibumi profile in managed mode and preserves the active
bar and layout in external mode. It refuses to overwrite a foreign directory.

## Switch bar hosts

Keep Shibumi installed but return to the stock Omarchy bar:

```bash
./scripts/shibumi-suite deactivate --dry-run
./scripts/shibumi-suite deactivate
```

Switching between the Shibumi and Omarchy bar owners performs Quattro's full
shell handoff: the previous instance stops before the new bar configuration is
published, then a fresh instance starts and is verified. V1/V2 presentation
changes within the Shibumi bar remain live.

Keep the current Shibumi widgets in the stock bar instead:

```bash
./scripts/shibumi-suite deactivate --keep-layout
```

Restore the Shibumi bar and managed layout:

```bash
./scripts/shibumi-suite activate --dry-run
./scripts/shibumi-suite activate
```

The Control Center **Bars** page performs the same supported host switch and
keeps both return paths visible.

`omarchy bar reset` selects the stock bar while preserving the current layout.
`omarchy bar defaults` replaces the complete `bar` object and removes
`bar.shibumi`; use it only when that broader reset is intended.

## Uninstall

For a package installation, remove the user-scoped suite first and the system
package second:

```bash
shibumi-shell uninstall --dry-run
shibumi-shell uninstall --yes
omarchy pkg drop shibumi-shell
```

This order keeps the lifecycle command and immutable payload available until
the stock Omarchy bar, menu routing, plugin roots, and installation state have
been restored or removed. Pacman removal by itself intentionally does not
mutate user configuration. Uninstall uses Quattro's supported full shell
restart before removing the complete provider tree. Install, activate,
deactivate, and migration use the same boundary; this avoids racing Qt's live
QML loaders during a wholesale bar-owner transition.

For a source installation, preview and remove all managed Shibumi plugins with:

```bash
./scripts/shibumi-suite uninstall --dry-run
./scripts/shibumi-suite uninstall --yes
```

Do not follow the source uninstall with `omarchy pkg drop shibumi-shell`.
The transitional source workflow did not install a package with that name.
Its Pacman-managed runtime dependencies remain installed because they may be
shared with Omarchy or other software.

The default uninstall restores the stock bar and removes Shibumi's managed
configuration. Shibumi records the bar that was active before installation so
its widgets and options can be restored as a complete layout. Install states
created before this record existed fall back to Quattro's current stock-bar
definition instead of leaving an empty bar. Preserve the `bar.shibumi`
settings branch with:

```bash
./scripts/shibumi-suite uninstall --keep-settings
```

The adapter removes only suite-owned plugin directories. It refuses foreign or
ambiguous targets.

## State and recovery

The suite stores installation metadata under:

```text
${XDG_STATE_HOME:-$HOME/.local/state}/shibumi/
```

Interrupted transactions are recovered before the next mutating suite command.
Do not edit `install.json`, transaction snapshots, ownership markers, or plugin
hashes by hand.

If an operation fails:

1. keep the checkout and error output unchanged;
2. run `./scripts/shibumi-suite status`;
3. rerun the same suite command so automatic recovery can complete;
4. use [troubleshooting](development/troubleshooting.md) before removing files
   manually.

## Security boundary

Omarchy plugins execute unsandboxed inside the desktop shell. Install Shibumi
and third-party catalog plugins only from sources you trust.

The suite adapter rejects symlinked payloads, special files, unsafe manifest
entry points, foreign ownership markers, and unknown replacement directories.
It hashes the staged payload and verifies the running revision before
committing a transaction.

Shibumi does not fetch its own source updates. For a source installation,
update only from a trusted checkout. Package update checks are read-only and package
installation remains owned by Omarchy/Pacman. The AUR boundary is documented in
[packaging and AUR strategy](development/packaging.md).
