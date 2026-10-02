# Shibumi 0.1.1-beta.16 release readiness

> **Document status: Revision-bound validation record.** This page separates
> recorded product evidence from release, package, and physical acceptance.
> It cannot override [`../ARCHITECTURE.md`](../ARCHITECTURE.md).

## Release and published predecessor

`0.1.1-beta.16` is published as a GitHub prerelease. The validated product
revision recorded here is `30746f56f61f08e7cf665e7d1fc894711b563fa2`, with
24 plugins and suite payload digest
`f08b4ec613f248fda62d7dec9865ea46a846fa2e91b2723a186adc0ab0bffc41`.
This product record does not substitute for the exact release commit's archive,
checksum, package, or complete release-evidence records.

Beta.15.4 was published on 2026-09-28 as a GitHub prerelease from
`6594b989c9f5edfe557669b0413a9bd3e50f8e81`. It is the frozen rolling
predecessor in [`release-predecessor.json`](../tests/fixtures/release-predecessor.json).
Exact tag, merge, and documentation-merge checkout identities are admitted by
[`lifecycle-predecessors-v1.json`](../contracts/lifecycle-predecessors-v1.json).
A version string alone never authorizes recovery or replacement. AUR publication
remains deferred.

## Evidence at the recorded product revision

| Gate | Evidence and boundary |
| --- | --- |
| Complete source contract | Passed on `30746f5`, exit 0; 638.65 seconds |
| Isolated Quattro lifecycle | Passed on `30746f5`, exit 0; 32/32 shell generations; 109.68 seconds |
| Retained runtime paths | Historical Beta.13 → Beta.14.1 package arm; fresh checkout; Beta.15, Beta.15.2, and rolling Beta.15.4 checkout updates |
| Settings round trips | Isolated keep-settings/reinstall retained the complete State entry and host layout, including delayed follow-up |
| Live installations | Reviewer reports `30746f5` installed on two maintainer machines by keep-settings round trip, identical settings and no Shibumi warnings in the new shell logs |
| Scoped visual previews | Reviewed V1/V2 badge, text, bell, battery, and palette comparisons; software-rendered previews do not establish physical acceptance |
| Scoped maintainer live check | Maintainer confirms the battery, charging bolt, and palette; this is not blanket acceptance of all visuals or hardware workflows |

The contract/runtime passes above are not a full 14-gate collector result.
The historical package arm is not a Beta.16 package-upgrade proof. Private
Wayland/software-rendered previews are not live GPU, layer-shell, hotplug, or
physical multi-output acceptance. The recorded contract run retained six known
PillSurface teardown TypeErrors. Its 590 warning/error lines in 154 normalized
classes matched the preceding product run, as did the runtime warning/error
multiset; these are not warning-free fixture logs.

## Pinned host contracts

The release's installed-package and source-parity contracts target Omarchy
4.0.4. Pinned configuration is not a physical-acceptance claim.

| Component | Required identity |
| --- | --- |
| Omarchy | `omarchy 4.0.4-1` |
| Omarchy Settings | `omarchy-settings 4.0.4-1` |
| Quickshell | `quickshell 0.3.1-1` |
| Installed package profile | `installed-package-v4.0.4` |
| Source parity | `installed-source-parity-v4.0.4`, `c668141e9c42b13c80c9ca4ea108e11708c5e8a5` |
| Agents reference | `v4.0.0`, `f0020448ca87329199de7cb12f2015ebc4a3e5e7` |
| Forward reference | `ed7bae4ac5a570e9df307486e0202fdafcc6ee24` |

The manifests in [`contracts/baselines/`](../contracts/baselines/) bind consumed
files and subtrees. Historical 4.0.3/4.0.2 manifests remain explicit compatibility
references, not substitutes for the release jobs' 4.0.4 pins. Provisioning is
covered by the [validation-host runbook](development/validation-host.md);
[host compatibility](architecture/quattro-compatibility.md) describes the proof axes.

## Release verification workflow

These requirements apply to each release; this list is not a record that a step
was performed. Each operation needs its own maintainer Go.

1. Complete live review and resolve accepted findings. Approve the changelog,
   highlights, downgrade warning, and documentation.
2. Finalize and commit the approved texts, including the agreed changelog release
   date before checksum preparation, and run source/documentation checks.
   Recompute all 24 plugin digests and compare candidate pins; docs outside plugin
   roots change archive bytes, not the plugin-only suite digest. Never invent
   future checkout revisions or alter published predecessor identities.
3. Build the archive reproducibly, align PKGBUILD's upstream version and checksum
   plus `.SRCINFO`, run `check-aur-package`, approve that packaging commit, and
   verify a byte-identical clean-commit rebuild. All shipped documentation must
   precede the checksum step.
4. Run the final clean-commit collector with `umask 022`, all 14 gates, exact
   durable baselines, no ambient Git overrides, and no concurrent candidate
   writers. Recheck the rolling published predecessor before evidence; do not
   drop arms. Evidence must bind the exact final release commit.
5. Complete independent review with zero actionable findings and the applicable
   physical/package gates. Record unavailable hardware and credentials honestly.
6. Release phases A–D: branch push and PR/checks; approved merge and tree check;
   controlled runner/tag/publication window; remote asset and runtime follow-up.
   Push, PR, merge, runner actions, tag, and publication each require their own
   authorization. Follow the [release workflow](development/release.md).

## Known limits and downgrade warning

- Horizontal Top and Bottom are supported. Vertical Full clipping and Icon
  alignment remain outside acceptance; the vertical bar is deferred to V3 in
  `0.2.0-beta`.
- Physical multi-output, mixed-scale, hotplug, DPMS/suspend/resume, enterprise
  Wi-Fi, and Bluetooth device workflows need their own raw setup and live
  evidence. No blanket hardware acceptance follows from these fixtures.
- Local whole-ink, workspace/Pacman, meter, Calendar overhang, and charge-bolt
  raster limits are not declared solved by the ordinary-text baseline work.
- The pinned host exposes Recent notification history, not Live popup access.
- **Downgrade:** Beta.15.4 and older cannot read V1 `order.parked`; they reset
  V1 order, roles, and splits while retaining other settings and V2.
  `--keep-settings` does not prevent this. The [release notes](../.github/release-notes/v0.1.1-beta.16.md)
  and [backup guide](install.md#backup-before-downgrade) identify the complete
  settings and recovery evidence to preserve. Restore the settings with a
  matching payload.
- AUR and omarchy-pkgs publication are separate work, not authorized here.

## Immutable asset and publication gate

Require a reproducible exact-clean-commit archive, complete inventory and
SHA-256 sidecar, matching PKGBUILD/`.SRCINFO`, accepted release evidence, and
package rehearsal. The workflow verifies remote direct/peeled tag identity,
uploads only five declared assets to a draft, downloads and checks each name,
size and SHA-256, and repeats tag and asset checks immediately before publication.
Any failure stays a draft; retries may replace only declared assets. Never move
an already published tag. Server-side immutable `v*` tag rules must independently
block updates and deletion. See [packaging](development/packaging.md).

## Historical evidence

Beta.13's single-output Omarchy 4.0.3 acceptance remains historical in
[Get started](getting-started.md#know-the-beta-boundary). The paused
[Beta.14 validation record](development/beta14-validation.md) is not a current
release checklist. Beta.15.4's published changes and limits are recorded in its
[release notes](../.github/release-notes/v0.1.1-beta.15.4.md). Earlier readiness
snapshots remain in Git history; none confers acceptance on Beta.16.
