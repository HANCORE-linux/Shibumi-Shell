# Bluetooth final candidate evidence — 2026-08-06

The original candidate was recorded at `2026-08-06T02:10:09+02:00`. The
hotplug/evidence follow-up was recorded at `2026-08-06T09:23:34+02:00` against
base commit `0a400ad1d64beb40bcc91d2b23d7d7577f36e7b5`. At follow-up recording time
the base was six commits ahead of and zero behind `origin/main`
(`040da9b104055e6799000aceb8c9331312fe6345`); a direct `git fetch origin main`
immediately beforehand confirmed that remote hash. This evidence describes the
uncommitted audit-closure candidate; no push was performed.

## Focused Bluetooth gate

Command: `OMARCHY_PATH=/usr/share/omarchy ./tests/bluetooth-plugin-regression.sh`

Host binding: installed `omarchy-dev 4.0.0.r1508.g12af188-1`; the explicit
`OMARCHY_PATH` prevents the focused suite from selecting a private checkout.

Result: exit code 0. Required terminal markers observed:

```text
bluetooth backend regression passed
bluetooth adapter hotplug regression passed
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

The dedicated adapter-hotplug regression starts Discovery through the real
backend facade, destroys that adapter while the request is pending, exercises
`onAdapterChanged`, then creates a distinct replacement adapter. It requires
the stale completion to be dropped, exactly one fresh replacement request,
observed replacement ownership, clean final release and an empty guard
registry. A controlled mutation removed exactly `retirePendingDiscovery()`
from `onAdapterChanged`:
the older backend regression remained green and the dedicated test failed with
`onAdapterChanged did not retire pending Discovery`. The restored candidate
passed.

## Full contract gate

Command: `OMARCHY_PATH=/usr/share/omarchy ./tests/contract-regression.sh`

The explicit host path makes the conditional host-runtime block mandatory; it
must not be skipped because `OMARCHY_PATH` is absent.

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
  `documentation regression passed`; this includes exact guards for both
  `/usr/share/omarchy`-bound dynamic commands above.
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
b739645f1fcc723ab555723c9ee1735b4650edec247955e7c34630b96a231008  tests/bluetooth-adapter-hotplug-regression.qml
9c02ec441a8fc4406950689db55f581ddd8c03ef4a70b7714f8707016f0bc775  tests/bluetooth-plugin-regression.sh
aa7f47e8c26dac0432dcf0ffa87582738066504ad846fee4c964db9239cb37fa  tests/documentation-regression.py
```

Physical multi-output behavior remains deferred because no second monitor is
available. This run made no real Bluetooth device, radio or audio mutation.
