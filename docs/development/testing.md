# Testing

Status: maintainer reference

Automated Shibumi tests can run from any supported development checkout.
Maintainers repeat the complete contract and live Wayland acceptance on an
isolated validation system before release; users and external contributors do
not need access to that system.

## Test order

Run the smallest affected regression first. For a bar-host change:

```bash
cd /path/to/shibumi
OMARCHY_PATH=/usr/share/omarchy ./tests/bar-host-registry-regression.sh
```

For a Bluetooth change:

```bash
OMARCHY_PATH=/usr/share/omarchy ./tests/bluetooth-plugin-regression.sh
```

Before handing off or releasing any source change, run all four complete
baseline jobs. The installed-package job defaults to the package-managed host:

```bash
./tests/omarchy-installed-package-contract-regression.sh
```

The installed-source-parity job requires an explicit Git checkout of the
official `v4.0.2` source revision used by the installed package:

```bash
SHIBUMI_INSTALLED_SOURCE_OMARCHY_PATH=/path/to/omarchy-v4.0.2 \
  ./tests/omarchy-installed-source-parity-contract-regression.sh
```

The forward-compat job separately requires the immutable upstream snapshot used
by the engineering audit:

```bash
SHIBUMI_FORWARD_COMPAT_OMARCHY_PATH=/path/to/omarchy-forward-compat-ed7bae4a \
  ./tests/omarchy-forward-compat-contract-regression.sh
```

The AI Agents integration retains its own narrower revision-bound host
contract against the official `v4.0.0` source baseline:

```bash
SHIBUMI_AGENTS_OMARCHY_PATH=/path/to/omarchy-v4.0.0 \
  ./tests/omarchy-agents-contract-regression.sh
```

This gate binds the consumed Agents manifest, record reader, updater, and
Claude/Codex collectors independently of the complete host inventory.

Every host-bound test both imports `tests/lib/baselines.sh` and invokes its
loader. The complete-host jobs select three repository-owned manifests with
non-overlapping claims; the Agents job selects its separate narrower manifest:

- `contracts/baselines/omarchy-installed-package-v4.0.2.json` validates the
  package-managed `omarchy 4.0.2-1`, `omarchy-settings 4.0.2-1` layout;
- `contracts/baselines/omarchy-installed-source-parity-v4.0.2.json` proves that
  the official `v4.0.2` source form satisfies the same complete suite;
- `contracts/baselines/omarchy-forward-compat-ed7bae4a.json` proves forward
  compatibility with the recorded upstream snapshot.

All three manifests bind the complete consumed `shell`, `bin`, and `config`
subtrees by entry count, path inventory, entry type, executable state, symlink
target where packaging requires one, and file-content digest. Directory nodes,
including empty directories, participate in the inventory and structure
digest; FIFOs, sockets, devices, and other unsupported node types are rejected.
`shell` and `config` payload entries must be regular files; the installed `bin`
payload entries must retain their exact absolute package symlinks. Both
Git-checkout jobs additionally require their exact declared revision. A caller
may relocate a matching tree through the documented path input, but cannot
select an arbitrary manifest, escape the validated tree through a consumed
source symlink, or add or omit any subtree entry.

The aggregate is complete only when it reaches a marker beginning with
`Shibumi complete contract regression passed`. The marker names the selected
installed-package, installed-source-parity, or forward-compat baseline and its
full source revision. Missing or drifted host files, a missing Quickshell
runtime, or any skipped host matrix fail the run before that marker.

The V1/V2 predecessor inventory is pinned portably in
`contracts/baselines/quickshell-dots-d0896fc-v2-deec8103.json`. To additionally
verify a local checkout byte-for-byte, pass its absolute path without encoding
that machine-specific path in a contract:

```bash
SHIBUMI_PREDECESSOR_PATH=/path/to/quickshell-dots \
  ./tests/reference-baseline-regression.sh
```

The full contract covers:

- V1 and V2 source evidence;
- embedded V2 difference classification;
- Quattro version and plugin contracts;
- self-contained plugin payloads and vendored parity;
- host-facade and suite lifecycle behavior;
- QML component and service smokes;
- Control Center, Omarchy menu continuity, bar, panel, and widget behavior;
- transactional installer and updater regressions.

The bar gates also run `tests/v1-center-slot-regression.qml` and the two-output
slot-interaction fixture. `tests/drag-ghost-render-regression.sh` renders only
controlled fixture content offscreen at scale factors 1 and 1.5, checks capture
pixels with the installed `/usr/bin/magick`, and tests cancellation/image lifetime.
It also tests already hidden source-window refusal and cancellation when the
source changes windows. Invalid dimensions use the shared size-guard predicate:
Qt's offscreen QWindow clamps zero dimensions to one, so this is not a native
zero-sized-window runtime test. Changed bar/model QML fixtures abort
the current JavaScript stack after `Qt.exit(1)`: scheduling failure alone must not
fall through to a later success exit. Mutation counterchecks must prove a nonzero
process exit, not merely a diagnostic string or final PASS marker.
`tests/qml-assertion-exit-regression.py` repeats positive/negative/restored-positive
controls for the center limit and controller persistence count in private copies.
The bar-host fixture also runs `fixtures/CloneSelectionChecks.qml` against the
selected baseline's unmodified registry decision/mutation methods, with only
startup directory/watcher I/O disabled. It proves the original-enable hazard,
clone identity/settings preservation and atomic refusal cases without a live
registry. Model/controller/bar tests cover ambiguous extra-slot removal and the
explicit return-to-extra workaround. `fixtures/PluginRemovalChecks.qml` executes
the exact extracted Control Center removal method against inert process
properties, proving refusal before command dispatch. That fixture neither runs
an uninstaller nor proves a filesystem-uninstall transaction. The loaded Plugin
Catalog confirmation tests preserve the actionable error and its generic fallback.
Center interaction cases exercise disabled and non-loading G8, a width-reactive
sibling on two simulated outputs, edit placeholders and loading recovery,
without deriving owner readiness from its own allocated width.
It uses no desktop screenshot or physical layer surface; real Top/Bottom ghost
and mixed-scale acceptance remain separate.

## Live validation

After the complete contract passes:

```bash
./scripts/shibumi-suite update --dry-run
./scripts/shibumi-suite update
./scripts/shibumi-suite status
```

Maintainers then verify the affected user flow in a real Wayland session. For
UI changes, inspect Top and Bottom placement, open and closed state, Escape and
outside dismissal, focus transfer, theme changes, bar switching, shell reload,
and idle/screensaver behavior when relevant.

Use screenshots and Quickshell logs as evidence. Record the exact Omarchy
version, output geometry, scale, source commit, and any physical state that
could not be exercised.

## Hardware and output gates

Fixtures prove deterministic unavailable, degraded, and error states. They do
not replace:

- physical mixed-scale and hotplug behavior;
- enterprise Wi-Fi authentication and recovery;
- Bluetooth pairing, routing, disconnect, and forget;
- suspend, resume, DPMS, and device-specific behavior.

Open physical gates stay explicit in
[release readiness](../release-readiness.md).
