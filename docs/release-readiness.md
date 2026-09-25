# Shibumi 0.1.1-beta.13 prerelease status

> **Document status: Published prerelease record.** This page records the
> accepted evidence and deferred gates. It cannot override
> [`../ARCHITECTURE.md`](../ARCHITECTURE.md).

Beta.13 superseded Beta.12, which was tagged but not published as a GitHub
release or AUR package. Beta.13 is published as GitHub prerelease
`v0.1.1-beta.13` from exact commit
`2760cdb8272255790d5e4613fed8a48cb63c3555`; AUR publication remains deferred.
It retains the 24-plugin, Omarchy 4.0.3 runtime, bar, and lifecycle work and
contains no Step-6 product functionality or automatic Step-6 migration.

## Beta.15.3 worktree (not accepted)

The maintenance candidate fixes exact checkout predecessor admission for Beta.15,
Beta.15.1 (tagged, not released), and Beta.15.2. It retains strict payload and
lifecycle authority checks and contains no panel or global presentation changes.
Its package identity is `public-beta.15.3`, with only
`package:0.1.1-beta.15.3`; exact future tag/merge checkout identities belong in
Beta.15.4 once those revisions exist.

Release checklist, still open:

- review the complete candidate and the proposed versioned release notes;
- obtain explicit commit approval, then run the complete clean-commit collector,
  including separate Beta.15 and Beta.15.2 checkout-update runtime arms;
- provision and verify the three exact external host baselines through separately
  authorized operations; prior working-tree passes are not this candidate's
  clean-commit evidence;
- before tagging, confirm the registered validation runner uses Omarchy and Omarchy
  Settings 4.0.4-1 with Quickshell 0.3.1-1, and that its
  `SHIBUMI_INSTALLED_SOURCE_OMARCHY_PATH` repository variable names a clean
  4.0.4 checkout at `c668141e9c42b13c80c9ca4ea108e11708c5e8a5` (runner/variable
  changes need separate authorization);
- build the reproducible clean-commit archive, then pin PKGBUILD and `.SRCINFO`
  in the separately approved checksum step and verify a byte-identical rebuild;
- complete independent review, applicable physical acceptance, hosted gates and
  release-asset verification before claiming release acceptance. Each delivery
  phase and any production update requires its own authorization.

The Beta.13 and Beta.14 records below remain historical, not acceptance of
this maintenance candidate.

## Beta.14 worktree (not accepted)

The [candidate validation record](development/beta14-validation.md) tracks the
paused general performance investigation, direct #54 Loader fix, native A/B
census and remaining physical gates. The additional recovery rescan was removed;
only the once-per-process startup prime remains. It is separate from this published Beta.13 record.
No Beta.13 acceptance row below accepts the uncommitted Beta.14 payload.

## Beta.13 snapshot hotfix status (2026-09-12)

The published payload keeps each admitted `shell.json` snapshot open through
transaction end as a no-follow regular-file descriptor. Pathname, held-object,
size, and digest checks reject replacement and in-place mutation, including
inode reuse.

Focused Python regressions cover replacement, mutation, descriptor cleanup,
drained-baseline rebind, and crash simulation. Those regressions, independent
review, exact-commit archive and package gates, package-bound lifecycle
acceptance, and the scoped physical Machine 2 round passed before publication.

## Superseded Beta.12 candidate history

Beta.12 was based directly on Step-5 tip
`5154c020a44d71139a6614a183ec91021b9772c1`. It contained the 24-plugin native
Network payload, the Bluetooth ST-01 identity fix, and Omarchy 4.0.2
compatibility work. It contained no Step-6 product functionality and no
automatic Step-6 migration.

Candidate `98faf6a7117b3dd22675ceedf597f8b887a41363` was rejected during its
first physical fresh-install attempt: managed install requested a plugin rescan
and then stopped Quickshell while asynchronous QML incubation was still active,
producing `SIGSEGV`. The replacement candidate drains the production shell
before publishing managed plugin roots and must repeat every automated and
physical gate; evidence from the rejected identity is not transferable.

## Post-acceptance bar corrections (2026-09-08)

Candidate `d077efbd442bd7784b6ba691b67ef7160dcc00e5` completed the scoped
physical round but was reopened after the V1 ghost-content failure and the
additional bar findings. Both original Step-6 installations were restored.
The older staging/acceptance rows below are not a live deployment inventory.

The source corrections cover #44 (regional extra widths and grouped-center
budget), #46 (slot-neutral new V1 family replacements with existing dynamic
placements preserved), and #23 (host-selected clone resolution and metadata).
Separately authorized for Beta.12 is one optional V1 center slot, explicitly
added in edit mode, for at most two total. Existing layouts are not expanded
on load. The ghost correction uses the attached Window API, retains its image
result, rejects stale capture callbacks, and removes the duplicate Bottom
offset. The real layer delegates to an offscreen render-tested visual.
There is no split-schema migration, new overflow policy, or dev-host capability
bypass. The exact
production-boundary ledger changes the resolver's `entryPointUrl` occurrence
count from five to six for cache revalidation; its host-integration owner and
single component-creation route are unchanged.

These changes need a new exact candidate, complete automated gates, independent
review, and affected physical acceptance. Ghost and two-slot-center physical
acceptance remain open; offscreen pixel/scale checks are not Wayland or physical
mixed-scale evidence. No corrected package has been deployed, and no publication
is authorized.
Historical acceptance of `d077efb` is not acceptance of the changed payload.

## Candidate boundary

The normal lifecycle supports only these predecessor identities:

- public `0.1.1-beta.11` at
  `adbb11068e9c77561ff0c3d1b8fca5212653ae3c`, including its package identity;
- the exact Step-5 tip at
  `5154c020a44d71139a6614a183ec91021b9772c1`;
- the exact current Beta.13 payload after installation.

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

The Beta.15.3 worktree's primary source and installed-package compatibility
contracts target Omarchy 4.0.4. This is candidate gate configuration, not
physical acceptance. The published Beta.13 package was physically accepted on
Omarchy 4.0.3 using one physical output; Beta.14 still
requires its own physical output and coredump acceptance.

| Component | Accepted identity |
| --- | --- |
| Physical Beta.13 release host | Omarchy `4.0.3`; single-output acceptance |
| Candidate Omarchy | `omarchy 4.0.4-1` |
| Candidate Omarchy settings | `omarchy-settings 4.0.4-1` |
| Candidate official source | `v4.0.4`, `c668141e9c42b13c80c9ca4ea108e11708c5e8a5` |
| Quickshell | `quickshell 0.3.1-1` |
| Candidate installed-package profile | `installed-package-v4.0.4` |
| Candidate source-parity profile | `installed-source-parity-v4.0.4` |
| Optional compatibility source | `v4.0.2`, `346e69e1cec6c4e8924531874af6ba010a1bc99e` |
| Agents reference | `v4.0.0`, retained for that isolated contract only |
| Forward reference | `ed7bae4ac5a570e9df307486e0202fdafcc6ee24` |

The installed package and pinned `v4.0.4` source have exact `shell` and
`config` parity. Installed `/usr/share/omarchy/bin` links resolve to the source
payload except for the three source-only maintenance helpers `omarchy-debug`,
`omarchy-debug-idle`, and `omarchy-upload-log`. The machine-readable manifests
bind the complete consumed subtrees. The immutable 4.0.2 manifests remain
available through the explicit `SHIBUMI_OMARCHY_BASELINE_VERSION=4.0.2`
compatibility selector; candidate release jobs pin 4.0.4 directly.

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
| Exact 24-plugin source contract | Passed for the exact published payload |
| Omarchy 4.0.3 installed-package baseline | Passed |
| Omarchy 4.0.3 source-parity baseline | Passed |
| Omarchy 4.0.2 compatibility manifests | Retained and schema-validated |
| Forward-compatibility baseline | Passed |
| Bluetooth detached-record and stale-identity regression | Passed |
| Lifecycle predecessor and all-journal admission regression | Passed |
| Snapshot FD identity, cleanup, rebind, and crash-simulation regressions | Passed with independent review |
| Full Python, QML, shell, documentation, and package suites | Passed before publication |
| Reproducible exact-commit archive and checksum | Passed |
| AUR package rehearsal with exact installed inventory | Passed; AUR publication deferred |
| Physical presentation and host-return acceptance | Passed on Omarchy 4.0.3 for V1/V2, stock-bar return, style, and top/bottom on `eDP-1` |
| Package-bound lifecycle | Passed with all 24 plugins |
| Machine 2 | Scoped Beta.13 physical round passed without a new Quickshell coredump |
| GitHub prerelease | Published as `v0.1.1-beta.13` |
| AUR publication | Deferred |

Fixtures prove deterministic boundaries but do not replace physical Network,
Bluetooth, output, suspend/resume, notification, drag/drop, or visual checks.
The published physical round used one output; no multi-output result is claimed.
Enterprise Wi-Fi, mixed scale, multi-output, and display hotplug remain tracked
stable-release gates where hardware or credentials were unavailable.

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

Beta.13 is published as a GitHub prerelease from its accepted exact commit.
This record does not claim AUR publication or physical multi-output,
enterprise-Wi-Fi, mixed-scale, or display-hotplug acceptance.
