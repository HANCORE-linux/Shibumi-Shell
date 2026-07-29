# Release workflow

Status: private-alpha runbook

The suite version in
[`../../contracts/plugin-suite-v1.json`](../../contracts/plugin-suite-v1.json),
all 25 plugin manifests, the changelog, release commit, and Git tag must agree.

## Prepare

1. Confirm the target and remaining gates in
   [release readiness](../release-readiness.md).
2. Update the suite version and every plugin manifest together.
3. Move user-visible changelog entries into the target version.
4. Update user guides, architecture contracts, compatibility evidence, and
   screenshot placeholders or captures affected by the release.
5. Confirm the repository remains private while public-release blockers are
   open.

## Validate the source tree

Review source hygiene in the Git checkout:

```bash
git status --short
git diff --check
```

This is a read-only source review, not runtime acceptance.

## Validate on Machine2

Run the complete contract against the supported Quattro runtime:

```bash
cd /home/drdeltree/Projects/shibumi
OMARCHY_PATH=/usr/share/omarchy ./tests/contract-regression.sh
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

## Live acceptance

At minimum, verify:

1. Shibumi to Omarchy to Shibumi bar continuity;
2. Top and Bottom bar placement;
3. Control Center, App Menu, panels, pickers, Escape, and outside dismissal;
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
3. Tag the exact accepted commit as `v<version>`.
4. Push the branch and tag to the private
   `HANCORE-linux/Shibumi-Shell` repository.
5. Verify the remote branch and tag resolve to the intended commits.

Do not move an already published tag silently. If a tagged private-alpha
candidate needs another fix, agree on whether to replace the unpublished tag
or advance the version before changing remote history.

## Public-release gate

Making the repository public requires every blocker in
[release readiness](../release-readiness.md) to pass on the exact release
commit. A fixture, source audit, or inherited predecessor behavior does not
replace physical Shibumi runtime acceptance.
