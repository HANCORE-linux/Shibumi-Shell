# Development setup

Status: maintainer reference

Work from a clean Shibumi checkout on the development machine:

```bash
cd /path/to/shibumi
git status --short
rg --files
```

Shibumi source inspection and automated tests run locally. Live release
acceptance is repeated by maintainers on an isolated Omarchy Quattro system;
external contributors do not need access to it. Avoid deploying development
payloads into a primary desktop's Omarchy plugin directory.

## Repository shape

- `hancore.shibumi.*/` contains the 24 self-contained plugin roots.
- `Bar.qml`, `core/`, `styles/`, and selected shared sources are canonical
  development copies with checked vendored mirrors.
- `contracts/` contains executable product and evidence contracts.
- `scripts/shibumi_suite/` implements the transactional lifecycle adapter.
- `tests/` contains source, component, runtime, and lifecycle regressions.
- `docs/` contains user references, contracts, evidence, and historical notes.

## Maintainer runtime acceptance

Maintainers synchronize only the intended source changes into the isolated
validation checkout and run the relevant test there. Its Omarchy runtime stays
at `/usr/share/omarchy` unless the compatibility target changes deliberately.

Do not start a second long-lived Quickshell process. Component smokes use
isolated temporary runtimes and must clean them up on exit.

See [testing](testing.md) for the required command order and
[troubleshooting](troubleshooting.md) for Wayland session details.
