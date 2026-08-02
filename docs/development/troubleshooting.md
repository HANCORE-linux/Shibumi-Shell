# Troubleshooting

Status: user and maintainer reference

## Shibumi does not appear

Run:

```bash
./scripts/shibumi-suite status
omarchy plugin list
```

If Shibumi is installed but inactive:

```bash
./scripts/shibumi-suite activate --dry-run
./scripts/shibumi-suite activate
```

Do not use `omarchy plugin add` on the repository root. It is a 24-plugin suite,
not one root plugin.

## A Shibumi plugin was removed or disabled individually

The generic Omarchy plugin menu manages one plugin root at a time and does not
know Shibumi's suite dependencies. Restore the complete suite:

```bash
./scripts/shibumi-suite status
./scripts/shibumi-suite repair --dry-run
./scripts/shibumi-suite repair
```

Repair is transactional and refuses foreign replacement targets. Do not try to
recreate missing suite directories by hand.

## The Omarchy bar is active

Open Control Center **Bars** and select Shibumi, or run:

```bash
./scripts/shibumi-suite activate
```

If `omarchy bar defaults` was used, Shibumi can restore its managed layout but
cannot reconstruct personal `bar.shibumi` settings that the defaults command
deleted.

## A panel is misplaced or detached

Close and reopen the panel once, then record:

- the invoking widget and panel;
- Top or Bottom bar placement;
- output resolution and scale;
- whether the bar, screen, theme, DPMS, or screensaver state changed;
- the current Quickshell log and a screenshot.

Panels should close when the bar is hidden for an idle or screensaver
transition. A panel that remains open with a lost anchor is a product bug.

## An update is refused

`shibumi-suite update` refuses:

- inactive or configuration-drifted installations;
- unmanaged or foreign plugin directories;
- symlinked payloads and special files;
- unsafe manifest entry points;
- invalid or inconsistent install state.

Run `status` and resolve the reported drift. Use `activate` before `update` when
the suite is intentionally installed but inactive. Use `repair` when payloads
are missing, modified, ownership-mismatched, or were disabled individually.

## An operation was interrupted

Keep the state directory intact and rerun the intended suite command.
Mutating commands recover unfinished transactions before starting new work.
Do not delete transaction directories or ownership markers manually.

## A live QML test cannot reach Wayland

Live tests need the validation system's real user runtime, Wayland display, and Hyprland
instance. A sandbox or plain SSH session without those environment values can
fail even when the component is correct.

Run component contracts through the repository test scripts. For real-session
inspection, use the environment of the validation system's running Quickshell process and
confirm that only one production shell process remains.

## Collect diagnostics

Useful read-only checks:

```bash
./scripts/shibumi-suite status
omarchy plugin list
pgrep -af quickshell
hyprctl monitors -j
qs log
```

Do not publish logs or screenshots before removing device addresses, SSIDs,
notifications, usernames, paths, and account data.
