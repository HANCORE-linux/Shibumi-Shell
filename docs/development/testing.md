# Testing

Status: maintainer reference

All Shibumi tests run on Machine2. Local source inspection and editing are
allowed, but a local pass is not release evidence.

## Test order

Run the smallest affected regression first. For a bar-host change:

```bash
cd /home/drdeltree/Projects/shibumi
OMARCHY_PATH=/usr/share/omarchy ./tests/bar-host-registry-regression.sh
```

For a Bluetooth change:

```bash
OMARCHY_PATH=/usr/share/omarchy ./tests/bluetooth-plugin-regression.sh
```

Before handing off or releasing any source change, run the complete contract:

```bash
OMARCHY_PATH=/usr/share/omarchy ./tests/contract-regression.sh
```

The full contract covers:

- V1 and V2 source evidence;
- embedded V2 difference classification;
- Quattro version and plugin contracts;
- self-contained plugin payloads and vendored parity;
- host-facade and suite lifecycle behavior;
- QML component and service smokes;
- Control Center, App Menu, bar, panel, and widget behavior;
- transactional installer and updater regressions.

## Live validation

After the complete contract passes:

```bash
./scripts/shibumi-suite update --dry-run
./scripts/shibumi-suite update
./scripts/shibumi-suite status
```

Then verify the affected user flow in Machine2's real Wayland session. For UI
changes, inspect Top and Bottom placement, open and closed state, Escape and
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
