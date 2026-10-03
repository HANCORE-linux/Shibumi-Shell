# Shibumi 0.1.1-beta.16.1 release readiness

> **Document status: Revision-bound validation record.** This page separates
> recorded product evidence from release, package, and physical acceptance.
> It cannot override [`../ARCHITECTURE.md`](../ARCHITECTURE.md).

## Candidate and published predecessor

The Beta.16.1 product commit is
`047bcba64f99cfa4962fa4c12d8ddd7791c8f436`, with 24 plugins and suite payload
digest `25fe4252e981e57f1a550862d448e4f9d858e66efb34f915af32743480fa05d7`.
The validation target is this product plus the documentation commit containing
the Beta.16.1 release texts. Documentation outside plugin roots leaves the
suite digest unchanged but changes release-archive bytes. Gates must bind the
accepted combined revision, not a future commit or inherited predecessor pass.

Beta.16 was published on 2026-10-02 as a GitHub prerelease from
`4840482ec0e06a2ebd478120833d4fae1f30889e`. It is the frozen rolling
predecessor in [`release-predecessor.json`](../tests/fixtures/release-predecessor.json).
That exact tag checkout and release merge
`05548c8d9ffdf0d37962d6e423e2a0dc21b8cd91` are admitted by
[`lifecycle-predecessors-v1.json`](../contracts/lifecycle-predecessors-v1.json),
with the unchanged Beta.16 payload digest
`f08b4ec613f248fda62d7dec9865ea46a846fa2e91b2723a186adc0ab0bffc41`.
Older exact identities remain admitted; a version string alone never authorizes
recovery or replacement. AUR publication remains deferred.

## Recorded evidence and outstanding gates

| Gate | Evidence and boundary |
| --- | --- |
| Complete source contract | Failed on `047bcba`, exit 1 after 151.43 seconds: `test_release_workflow_uses_curated_notes` required the missing Beta.16.1 notes. A full rerun including the documentation commit is pending. |
| Isolated Quattro lifecycle | Pending on the combined revision; not started after the contract failure. No Beta.16.1 32/32 result is recorded. |
| Retained runtime paths | Required: historical Beta.13 → Beta.14.1 package arm (5), fresh checkout (6), Beta.15 (7), Beta.15.2 (7), and rolling Beta.16 → current checkout (7): exactly 32 shell generations. |
| Bluetooth preparation | Native-QML softblock-mock red/green regression and scoped Bluetooth, IPC, hotplug, and audio checks passed during fix preparation; these are not final-HEAD full gates or real rfkill acceptance. |
| Scoped visual previews | Private V1/V2 fit comparisons at DPR 1/1.6 cover the update count, badge-free tray, custom tone and count transitions; these revision-bound previews are not physical acceptance. |
| Live installation and Bluetooth | Pending: reviewer installation and real softblock → on through Bar, panel, and IPC; rapid repeat clicks; on → off. No hardware or persistence result is recorded. |
| Release/package verification | Release date, exact-commit archive/checksum, updated PKGBUILD/`.SRCINFO`, source/package rehearsal, 14-gate collector, and publication verification remain pending. |

The failed contract run passed the baseline and documentation checks and
26 of 27 PackageReleaseTests; the missing release notes were the sole package
test failure. No test was relaxed and no placeholder notes were added to bypass
it. Focused documentation checks do not replace the full contract rerun.
The historical package arm is not a Beta.16.1 package-upgrade proof. Private
Wayland/software-rendered previews are not live GPU, layer-shell, hotplug, or
physical multi-output acceptance. Earlier release passes do not transfer to
this candidate.

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
- Bluetooth power affects all radios through the host helper and cannot clear
  a hardware block. The 20-second pending deadline does not stop the detached
  process or prevent later effects. Real rfkill and persistence acceptance is
  separate from controlled native-QML feedback.
- The horizontal update count shares the bar-value baseline and CPU ink spacing.
  Its leading reservation grows on an output-scale grid so the unchanged bell
  retains its raster phase, including centered Fit. The private captures still
  contain isolated one-level RGB differences in other widgets after translation;
  exact whole-bar pixel identity and physical acceptance are not claimed.
- **Downgrade:** Beta.15.4 and older cannot read V1 `order.parked`; they reset
  V1 order, roles, and splits while retaining other settings and V2.
  `--keep-settings` does not prevent this. The [release notes](../.github/release-notes/v0.1.1-beta.16.1.md)
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
release checklist. Beta.16's published changes and limits remain in its
[release notes](../.github/release-notes/v0.1.1-beta.16.md). Its earlier product
revision `30746f5` passed the complete contract and 32-generation runtime;
those fixtures retained known teardown warnings and did not establish blanket
hardware acceptance. Earlier readiness snapshots remain in Git history; none
confers acceptance on Beta.16.1.
