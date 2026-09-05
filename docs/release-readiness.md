# Is Shibumi 0.1.1-beta.12 ready for prerelease testing?

> **Document status: Local release-candidate gate.** This page records evidence
> and open acceptance. It cannot override [`../ARCHITECTURE.md`](../ARCHITECTURE.md).

Beta.12 is based directly on Step-5 tip
`5154c020a44d71139a6614a183ec91021b9772c1`. It contains the 24-plugin native
Network payload, the Bluetooth ST-01 identity fix, and Omarchy 4.0.2
compatibility work. It contains no Step-6 product functionality and no
automatic Step-6 migration.

## Candidate boundary

The normal lifecycle supports only these predecessor identities:

- public `0.1.1-beta.11` at
  `adbb11068e9c77561ff0c3d1b8fca5212653ae3c`, including its package identity;
- the exact Step-5 tip at
  `5154c020a44d71139a6614a183ec91021b9772c1`;
- the exact current Beta.12 payload after installation.

The version string is not authority. Admission also compares source revision,
complete suite and plugin digests, activation metadata, managed markers, and
the complete journal schema. Every existing journal is inventoried before any
journal is recovered or discarded. One admitted public journal may explain an
exposure mismatch, is consumed from its validated snapshot, and is followed by
a second live-identity check; multiple public journals fail as ambiguous.
Step-6 Power registration, Step-6 phases or fields, mixed live markers, and
unknown states fail closed without mutation. Repair alone may tolerate a
missing owned root or payload drift while exact state and remaining marker
authority hold. Machines already running Step 6 need a separate reviewed
rollback.

## Current tested host contract

| Component | Accepted identity |
| --- | --- |
| Omarchy | `omarchy 4.0.2-1` |
| Omarchy settings | `omarchy-settings 4.0.2-1` |
| Official source | `v4.0.2`, `346e69e1cec6c4e8924531874af6ba010a1bc99e` |
| Quickshell | `quickshell 0.3.1-1` |
| Installed-package profile | `installed-package-v4.0.2` |
| Source-parity profile | `installed-source-parity-v4.0.2` |
| Agents reference | `v4.0.0`, retained for that isolated contract only |
| Forward reference | `ed7bae4ac5a570e9df307486e0202fdafcc6ee24` |

The installed package and pinned `v4.0.2` source have exact `shell` and
`config` parity. Installed `/usr/share/omarchy/bin` links resolve to the same
source payload, apart from three host-local helpers not owned by those packages.
The machine-readable manifests bind the complete consumed subtrees.

## Bluetooth ST-01

`BluetoothBackendAdapter` keeps native device QObjects private. The service and
panel receive detached primitive records containing address, device D-Bus path,
adapter ID/path, and monotonic device/adapter incarnations. Immediately before
mutation, the adapter resolves exactly one current native entity and checks its
state. Malformed, stale, ambiguous, missing, or state-conflicting identities
return typed failures and dispatch zero actions.

The panel consumes action results through explicit `.ok`; a truthy
`{ok: false}` object cannot be mistaken for success. Device connect, pair,
disconnect, and forget retain exactly one
`omarchy-bluetooth-device` helper mutation path. The audio handoff remains
incarnation-bound and the `omarchy-audio-output-set-default` compatibility
helper remains declared debt. Helper removal is not part of this hotfix.

## Evidence status

| Gate | Status |
| --- | --- |
| Exact 24-plugin source contract | Local automated gate required on final commit |
| Omarchy 4.0.2 installed-package baseline | Passed locally |
| Omarchy 4.0.2 source-parity baseline | Passed locally |
| Forward-compatibility baseline | Passed locally |
| Bluetooth detached-record and stale-identity regression | Passed locally |
| Lifecycle predecessor and all-journal admission regression | Passed locally |
| Full Python, QML, shell, documentation, and package suites | Required on final commit |
| Reproducible exact-commit archive and checksum | Required after final commit |
| AUR package rehearsal with exact installed inventory | Required after checksum pinning |
| Fresh physical Network acceptance | **Open; public-beta blocker** |
| Fresh physical Bluetooth acceptance | **Open; public-beta blocker** |
| Live install, activation, update, rollback, and uninstall | Not authorized in local-candidate scope |
| Machine 2 | Out of scope and untouched |
| Push, tag, GitHub release, or AUR publication | Not authorized |

Fixtures prove deterministic boundaries but do not replace physical Network,
Bluetooth, output, suspend/resume, notification, drag/drop, or visual checks.
Enterprise Wi-Fi, mixed scale, multi-output, and display hotplug remain tracked
stable-release gates where hardware or credentials are unavailable.

## Release asset gate

The final archive must be built from the exact clean commit, reproduce
byte-for-byte, and provide a complete inventory plus SHA-256 sidecar. The AUR
rehearsal must reject every unexpected installed path and confirm package
metadata, lifecycle help, the predecessor contract, and all 24 plugin roots.

A tag workflow must:

1. prove the remote tag peels to `GITHUB_SHA`;
2. rebuild the exact-commit archive and validate all asset relationships;
3. create a draft release containing only the declared assets;
4. download those remote assets and compare every name, size, and SHA-256;
5. repeat direct/peeled remote tag verification against `GITHUB_SHA`;
6. publish only after both comparisons pass.

Repository administrators must enforce a server-side immutable `v*` tag
ruleset that blocks tag updates and deletion. Workflow checks do not replace
that server-side control. Any failed upload or verification remains a draft and
must never be treated as a published release. Workflow retries may reuse only
that draft, clobber only the declared asset names, and must repeat the complete
remote comparison immediately before publication; undeclared assets fail the
retry closed.

## Publication decision

Beta.12 is a local candidate, not an authorized release. Publication remains
blocked until the final clean-commit automated gates, AUR rehearsal, and fresh
physical Network/Bluetooth acceptance pass and separate authorization is given.
