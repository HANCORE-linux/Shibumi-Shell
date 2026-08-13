# Release workflow

Status: beta package runbook

`VERSION`, package metadata, the suite version in
[`../../contracts/plugin-suite-v1.json`](../../contracts/plugin-suite-v1.json),
all 24 plugin manifests, PKGBUILD, `.SRCINFO`, changelog, release commit, and Git
tag must agree.

## Prepare

1. Confirm the target and remaining gates in
   [release readiness](../release-readiness.md).
2. Update the suite version and every plugin manifest together.
3. Move user-visible changelog entries into the target version.
4. Add concise, versioned notes under `.github/release-notes/`.
5. Update user guides, architecture contracts, compatibility evidence, and
   screenshot placeholders or captures affected by the release.
6. Confirm the repository visibility and remaining public-release blockers.
7. Keep AUR publication behind the source, package, and clean-build gates in
   [packaging and AUR strategy](packaging.md).

## Prepare the package checksum

Finish every file included in the release payload before pinning its checksum.
Build the candidate twice and copy its reported SHA-256 into
`packaging/aur/PKGBUILD`, then regenerate `.SRCINFO`:

```bash
scripts/build-release-archive --allow-dirty --check-reproducible
cd packaging/aur
makepkg --printsrcinfo > .SRCINFO
cd ../..
scripts/check-aur-package
```

`packaging/aur/` is excluded from the archive specifically so updating its
checksum cannot change the bytes being hashed.

## Validate the source tree

Review source hygiene in the Git checkout:

```bash
git status --short
git diff --check
python3 tests/test_package_release.py
python3 tests/test_shibumi_suite.py
python3 tests/test_shibumi_health.py
./scripts/rehearse-aur-package
```

This is a read-only source review, not runtime acceptance.

## Validate on the internal validation system

Run the complete contract against all three pinned Quattro proof axes:

```bash
cd /path/to/shibumi
./tests/omarchy-installed-package-contract-regression.sh
SHIBUMI_INSTALLED_SOURCE_OMARCHY_PATH=/path/to/omarchy-b99fd91 \
  ./tests/omarchy-installed-source-parity-contract-regression.sh
SHIBUMI_FORWARD_COMPAT_OMARCHY_PATH=/path/to/omarchy-d6b21f80 \
  ./tests/omarchy-forward-compat-contract-regression.sh
SHIBUMI_AGENTS_OMARCHY_PATH=/path/to/omarchy-b99fd91 \
  ./tests/omarchy-agents-contract-regression.sh
```

Preview and perform the exact suite update:

```bash
./scripts/shibumi-suite update --dry-run
./scripts/shibumi-suite update
./scripts/shibumi-suite status
```

Record:

- source commit;
- Omarchy Quattro and Quickshell versions;
- plugin count and payload verification;
- live workflows exercised;
- physical, credential, or hardware states not exercised;
- relevant screenshots and sanitized logs.

Package acceptance additionally records Pacman package metadata, source-to-
package migration, update, explicit rollback, repair, user-suite uninstall,
package removal, and stock Omarchy recovery.

## Live acceptance

At minimum, verify:

1. Shibumi to Omarchy to Shibumi bar continuity;
2. Top and Bottom bar placement;
3. Control Center, Omarchy menu continuity, panels, pickers, Escape, and outside dismissal;
4. shell restart and theme change;
5. idle/screensaver panel cleanup;
6. no duplicate production Quickshell process;
7. no Shibumi type, loader, reference, or binding-loop errors.

Physical multi-monitor, mixed-scale, enterprise Wi-Fi, and Bluetooth workflow
acceptance remain separate release gates when the hardware or credentials are
not available.

## Commit and publish

1. Review `git diff`, generated evidence, and the working tree.
2. Commit with a concise imperative subject.
3. Rebuild the archive from the clean commit and confirm its SHA matches the
   pinned PKGBUILD value.
4. Tag the exact accepted commit as `v<version>`.
5. Push the branch and tag to `HANCORE-linux/Shibumi-Shell`.
6. Verify the remote branch and tag resolve to the intended commits.
7. Confirm the SHA-pinned GitHub workflow publishes the archive, checksum, and
   inventory from that exact tag.

Do not move an already published tag. If a candidate needs another fix, advance
the prerelease version and produce a new immutable asset.

## Public-release gate

Making the repository public requires every blocker in
[release readiness](../release-readiness.md) to pass on the exact release
commit. A fixture, source audit, or inherited predecessor behavior does not
replace physical Shibumi runtime acceptance.
