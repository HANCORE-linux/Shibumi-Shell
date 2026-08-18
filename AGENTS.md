# AGENTS.md

## Scope

These instructions apply to the entire Shibumi Shell repository.

## Product contracts

- Shibumi is a native Omarchy Quattro plugin suite running inside the existing Quickshell process.
- Preserve the authoritative 24-plugin contract and one-production-process ownership model.
- Preserve both supported presentations: V1 (`shibumi`) and V2 (`full`, `fit`, `dock`, and `notch`).
- Do not change established colors, geometry, typography, icons, or animations unless the task explicitly requests a visual redesign.
- Keep Audio and Network IPC ownership unique. Hidden official backend components must never expose a duplicate visible bar or panel surface.
- Keep panel, popout, and connected-surface ownership output-local; do not replace physical multi-output evidence with fixture claims.
- Never modify `/usr/share/omarchy` while developing Shibumi. Compatibility claims must remain revision-bound to the pinned host baselines.

## Source changes

- Read the relevant architecture, development, and release documentation before changing lifecycle, packaging, IPC, or host integration.
- Keep canonical and vendored QML/JavaScript copies synchronized. Run the repository sync/check scripts rather than editing generated copies independently.
- Preserve transactional install, update, repair, rollback, recovery, activation, deactivation, and uninstall behavior.
- Keep runtime fixtures isolated from production. They must use exact temporary paths and dedicated service ownership, must never stop, restart, mutate, or signal the production shell, and must prove complete cleanup.
- Reject malformed, incomplete, symlinked, or ambiguous recovery state before mutating live files or stopping the shell.
- Do not commit runtime state, local captures, temporary wrappers, credentials, generated caches, or reports stored outside this repository.
- Keep version metadata aligned across `VERSION`, package metadata, plugin manifests, contracts, release notes, changelog, PKGBUILD, and `.SRCINFO`.

## Validation

Run targeted tests first, then the applicable release gates. The release runbook is `docs/development/release.md`.

Core source gates include:

```bash
git diff --check
python3 tests/test_package_release.py
python3 tests/test_shibumi_suite.py
python3 tests/test_shibumi_health.py
python3 tests/test_shibumi_manager.py
./tests/third-party-integration-regression.sh
./scripts/check-aur-package
```

For host-facing changes, run all three pinned compatibility axes:

```bash
./tests/omarchy-installed-package-contract-regression.sh
SHIBUMI_INSTALLED_SOURCE_OMARCHY_PATH=/tmp/omarchy-installed-source-baseline-20260806 \
  ./tests/omarchy-installed-source-parity-contract-regression.sh
SHIBUMI_FORWARD_COMPAT_OMARCHY_PATH=/tmp/omarchy-upstream-engineering-audit-20260806 \
  ./tests/omarchy-forward-compat-contract-regression.sh
SHIBUMI_AGENTS_OMARCHY_PATH=/tmp/omarchy-agents-b99fd91 \
  ./tests/omarchy-agents-contract-regression.sh
```

Live acceptance must record what was actually exercised and must not claim unavailable hardware, credentials, multi-monitor, nested-compositor, or clean-chroot evidence as passed. Physical hardware gates require raw setup details, relevant command output, screenshots or video, and sanitized logs; fixtures cannot replace them.

## Change delivery approvals

Treat each delivery phase as a separate authorization boundary. Approval for one
phase never authorizes a later phase, and a bundled request must still be
confirmed immediately before each phase begins.

1. **Branch or worktree preparation:** show the intended branch and worktree
   path, then obtain explicit approval before creating, deleting, or resetting
   either one.
2. **Commit:** show the files or staged diff, validation result, and proposed
   English commit message, then obtain explicit approval before creating the
   local commit.
3. **Push:** report the exact commit hashes, source branch, and destination
   remote branch, then obtain a new explicit approval before pushing.
4. **Pull request:** show the proposed base, head, title, body summary, and any
   issue-closing keywords, then obtain a new explicit approval before creating,
   editing, commenting on, or otherwise mutating the PR.
5. **Merge:** wait for the required checks and reviews, report their results and
   the intended merge method, then obtain a new explicit approval before
   merging. Do not treat PR approval or a general request to finish as merge
   authorization.

Issue comments, labels, and closure are independent GitHub writes and require
separate explicit approval. Read-only status and CI inspection do not require
approval. If authorization is unclear, stop at the current phase and ask.

## Release safety

- Do not push, tag, publish a release, update Omarchy, log out, or reboot unless explicitly authorized.
- Never move an already published tag. If a published candidate needs code changes, advance the version and create a new immutable release.
- Build release archives from a clean accepted commit and verify archive, inventory, package checksum, PKGBUILD, and `.SRCINFO` agreement before publication.
- Require clean-commit release evidence and an independent review with zero actionable findings before release approval.
- Keep prerelease and stable release classification consistent with validated SemVer.
