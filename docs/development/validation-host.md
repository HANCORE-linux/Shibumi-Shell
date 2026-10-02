# Validation host runbook

Status: provisioning plan; no bootstrap script or authorization to run it

Use a dedicated, disposable Omarchy validation account/session, never a personal
production desktop. Every provisioning, registration, repository-setting, service,
and release action needs its own maintainer Go. Record approved values and results
in private operations evidence, not credentials or machine paths in this repository.
See [release workflow](release.md) and [testing](testing.md).

## 1. Host and trust boundary

- Require Omarchy and Omarchy Settings `4.0.4-1`, Quickshell `0.3.1-1`, an active
  unlocked Wayland session, and the tools required by the repository gates.
  Record `pacman -Q omarchy omarchy-settings quickshell` and package provenance.
  A new host version needs new contract review, not edited pins to bypass failure.
- Use a dedicated HOME without SSH keys, browser sessions, signing keys, personal
  GitHub credentials, or unrelated data. Same-UID jobs can access HOME, the user
  bus, compositor and devices: isolated fixtures are not a security sandbox.
- Do not share the machine with untrusted workloads. Avoid passwordless sudo;
  any unavoidable administrative capability expands the job's compromise scope.
  Keep source, evidence and baseline paths canonical, non-symlinked and exclusive.
- Plan disk/RAM capacity and serial execution. Preserve gate timeout/log budgets;
  do not raise limits or run resource measurements concurrently to obtain a pass.

## 2. Download and register the runner (separate approvals)

Select an explicit supported release from
[actions/runner](https://github.com/actions/runner/releases), for the host CPU.
Record the version, official asset URL and official SHA-256 independently of the
local download. Never resolve an unreviewed `latest` URL or invent a checksum.
The following Bash example is for Linux x64, with reviewed values supplied first:

```bash
set -euo pipefail
: "${RUNNER_VERSION:?set the approved runner version}"
: "${RUNNER_SHA256:?set its official SHA-256}"
runner_root="$HOME/.local/share/shibumi/actions-runner"
test ! -e "$runner_root"
mkdir -p "$runner_root"
cd "$runner_root"
asset="actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz"
curl --fail --location --proto '=https' --tlsv1.2 --output "$asset" \
  "https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/${asset}"
printf '%s  %s\n' "$RUNNER_SHA256" "$asset" | sha256sum --check --strict -
tar -xzf "$asset"
```

Stop on any error; extract only after successful checksum verification, into a
new empty runner directory. For another architecture select its matching asset.
After registration Go, use GitHub **Settings → Actions → Runners → New runner**
to obtain a short-lived registration token; enter it only at the private prompt.
Do not paste tokens into relay notes, shell history, logs or a unit file.

```bash
./config.sh --url https://github.com/HANCORE-linux/Shibumi-Shell \
  --name shibumi-validation --labels shibumi-validation --work _work
```

Require default `self-hosted` and `linux` labels plus `shibumi-validation`, matching
[package-release.yml](../../.github/workflows/package-release.yml). A replacement
runner needs a unique reviewed name; labels are scheduling, not access control.
Record runner ID/name/version/labels. Review automatic runner updates and capture
the actual version for each run. Never copy a registered runner directory to a
new host; its private registration files are credentials.

## 3. User service and session environment

After unit-file approval, place this example at
`~/.config/systemd/user/shibumi-validation-runner.service` (not a root service):

```ini
[Unit]
Description=Shibumi release validation runner
After=graphical-session.target
PartOf=graphical-session.target

[Service]
Type=simple
WorkingDirectory=%h/.local/share/shibumi/actions-runner
ExecStart=%h/.local/share/shibumi/actions-runner/run.sh
UMask=0022
Restart=no
KillMode=control-group
TimeoutStopSec=120
```

No automatic enable/boot/linger is intended. In the actual validation desktop's
terminal, inspect the session values and import only the required environment:

```bash
systemctl --user import-environment WAYLAND_DISPLAY XDG_RUNTIME_DIR \
  DBUS_SESSION_BUS_ADDRESS XDG_SESSION_TYPE XDG_CURRENT_DESKTOP PATH
systemctl --user daemon-reload
```

Verify the user manager is this session's UID, the Wayland socket exists, the
user bus is reachable, and `graphical-session.target` is active. Check PATH for
untrusted entries and stale runner `.env`/`.path` snapshots; never import all
variables or a developer's `GIT_*` overrides. Keep runner umask at 022. Start only
for the approved tag window: `systemctl --user start shibumi-validation-runner`.
Inspect its journal and GitHub readiness before tagging. Do not log out or restart
the compositor mid-run. After the job and fixture cleanup, obtain stop Go, stop
that exact unit and verify it inactive and the runner offline; never use broad
`pkill`/`killall`. No production shell lifecycle action is part of this runbook.

## 4. Durable, exact host baselines

Use separate clean checkouts below a persistent location such as
`$HOME/.local/share/shibumi/validation-baselines`, outside `/tmp` and the runner's
`_work` tree. Do not use symlink aliases or a moving upstream checkout. From the
reviewed Shibumi checkout, match these manifest `sourceRevision` values exactly:

| Profile / manifest in `contracts/baselines/` | Revision | Repository variable |
| --- | --- | --- |
| `omarchy-installed-source-parity-v4.0.4.json` | `c668141e9c42b13c80c9ca4ea108e11708c5e8a5` | `SHIBUMI_INSTALLED_SOURCE_OMARCHY_PATH` |
| `omarchy-agents-v4.0.0.json` | `f0020448ca87329199de7cb12f2015ebc4a3e5e7` | `SHIBUMI_AGENTS_OMARCHY_PATH` |
| `omarchy-forward-compat-ed7bae4a.json` | `ed7bae4ac5a570e9df307486e0202fdafcc6ee24` | `SHIBUMI_FORWARD_COMPAT_OMARCHY_PATH` |

After provisioning approval, clone `https://github.com/basecamp/omarchy` separately
for each profile and `git checkout --detach <full-revision>`. Check `HEAD^{commit}`,
canonical absolute path and `git status --porcelain=v1 --untracked-files=all`.
A tag name or clean status alone is not a byte/inventory proof. Use the existing
`tests/lib/baselines.sh` validator, not a new checksum implementation. From the
Shibumi checkout, in a fresh Bash process for each profile, supply `OMARCHY_PATH`
and `SHIBUMI_OMARCHY_BASELINE_PROFILE` (`installed-source-parity`, `agents-current`,
or `forward-compat`), set `SHIBUMI_OMARCHY_BASELINE_VERSION=4.0.4`, then run:

```bash
source tests/lib/baselines.sh
shibumi_load_omarchy_baseline
```

Repeat for `installed-package` against the actual installed `/usr/share/omarchy`;
never relocate or rewrite it to mimic package provenance. Validators check the
manifest schema, exact source revision, consumed hashes/subtree inventories and
applicable package provenance. Record exits and manifest hashes. All four full
contract jobs and NativeCatalog resource checks still belong to release validation.
The collector separately preflights and revalidates complete clean candidate and
baseline identities at gate boundaries. No concurrent writers are permitted.

## 5. Repository settings and controlled release window

- Set the three repository **Actions variables** above to the accepted absolute
  paths on the validation host, not shell expressions like `$HOME` or `~`. They
  are paths, not secrets. Each variable write needs its own approval.
- Treat the repository as public/untrusted input: require approval for **all
  outside collaborators' fork-PR workflow runs**. Approval is not sandboxing;
  reviewed PR code must not execute on this session-bound self-hosted runner.
- Verify PRs use only hosted `package-contract`; `release-validation` is tag-only
  and needs that job. Review workflow changes before merge; reject routes such
  as untrusted `pull_request_target` checkout. Keep the runner offline outside
  approved windows and inspect queued jobs before starting it.
- Limit allowed Actions to reviewed full-SHA pins, use read-only default workflow
  permissions, disable Actions PR approval/creation, and verify only the hosted
  `github-release` job has `contents: write`. No publication token goes to this host.
- Protect release branches and enforce immutable `v*` tags (no update/deletion,
  no routine bypass; restrict creation to authorized maintainers). Record actual
  settings and repository visibility; do not claim they are configured from docs.
- After separate collector Go: clean accepted commit, `umask 022`, all three
  baseline variables, no ambient Git overrides, serial collector **14/14**.
  Use the release workflow's exact-commit procedure; no `--allow-dirty` acceptance.
  Any red gate stops the sequence for diagnosis, not blind retry or a weaker gate.
- Runner availability is not release approval. Push, PR, merge, tag, publication,
  download verification and later installation retain separate authorization.
