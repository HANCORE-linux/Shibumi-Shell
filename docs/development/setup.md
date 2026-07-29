# Development setup

Status: maintainer reference

Work from a clean Shibumi checkout on the development machine:

```bash
cd /home/hancore/Projects/shibumi
git status --short
rg --files
```

Shibumi source may be inspected and edited locally, but all automated and live
runtime tests run on Machine2. Do not deploy Shibumi into the primary
development desktop's Omarchy plugin directory.

## Repository shape

- `hancore.shibumi.*/` contains the 25 self-contained plugin roots.
- `Bar.qml`, `core/`, `styles/`, and selected shared sources are canonical
  development copies with checked vendored mirrors.
- `contracts/` contains executable product and evidence contracts.
- `scripts/shibumi_suite/` implements the transactional lifecycle adapter.
- `tests/` contains source, component, runtime, and lifecycle regressions.
- `docs/` contains user references, contracts, evidence, and historical notes.

## Machine2 test checkout

Synchronize only the intended source changes into the Machine2 checkout, then
run the relevant test there. Keep Machine2's Omarchy runtime at
`/usr/share/omarchy` unless the compatibility target changes deliberately.

Do not start a second long-lived Quickshell process. Component smokes use
isolated temporary runtimes and must clean them up on exit.

See [testing](testing.md) for the required command order and
[troubleshooting](troubleshooting.md) for Wayland session details.
