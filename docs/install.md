# Install and update

Status: user reference

Shibumi installs 25 independent plugin roots into Omarchy's normal plugin
directory. The repository root is a suite source, not a single installable
Omarchy plugin.

## Install from the private repository

```bash
git clone git@github.com:HANCORE-linux/Shibumi-Shell.git
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

Pass `--yes` only for an intentional non-interactive install:

```bash
./scripts/shibumi-suite install --yes
```

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

Update from a trusted checkout:

```bash
git pull --ff-only
./scripts/shibumi-suite update --dry-run
./scripts/shibumi-suite update
```

An update requires an active, suite-managed Shibumi installation. It stages all
25 current plugin roots as one transaction and verifies that the shell executes
the accepted payload rather than a stale QML cache.

## Status

```bash
./scripts/shibumi-suite status
```

Status reports the source and installed revision, managed plugin count,
modified or missing payloads, active bar, and configuration drift. A nonzero
exit indicates a state that needs attention.

## Repair a partial suite

Omarchy's generic plugin manager sees the 25 Shibumi roots as individual
third-party plugins. Do not remove or disable Shibumi internals individually.
If one was removed, disabled, or modified, restore the complete payload and
managed profile with:

```bash
./scripts/shibumi-suite repair --dry-run
./scripts/shibumi-suite repair
./scripts/shibumi-suite status
```

Repair validates and stages all current plugin roots, restores the selected
Shibumi profile, verifies the running payload, and rolls back to the exact
pre-repair state if a gate fails. It refuses to overwrite a foreign directory.

## Switch bar hosts

Keep Shibumi installed but return to the stock Omarchy bar:

```bash
./scripts/shibumi-suite deactivate --dry-run
./scripts/shibumi-suite deactivate
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

Preview and remove all managed Shibumi plugins:

```bash
./scripts/shibumi-suite uninstall --dry-run
./scripts/shibumi-suite uninstall
```

The default uninstall restores the stock bar and removes Shibumi's managed
configuration. Preserve the `bar.shibumi` settings branch with:

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
