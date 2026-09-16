# Arch packaging and AUR publication

Status: `0.1.1-beta.14.1` local candidate contract

Shibumi ships one versioned suite containing 24 separately validated Omarchy
Quattro plugin roots. Pacman owns the immutable program files; the Shibumi
lifecycle owns explicit per-user staging, activation, repair, and removal.

## Package boundary

The `shibumi-shell` package installs:

- the immutable suite under `/usr/share/shibumi-shell`;
- the stable command `/usr/bin/shibumi-shell`;
- the suite, host-facade, package-runtime, backend-boundary, and exact
  lifecycle-predecessor contracts;
- package-origin metadata, license, and runtime user documentation.

It has no `.install` script or Pacman hook. A package transaction must never
guess a logged-in desktop user or write `~/.config/omarchy`, `~/.local/state`,
or `~/.cache`. Those paths belong to an explicit unprivileged lifecycle
transaction:

```text
Omarchy/Pacman installs immutable /usr payload
                    |
                    v
user runs shibumi-shell install or update
                    |
                    v
24 plugin roots are staged, reloaded, and verified transactionally
```

## Quattro and dependency policy

Shibumi supports Omarchy Quattro only. The PKGBUILD depends on `omarchy`
rather than `omarchy>=4`: the Quattro development package currently declares
an unversioned `provides=omarchy`, so Pacman cannot satisfy a versioned virtual
dependency even though the installed host is Quattro. The lifecycle closes
that packaging gap by verifying the exact Shibumi-required Quattro APIs before
any mutation.

Required commands, services, and fonts are declared in
[`../../contracts/package-runtime-v1.json`](../../contracts/package-runtime-v1.json).
Pacman skips packages that are already installed or provided. Optional
packages enable bounded features such as the media spectrum, thumbnails, and
NVIDIA telemetry; their absence does not prevent the core suite from starting.

## User lifecycle

After AUR publication, the normal installation is one copyable command:

```bash
omarchy pkg aur add shibumi-shell && shibumi-shell install --yes
```

Package upgrades require an explicit staging step:

```bash
omarchy update
shibumi-shell update --yes
```

A source-managed installation moves to package ownership by installing the
package and running `shibumi-shell update --yes`. User configuration, the
active profile, external layouts, and unrelated plugins are preserved.

Intentional package rollback is supported only between releases that both use
the canonical State service-entry storage contract. Beta.12 is the first package
with that contract, so it has no older eligible package target. Do not install
Beta.11 or an earlier package after Beta.12: Pacman replaces the current payload
and lifecycle code before the user-level update runs, so Beta.12's storage guard
cannot reject that package afterward. There is no reverse migration to legacy
storage.

For a future older release that explicitly retains the same storage contract,
rollback remains two-step and opt-in:

```bash
sudo pacman -U /var/cache/pacman/pkg/shibumi-shell-compatible-older.pkg.tar.zst
shibumi-shell update --allow-downgrade --yes
```

The eligible target's lifecycle must still admit both release identities. Its
transaction failure and recovery path restores complete original snapshots.

Removal reverses the user lifecycle before dropping the immutable payload:

```bash
shibumi-shell uninstall --yes
omarchy pkg drop shibumi-shell
```

## Immutable release asset

`scripts/build-release-archive` builds a deterministic, single-root archive
named `shibumi-shell-<version>.tar.gz`. It normalizes ownership, timestamps,
ordering, and compression metadata and emits a SHA-256 file plus a complete
inventory.

The AUR metadata directory is intentionally excluded from the archive. Keeping
the PKGBUILD containing `_source_sha256` inside the bytes it hashes would make
the checksum self-referential. The runtime package helpers under `packaging/`
remain in the asset.

The GitHub tag workflow rebuilds the archive from `GITHUB_SHA`, requires the remote `v<VERSION>` tag to peel to that commit, and compares the result with the pinned PKGBUILD checksum. The self-hosted validation job has read-only repository permission. It transfers the validated assets and their checksum manifest to a separate publication job. Only that job receives write permission.

The publication job verifies the transferred inventory and checksums before it creates or updates a draft. It downloads the remote assets, compares every name, size, and SHA-256, and only then publishes. A server-side `v*` ruleset must independently block tag updates and deletion. A failed upload or verification remains a draft. Every external action is pinned to a full commit SHA.

## Local rehearsal

Run the complete local package rehearsal without a published tag:

```bash
./scripts/check-aur-package
./scripts/rehearse-aur-package
```

The rehearsal creates the release archive twice, replaces the remote source
with that local asset in a temporary PKGBUILD, runs `makepkg`, and inspects the
result. It requires:

- a successful source checksum validation;
- files only below `/usr` plus normal package metadata;
- no install hook, user path, bytecode cache, or unexpected payload;
- the stable command, package marker, license, suite contract, and lifecycle
  predecessor contract;
- exactly the 24 contract-declared plugin manifests;
- a successful packaged lifecycle help smoke.

`--nodeps` is used only by this controlled rehearsal because dependency
resolution is verified separately against the validation system. The package
continues to depend on Omarchy's `omarchy-bluetooth-device` and
`omarchy-audio-output-set-default` helpers for the Beta.12 hotfix; those are
explicit compatibility debt, not undeclared native replacements. A clean-chroot
build must perform normal dependency resolution before publication.

## Publication gates

The AUR entry remains blocked until all of these are true:

1. The exact candidate commit passes the source, package, and Health tests.
2. the validation system passes package install, source-to-package migration, update,
   intentional rollback, repair, uninstall, and stock recovery.
3. Every Shibumi V1/V2/Omarchy bar-switch transition passes with one responsive
   production Quickshell process and no new bounded runtime error.
4. A clean Arch chroot resolves every required dependency and builds the
   package.
5. The immutable GitHub release asset exists and its SHA-256 equals PKGBUILD
   and `.SRCINFO`.
6. `scripts/check-aur-package --publish-check` passes against the remote tag
   and asset.
7. The AUR package name can be registered and the one-command install is
   repeated from a clean supported Omarchy Quattro account.

AUR unavailability blocks only gates 6–7. It does not block local package
construction or the validation system lifecycle acceptance.
