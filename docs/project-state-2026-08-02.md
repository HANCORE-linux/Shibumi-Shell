# Project state on 2026-08-02

This handoff records the published Shibumi beta-package candidate before the local workstation changes to Omarchy Quattro. `main` and `origin/main` point to `a1267b7`. The next session must verify the new local host before it changes Shibumi, user configuration, or release state.

## Resume after the local Quattro installation

The user is installing Omarchy Quattro on the workstation that contains `/home/hancore/Projects/shibumi`. Treat the workstation as a new host until read-only checks prove its versions, paths, services, shell process, and configuration.

Use these coordinates:

- Source workspace: `/home/hancore/Projects/shibumi`
- Published branch: `main` at `a1267b7`
- Dedicated validation system: `drdeltree@192.168.2.205`
- SSH command prefix: `ssh -F /dev/null drdeltree@192.168.2.205`
- Validation runtime: `/usr/share/omarchy/shell`
- Read-only V1 reference: `/home/hancore/Projects/Quickshell-Dots/versions/V1`
- Read-only V2 reference: `/home/hancore/Projects/Quickshell-Dots/versions/V2`

Do not rediscover the validation address. Do not edit either reference tree. Do not copy the validation system's user configuration onto the new local host.

Before a local Shibumi install, record:

```bash
git -C /home/hancore/Projects/shibumi status --short
git -C /home/hancore/Projects/shibumi log -1 --oneline --decorate
pacman -Q omarchy omarchy-git omarchy-dev quickshell quickshell-git 2>/dev/null
test -f /usr/share/omarchy/shell/shell.qml && echo quattro-shell-present
omarchy-shell shell ping
```

Package names vary across development and stable Omarchy installations. Record the installed result instead of assuming a package name.

## Git and publication state

The latest published sequence is:

| Commit | Result |
| --- | --- |
| `8fa79a4` | Sized hosted keyboard panels to their content |
| `e81e4e4` | Kept V2 separator controls responsive |
| `33d8602` | Restored V2 separator actions and reboot/shutdown confirmations |
| `78ac16c` | Recognized crash-relaunched Quickshell processes in Health |
| `9aa1e13` | Scoped widget-appearance IPC by V1/V2 variant |
| `3c80802` | Stabilized the Control Center panel loader across switches |
| `29c1574` | Completed the implemented Issue #5 Health lifecycle acceptance |
| `a1267b7` | Added the Arch package candidate, retired the custom app menu, and hardened bar-owner handoffs |

`a1267b7` is present on `main`, `origin/main`, and `origin/HEAD`.

The worktree was clean except for these intentionally untracked handoff materials:

- `docs/audits/`
- `docs/project-state-2026-08-02.md`

Do not add either path to a commit without explicit approval. Commit and push only after the user explicitly authorizes both actions.

## Current product contract

Shibumi supports Omarchy Quattro only. The beta candidate has these boundaries:

- Product version: `0.1.1-beta.1`
- Arch package candidate: `shibumi-shell 0.1.1beta.1-6`
- Managed suite: 24 plugins
- System payload: `/usr/share/shibumi-shell`
- Lifecycle command: `/usr/bin/shibumi-shell`
- User plugins: `~/.config/omarchy/plugins`
- Install state: `~/.local/state/shibumi/install.json`
- Omarchy owns the application menu
- Shibumi ships no `menu` entry point and no `hancore.shibumi.menu` plugin

Pacman owns the immutable payload and command. Pacman installation and removal do not change user Omarchy configuration. The user-scoped `shibumi-shell` lifecycle validates Quattro, stages managed plugins, updates configuration, and records state.

The current lifecycle implements:

- install, update, repair, activate, deactivate, and uninstall
- source-checkout-to-package migration
- package downgrade refusal and explicit rollback permission
- transaction rollback and interrupted-operation recovery
- retired-plugin migration from the previous 25-plugin state
- complete stock-bar restoration and picker routing
- package, staged-payload, and source-checkout status reporting

Install, migration, activation, deactivation, uninstall, rollback, and recovery use a stop-before-write handoff:

1. Stop every matching Quickshell instance.
2. Write the target configuration atomically.
3. Start and verify a fresh Quattro shell.

Updates and repairs keep the current bar owner and may use live reload. V1/V2 presentation changes also remain live.

## Validation evidence

Local release checks passed before `a1267b7`:

- 46 of 46 suite lifecycle tests
- 13 of 13 continuity-manager tests
- 4 of 4 package-release tests
- documentation regression
- plugin-suite contract regression
- state-matrix contract regression
- AUR scaffold checks
- local `makepkg` rehearsal

The final package rehearsal produced 370 entries with SHA-256:

```text
bb50218859e21a6004d23f4bfdd7805660366a5a556bdea3f5cbbd240d6d5de6
```

The dedicated validation system runs package `0.1.1beta.1-6` with Shibumi V2 active and 24 managed plugins. The installed manager matches the packaged manager byte-for-byte.

Runtime validation proved:

- no Shibumi menu directory, service, state entry, or manifest remains
- Omarchy menu ping and summon work after install, switching, and uninstall
- uninstall restores the complete 13-widget Quattro stock bar exactly
- the user visually confirmed the restored Omarchy bar
- install, update, uninstall, and reinstall complete with the package lifecycle
- `V1 → V2 → Omarchy` completes without a new coredump
- `Omarchy → V2` completes without a new coredump
- one production Quickshell instance remains after each fixed handoff

The coredump baseline on the validation system is 44. The latest recorded crash occurred at 22:50 before the stop-before-write fix. The validated `-6` transitions did not increase that baseline. Do not delete the historical coredumps before the remaining switch matrix finishes.

## Fable audit and Issue #5

The Fable audit's confirmed Health defect was fixed in `78ac16c`: Health now identifies a crash-relaunched Quickshell process even when its re-exec command line no longer contains the shell path.

The follow-up work also fixed:

- variant-scoped widget appearance
- Control Center loader stability during bar switches
- Health timeout, cancellation, stale-result, copy-feedback, and issue-action acceptance

Commit `29c1574` contains the implemented Issue #5 acceptance work. GitHub Issue #5 remains open. Review its current checklist and obtain user approval before closing it.

The audit report remains local under `docs/audits/`. It contains historical references to the validation environment and the earlier 25-plugin build. Treat those counts and package details as historical evidence, not the current contract.

## GitHub issue state

The issue state checked on 2026-08-02 is:

| Issue | State | Next action |
| --- | --- | --- |
| #1 | Open | Future third-party host wrapper |
| #2 | Closed | No action |
| #3 | Closed | Preserve V2 Notch regressions |
| #4 | Closed | Preserve provider-summary regressions |
| #5 | Open | Review the completed implementation before closing |
| #6 | Open | Continue the package and release gates below |
| #7 | Closed | Preserve guarded bar switching |
| #8 | Open | Future logo assets and wordmarks |
| #9 | Closed | Preserve the Control Center interaction grammar |

Issue #6 contains the detailed 2026-08-02 package status at:

`https://github.com/HANCORE-linux/Shibumi-Shell/issues/6#issuecomment-5160327606`

## Next procedure on the new local Quattro host

### 1. Establish the local host baseline

Run read-only checks first:

- identify the installed Omarchy and Quickshell packages and versions
- verify `/usr/share/omarchy/shell` and the official plugin validator
- verify shell IPC, Hyprland outputs, failed services, and existing user shell configuration
- record whether Shibumi, QS Rise, or any overlapping bar already exists
- record the local coredump baseline before lifecycle tests

Do not install Shibumi until these checks pass. Do not remove an existing shell or user configuration without explicit approval.

### 2. Use the local host for the fresh-install gate

The new Quattro installation is the preferred clean package target. Rebuild the package from `a1267b7` instead of relying on a `/tmp` artifact from the previous system:

```bash
cd /home/hancore/Projects/shibumi
./scripts/check-aur-package
./scripts/rehearse-aur-package --keep
```

Record the generated package path and checksum. Then ask the user to run the required `sudo pacman -U` command. Run `shibumi-shell install --yes` as the desktop user, not as root.

Prove these ownership rules separately:

1. `pacman -U` changes only Pacman-owned files.
2. `shibumi-shell install --yes` creates the 24 user plugin roots and install state.
3. Omarchy remains the only application-menu owner.
4. `shibumi-shell uninstall --yes` restores the exact pre-install bar.
5. Pacman removal leaves no system payload and does not rewrite user configuration.

### 3. Complete the switching matrix with logs

The three main states, V1, V2, and Omarchy, have six directed one-step transitions:

- V1 to V2
- V1 to Omarchy
- V2 to V1
- V2 to Omarchy
- Omarchy to V1
- Omarchy to V2

If each V2 form is a separate state, the state set is V1, V2 Full, V2 Fit, V2 Dock, V2 Notch, and Omarchy. Six states produce 30 directed transitions.

Test the six main host transitions first. Then test all four V2 forms on entry from V1 and Omarchy and on return to both hosts. Test Top and Bottom as a geometry axis with representative host transitions. Do not expand this into all 132 directed pairs across 12 position/style states unless new evidence requires it.

For every transition, record:

- source and destination state
- switch start and completion timestamps
- manager phase and target
- configured and running bar owner
- V1/V2 presentation state
- Quickshell process count and parentage
- coredump count before and after
- shell and menu IPC results
- new warning or error log lines
- Control Center route restoration and profile persistence

Stop at the first new coredump or state mismatch. Diagnose it before continuing the matrix.

### 4. Finish Issue #6 release gates

These gates remain open:

- AUR package-name registration
- exact public AUR one-command validation
- clean chroot build with dependency resolution
- physical downgrade and rollback
- reboot and login persistence
- mixed-scale and multi-output validation
- complete switching matrix
- immutable signed Git tag and GitHub release
- final release archive checksum in `PKGBUILD` and `.SRCINFO`
- final agreement between tag, archive, package metadata, changelog, and documentation

The unavailable AUR registration does not block local lifecycle work. It blocks publication and the exact public download path.

### 5. Preserve scope and approval boundaries

- Use Lacuna only as a structural reference. Do not copy its wording, code, or product identity.
- Do not add a Git bot unless a concrete release workflow requires one.
- Do not update third-party plugins without the user's explicit selection.
- Do not close Issues #5 or #6 without reviewing their current acceptance criteria with the user.
- Do not commit or push until the user explicitly authorizes it.
