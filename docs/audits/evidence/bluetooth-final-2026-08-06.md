# Bluetooth final candidate evidence — 2026-08-06

Final candidate recorded at `2026-08-06T02:10:09+02:00` against base commit
`f570eaffaf89759e1bb2d39bd9e3dfbeb83b0fd0`. At recording time the base was
five commits ahead of and zero behind `origin/main`
(`040da9b104055e6799000aceb8c9331312fe6345`). A direct `git fetch origin main`
at `2026-08-06T01:30:24+02:00` confirmed the same remote hash. This evidence
describes the uncommitted follow-up candidate; no push was performed.

## Focused Bluetooth gate

Command: `./tests/bluetooth-plugin-regression.sh`

Result: exit code 0. Required terminal markers observed:

```text
bluetooth backend regression passed
bluetooth audio intent regression passed
service-first: targets=1 methods=6 duplicates=0
service-first: rollback settled bluetooth/discovery=1:0
backend-first: targets=1 methods=6 duplicates=0
backend-first: rollback settled bluetooth/discovery=1:0
bluetooth IPC ownership regression passed
bluetooth IPC signal regression passed
bluetooth plugin regression passed
```

The backend regression includes destruction during a delayed Discovery start,
two simulated rejected Stop attempts, bounded reconciliation to a stable stop,
and two independent pending completions. A separate exact race completes the
old request immediately before replacement `startDiscovery()` and proves
same-turn ownership through the shared QML singleton. The backend regression
also destroys an adapter while its guard timer is live and proves immediate
registry cleanup. The IPC signal regression includes INT, TERM, HUP and the
TERM-resistant child case; the latter checks settled state restoration,
Leader/PGID termination and removal of its isolated case root.

## Full contract gate

Command: `./tests/contract-regression.sh`

Result after the shared-singleton, exact-takeover and adapter-lifecycle review
corrections: exit code 0. The current run again reached all focused Bluetooth
markers above and ended with:

```text
Shibumi contract regression passed
```

Expected fixture-only diagnostics included unavailable PipeWire in isolated
offscreen processes and deliberately rejected fixture actions. They are not
production-runtime findings and did not fail the contract.

## Static gates

- `python3 tests/documentation-regression.py`: exit 0,
  `documentation regression passed`.
- `shellcheck` for the changed Bash contracts: exit 0.
- Root/plugin `cmp` for `BluetoothBackendAdapter.qml`, `BluetoothModel.js` and
  `BluetoothDiscoveryGuard.qml`: exit 0.
- `/usr/lib/qt6/bin/qmllint -I /usr/share/omarchy/shell
  adapters/BluetoothBackendAdapter.qml adapters/BluetoothDiscoveryGuard.qml`:
  exit 0; exactly three existing unresolved Quickshell type-metadata warnings,
  no QML error.
- `git diff --check`: exit 0.

## Candidate hashes

```text
f4f4b613a1b0a68ac2432dbc450c65a3a24bc2450ed54962198d289fe4bf1a6f  adapters/BluetoothBackendAdapter.qml
82766809f271b42ab75eceaa29fc35d1606fa7e9076668cba3629783accc848c  adapters/BluetoothDiscoveryGuard.qml
a37830b73945ffdcbbcfcbc4fa4d62a3114aa0610f1d21d2875a57699a6e4411  adapters/qmldir
f4f4b613a1b0a68ac2432dbc450c65a3a24bc2450ed54962198d289fe4bf1a6f  hancore.shibumi.bluetooth/BluetoothBackendAdapter.qml
82766809f271b42ab75eceaa29fc35d1606fa7e9076668cba3629783accc848c  hancore.shibumi.bluetooth/BluetoothDiscoveryGuard.qml
9617b89277651c3c7dafcb4f1388a1e0d7e318ec089b1309634558a50d0a38b5  hancore.shibumi.bluetooth/qmldir
6d925f5d90ce2e30e9d770038954bbe403059352ba026f1d9fbcccb2d9a8f443  tests/bluetooth-backend-regression.qml
a767f09cefffb7e1c5236a13e9b72a6eed38e16e7a03b9e297bb4e259b3dcca6  tests/bluetooth-ipc-harness-signal-regression.sh
```

Physical multi-output behavior remains deferred because no second monitor is
available. This run made no real Bluetooth device, radio or audio mutation.
