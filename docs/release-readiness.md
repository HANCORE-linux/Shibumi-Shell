# Shibumi 0.1.1-beta.16.3 release readiness

> **Document status: Revision-bound validation record.** This page separates
> recorded product evidence from release, package, and physical acceptance.
> It cannot override [`../ARCHITECTURE.md`](../ARCHITECTURE.md).

## Candidate and published predecessor

The Beta.16.3 candidate contains V1 network bar ink, the status pending-flag
ordering fix, six-style hover colour, picker search/list fixes, inline helper
execution in the plugin smokes, and the forward-baseline generator and repin. Pacman retains
its exact 16.2 presentation and hover behaviour; compact and linked-theme
Update Center changes are excluded. Its 24-plugin suite payload digest is
`9d8cca435b465c52b0ff21d7a6780f90251a805dc1d1e72b78473ca2a8338a88`.
This is the preparation snapshot included in the release-identity commit, not
final clean-commit evidence. Source review, the complete contract, isolated
Quattro lifecycle, package rehearsal, full 14-gate collector, and reproducible
archive verification must record their exact final commit externally; no
predecessor gate result transfers to this candidate.

Beta.16.2 was published on 2026-10-08 as a GitHub prerelease from
`bd1224ba92fbf279666abe362ff5cf7a165da096`. It is the frozen rolling
predecessor in [`release-predecessor.json`](../tests/fixtures/release-predecessor.json).
That exact tag checkout and release merge
`e07853b54f018ab694572c7502297e0f17752220` are admitted by
[`lifecycle-predecessors-v1.json`](../contracts/lifecycle-predecessors-v1.json),
with the unchanged Beta.16.2 payload digest
`79c61d5e048c669c9eb27ebaad21987327892089daea501d0cf4185150a26f9e`.
The exact local tag payload matches all 24 pinned plugin digests; the published
release merge and tag have the same Git tree. Older exact identities remain admitted; a
version string alone never authorizes recovery or replacement. AUR publication
remains deferred.

## Recorded evidence and outstanding gates

| Gate | Evidence and boundary |
| --- | --- |
| Complete source contract | Pending exact release-commit evidence at this preparation snapshot. |
| Isolated Quattro lifecycle | Pending exact release-commit evidence, retaining all 32 generations. |
| Retained runtime paths | Historical Beta.13 → Beta.14.1 package arm (5), fresh checkout (6), Beta.15 (7), Beta.15.2 (7), and rolling frozen Beta.16.2 → candidate (7). No arm may be dropped. |
| Stage-1 visual evidence | Round 379 records DPR 1/1.6 rest and shared-code captures, seven-theme picker search, previewless themes, sorting, and an unchanged Update Center. Round 380 separately rechecks Pacman against 16.2 and the six retained hover styles against 379. No physical-output claim. |
| Stage-1 performance | Round 379: 670 sessions, 1,880 events, cold/warm N5; focus, style, bar and hover only, not media-scroll or Control Center events. Accepted by the maintainer, including the warm Kanji CPU group as variation. Focus R/B/changed-buffer counts are not identical in every group; 13/140 hover input-to-last-pixel measurements exceed 136.667 ms by at most 2.29 ms. No blanket speedup or scanout claim. Pacman has since been restored to 16.2; no new performance series is claimed. |
| Compatibility preparation | The unchanged validator accepts forward manifest `50d687a1`; the old manifest remains. Stage-1 complete profiles stopped at the expected old-version payload pin, so all final complete gates must run again after release identities are aligned. |
| Live installation and hardware | Keep-settings installation and reviewer live acceptance must be recorded separately. Fixtures do not establish physical multi-output, hardware, credential or real desktop input acceptance. |
| Release/package verification | Reproducible archive, checksum agreement, clean-commit gates and rehearsal, independent review, full collector and remote verification remain separate publication requirements. |

The historical package arm is not a Beta.16.3 installed-package upgrade proof.
Private Wayland/Mesa captures are not live GPU, layer-shell, hotplug, or physical
multi-output acceptance. Earlier release passes do not transfer to this candidate.
The release notes document the accepted Rings early step (raw DPR-1 reload N10:
full 1/10, standard 5/10 sessions, not natural-frequency estimates) and the
existing DPR-1.6 Notch/Numbers/Kanji centre oscillation. Both remain on the
0.2.0 redesign list; the Rings animation-ordering cause is unproved.

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
| Forward reference | `50d687a1f27063513cf42e6f33c3a4fcb17c24ed` |

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
  Its leading reservation grows on an output-scale grid. Status inner-spacing
  savings are returned to the group width; centered Fit preserves whole-physical-
  pixel movements relative to the previous raster phase. Complete other-widget
  rectangles are not all RGBA-identical after translation, and the restored V1
  island edges change slot backgrounds. Exact whole-bar pixel identity and
  physical acceptance are not claimed.
- **Downgrade:** Beta.15.4 and older cannot read V1 `order.parked`; they reset
  V1 order, roles, and splits while retaining other settings and V2.
  `--keep-settings` does not prevent this. The [release notes](../.github/release-notes/v0.1.1-beta.16.3.md)
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
confers acceptance on Beta.16.3.
