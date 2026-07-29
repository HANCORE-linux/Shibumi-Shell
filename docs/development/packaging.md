# Packaging and AUR strategy

Status: private-alpha decision

An Arch package is a useful future distribution layer for Shibumi, but it does
not replace the suite lifecycle. Shibumi remains one release containing 25
separately validated Omarchy plugin roots with dependencies, shared state, and
one transactional activation profile.

## Decision

Publish the first stable public release through an AUR package named
`shibumi-shell`. Do not publish the package while the source repository is
private or the stable release gates remain open.

A normal public AUR package needs a publicly retrievable, immutable source
archive and checksum. A private GitHub release would require user-specific
credentials and cannot provide the expected public AUR build path. During the
private alpha, use the trusted Git checkout and `shibumi-suite` directly. A
local `makepkg` build or private Arch repository can be added later if
installation on several controlled machines justifies that extra release
surface.

The stable-release user experience must be one copyable command, without a
manual clone or multi-step configuration guide. The current safe target is:

```bash
yay -S shibumi-shell && shibumi-shell install --yes
```

This is one shell command but intentionally keeps the two ownership domains
separate: the AUR helper installs the immutable system package, then the
unprivileged Shibumi lifecycle command configures the current user's Omarchy
session. A package hook must not guess the desktop user or mutate that user's
home directory while running as root.

## Intended package boundary

A future package should:

- install an immutable release payload under `/usr/share/shibumi-shell`;
- install a stable command under `/usr/bin`;
- include the contracts, plugin roots, lifecycle implementation, licenses, and
  user documentation needed at runtime;
- use a tagged source archive and pinned checksum;
- leave user state under the XDG state and configuration directories; and
- require an explicit user command to install, update, repair, activate,
  deactivate, or uninstall the Omarchy plugin suite.

Package installation and package upgrade must not edit
`~/.config/omarchy/shell.json`, remove plugin directories, or activate a bar
from a package-manager hook. Those operations are user-session state and
belong to the transactional suite command.

The resulting flow is:

```text
pacman/AUR updates immutable Shibumi source
                 |
                 v
user runs shibumi-suite update or repair
                 |
                 v
suite stages, verifies, activates, and records 25 plugin roots atomically
```

## What becomes easier

- installation of the command and immutable payload;
- version discovery, dependency declaration, upgrades, and removal through
  normal Arch tooling;
- reproducible source/checksum review; and
- later delivery to users who do not maintain a Git checkout.

## What does not become easier

- dependency-aware enable/disable behavior inside Omarchy;
- switching the complete Shibumi and stock Omarchy bar hosts;
- preserving per-bar layout and service state;
- repairing one plugin root removed by a generic plugin manager; or
- verifying that the running Quickshell process executes the new QML payload.

Those remain responsibilities of `shibumi-suite`.

## Public packaging gate

Before publishing to the AUR:

1. make the tagged release archive publicly retrievable;
2. follow the
   [AUR submission guidelines](https://wiki.archlinux.org/title/AUR_submission_guidelines);
3. add and review `PKGBUILD` and generated `.SRCINFO`;
4. build with `pkgctl build` in a
   [clean Arch chroot](https://wiki.archlinux.org/title/Creating_packages#Set_up_clean_chroot);
5. verify file ownership, runtime dependencies, licenses, and reproducibility;
6. test package install, package upgrade, suite install/update/repair, and
   package removal on Machine2; and
7. confirm that no package lifecycle hook mutates user Omarchy configuration.
8. prove the documented one-command installation from a clean supported
   Omarchy user on Machine2.

Until these gates pass, AUR metadata would add maintenance and
supply-chain surface without simplifying Shibumi's core runtime architecture.
