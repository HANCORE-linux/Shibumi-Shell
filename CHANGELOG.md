# Changelog

## [0.1.1-beta.14.1] - 2026-09-16

Same product behavior as Beta.14; only version constants changed in the
product payload.

### Changed

- Runtime release gate installs the Beta.13 package as predecessor (Step-5
  predates Omarchy 4.0.3) and adds a fresh-install arm on an empty host
- Contract: Beta.14 source revisions admitted as `source-beta.14`;
  `public-beta.14.1` is the package identity

### Release history

- v0.1.1-beta.14 was tagged but never published: its release-validation gate
  failed on the obsolete Step-5 predecessor fixture, not on the product

### Known limits

- Step-5 checkouts cannot be updated in place on Omarchy 4.0.3; run
  `uninstall --keep-settings` from the Step-5 checkout, then install from the tag
- Source checkouts outside the admitted revisions require the same sequence
  from their exact checkout (#56, supervised; general recovery is Beta.15)
- `QQmlVMEMetaObject` invalid-context warnings on output loss/return (8) and
  third-party plugin removal (349); no functional impact observed, unattributed
- G3 status-composite children do not restore after output return
  (separate finding)
- #54 pending reporter confirmation; evidence is one DP-1 hot-unplug cycle
  on pre-final `4d9744c`
- AUR publication deferred

## [0.1.1-beta.14] - 2026-09-16

### Added

- Added a passive owner-local presentation library for shared Shibumi surfaces,
  replacing per-plugin copies without adding a runtime owner or process
- Added bounded widget-pipeline census and warning evidence that observes Loader
  provenance without triggering recovery

### Changed

- Kept the Native Catalog warm-PSS ceiling at 512 KiB while recording three
  cold reconstruction cycles separately, baselining after them, and checking
  exactly three warm cycles; exact Beta.13 and the candidate pass, while the
  synthetic 2 MiB-per-cycle retention mutant still fails
- Removed unused root/shared compatibility copies and retired synchronization
  scripts while retaining the 24-plugin, 18-owner, one-process architecture
- Updated the primary installed-package and source-parity contracts to Omarchy
  4.0.3, retaining 4.0.2 as an explicit optional compatibility baseline
- Restored top-level widgets after hard monitor output loss without an
  additional recovery rescan; verified on pre-final candidate `4d9744c` by one
  physical DisplayPort hot-unplug cycle on single-output DP-1 (all 16 slots
  restored). The embedded G3 status composite did not restore its children and
  is tracked separately. Reporter confirmation pending (#54).

### Fixed

- Bound Beta.14 package admission to the contract's exact plugin and payload
  digests, rejecting mutated and unknown package identities
- Disabled Git replacement-object resolution in release-evidence gate
  environments
- Decoupled Network telemetry projection and demand from derived connection
  state, eliminating the `telemetryProjection` and `kind` binding loops
- Guarded hosted-widget popout release during live teardown, preventing the
  three-output `releasePopout` warning reported in #51
- Admitted the exact published Beta.13 source and package identities and made
  unsupported status diagnostics read-only and redaction-safe, addressing #53
- Restored Quick Access picker presentation and output ownership when the
  service has a scoped host rather than a direct Bar reference
- Preserved normalized AI usage shape and freshness through empty, malformed,
  stale, and restored provider data

### Validation

- The native three-cycle output-return comparison measured one startup prime
  and no later rescan for the candidate; the Beta.13 control required three
  explicit recovery rescans, four rescans total including its startup prime
- The maintained Native Catalog 3+3 gate measured 0 KiB warm growth for exact
  Beta.13 and the candidate in its first accepted run; the 512 KiB assertion is
  unchanged
- During a 30-minute live single-output DP-1 window on the exact final
  candidate, the maintainer exercised Wi-Fi off/on, every V1/V2 form, five G4
  toggles, workspace style, lock/unlock, and third-party removal with no binding
  loop or `TypeError` in the baseline-scoped log diff

### Known limits

- Unattributed `QQmlVMEMetaObject` invalid-context warnings appear during output
  loss/return (8) and live third-party plugin removal (349); no functional
  impact observed, root cause not yet attributed
- Source checkouts installed between tagged releases must be uninstalled with
  `--keep-settings` from their exact commit before installing a newer checkout
- Local and Machine 2 package installation, physical monitor-power acceptance,
  coredump checks, and reporter confirmation for #54 remain separate gates
- The tcmalloc allocation diagnostic was aborted without a product finding;
  general responsiveness attribution remains paused
- Physical multi-output acceptance and AUR publication remain deferred

## [0.1.1-beta.13] - 2026-09-12

### Fixed

- Kept the admitted `shell.json` rollback snapshot bound through transaction end
  to a no-follow regular-file file descriptor (FD)
- Checked the snapshot name, held object, size, and digest before restore,
  rejecting replacement and in-place mutation, including inode reuse
- Added regressions for descriptor cleanup, drained-baseline rebinding, and
  crash-simulation recovery paths

## 0.1.1-beta.12: Step 5 release line and Bluetooth identity fix

Local release candidate; publication remains gated on fresh physical acceptance.

### Added

- Added an optional second V1 center slot through the existing edit-mode `+`,
  preserving saved one-slot layouts until explicitly extended
- Included the completed Step 5 native Network payload on a release line based
  directly on the Step 5 tip
- Added exact Omarchy 4.0.2 installed-package and source-parity contracts
- Added pre-mutation lifecycle admission for exact Beta.11, Step-5-tip, and
  current-release identities, with complete journal inventory before recovery

### Changed

- Bluetooth panels now receive detached primitive device records and consume
  typed action results through explicit `.ok` checks
- Bluetooth mutations resolve the current device and adapter incarnation and
  dispatch exactly one retained Omarchy helper action
- Release publication now uses exact-commit archives, a draft upload, and
  remote asset digest verification before publication

### Fixed

- Included regional extras and center siblings in existing responsive budgets
- Made new V1 family replacements slot-neutral without relocating existing providers
- Followed host-selected enabled clones for widget admission, components and
  metadata, preserving active clone identity and entry settings
- Refused ambiguous base-slot provider removal unchanged; move the provider
  back to an extra before removal. Control Center uninstall preflights this case
- Corrected drag-ghost capture/window lookup, image lifetime, stale callbacks,
  and duplicated Bottom positioning; physical revalidation remains required
- Rejected stale, malformed, ambiguous, or replacement Bluetooth identities
  without dispatching a device mutation
- Rejected Step-6 Power-registration state and unknown journal schemas before
  recovery or any other lifecycle mutation
- Prevented managed install and migration from stopping Quickshell while an
  asynchronous plugin rescan is still incubating QML objects

### Known limits

- Existing Step-6 development installations need a separate reviewed rollback;
  the normal Beta.12 updater intentionally refuses them
- The retained Omarchy Bluetooth and audio-route helpers remain explicit
  compatibility dependencies
- Fresh physical Network and Bluetooth acceptance is required before publication

## 0.1.1-beta.11: Native Audio and Bluetooth cutover

Public beta candidate for 2026-08-23.

### Added

- Completed the Step 2 compact production-boundary transition and Step 3 Bluetooth audio-route seam
- Activated native PipeWire Audio and BlueZ/Bluetooth owners without duplicating backend ownership
- Added primitive Audio panel snapshots, stable IDs, typed action results, and live app-stream controls
- Added local physical acceptance for Audio and a Jabra Evolve2 55 Bluetooth output

### Changed

- Kept the 24-plugin contract and one production Quickshell process
- Coalesced mouse-wheel volume bursts and retained the effective audio sink during asynchronous refresh
- Aligned output, microphone, and app percentage typography and right-aligned the output value

### Fixed

- Prevented stale resolver updates from redirecting volume mutations to the default sink
- Preserved last-known output volume/mute state across temporary sink loss and reconnects
- Completed Bluetooth remove, fresh-pair, reconnect, route, and restore validation

### Known limits

- Physical second-display, mixed-scale/hotplug, and enterprise-Wi-Fi acceptance remain stable-release gates
- Machine2 validation is intentionally out of scope for this public beta
- AUR publication remains unavailable until the package name can be registered

## 0.1.1-beta.9: Host-owned Notifications compatibility

Release candidate for 2026-08-20.

### Added

- Added a narrow Omarchy Notifications adapter supporting current and legacy host model contracts
- Added explicit `Recent` and `Live` notification tabs with host-owned history replay
- Added DND, dismiss, clear, stale-replay, host-replacement, and unavailable-state coverage

### Changed

- Kept Omarchy as the sole Notifications owner; Shibumi exposes only primitive rows and typed actions
- Added `color04` highlighting for Recent and `color03` highlighting for Live
- Preserved Clear all and per-notification dismiss actions on both tabs

### Fixed

- Restored Shibumi notification presentation for Omarchy's current `popupModel` contract
- Preserved late live notifications during history replay and filtered stale replay results after Clear all
- Confirmed real Vesktop notifications arrive through the host service and appear in host history

### Known limits

- Physical multi-output, mixed-scale, hardware, final Machine 2 UI, and full visual-freeze acceptance remain explicit release gates
- The compatibility baseline is pinned to official Omarchy `4.0.0-1` (`v4.0.0`)
- AUR publication remains unavailable until the package name can be registered

This changelog records user-visible Shibumi changes.

## 0.1.1-beta.8: Layout protection and update hardening

Release candidate for 2026-08-13.

### Added

- Added independent, opt-in V1 and V2 layout locks with each generation's edit mode retained as a temporary override
- Added V1/V2 widget appearance controls, reset actions, and clearer cross-section transfer controls
- Added Omarchy Agents usage support and third-party plugin update visibility

### Changed

- Compacted each Bars layout section into a no-scroll Edit, Lock, and Restore row with matching V1/V2 headings and a visible lock toggle
- Refined telemetry units, widget spacing, theme-update actions, and plugin-update labels and review status
- Scoped OpenCode usage to the current day while retaining ready Agents providers without current usage

### Fixed

- Kept Shibumi bars opaque without changing or materializing Omarchy's `bar.transparent` preference
- Drained the managed Quickshell process before payload swaps and blocked updates while the session lock is active
- Enforced exclusive bar-widget ownership and hardened group teardown across output lifecycle changes
- Restored the Omarchy plugin diff pager and kept update panels from covering launched review or updater actions
- Selected the current `omarchy.agents` replacement when legacy model-usage providers are absent, while retaining the complete legacy contract on older hosts
- Kept Network speed tests entirely inline by running `omarchy-network-speedtest` from Shibumi without loading Omarchy's standalone speed-test panel

### Known limits

- Physical mixed-scale multi-monitor, enterprise Wi-Fi, remaining device-backed Bluetooth, clean-chroot packaging, and safe nested-compositor lifecycle acceptance remain external stable gates
- AUR publication remains unavailable until the package name can be registered

## 0.1.1-beta.7: Network label stability

Release candidate for 2026-08-07.

### Fixed

- Measured bounded Network labels independently from their rendered width, preventing V2 Wi-Fi and shared text-mode binding loops
- Covered Wi-Fi transitions across V1 and V2 full, icon, and text modes, including long bounded labels

### Known limits

- Physical mixed-scale multi-monitor, enterprise Wi-Fi, remaining device-backed Bluetooth, clean-chroot packaging, and safe nested-compositor lifecycle acceptance remain external stable gates
- AUR publication remains unavailable until the package name can be registered

## 0.1.1-beta.6: Stable-readiness lifecycle hardening

Release candidate for 2026-08-07.

### Changed

- Classified stable GitHub releases independently from prereleases with validated SemVer handling
- Restored the exact saved Omarchy layout when first returning from Shibumi
- Made unavailable Quickshell logs an explicit Health warning instead of a false clean result
- Corrected current installation and architecture documentation to the 24-plugin contract

### Fixed

- Published suite and continuity-manager recovery transactions only after complete durable preparation
- Serialized continuity recovery with active bar-switch workers
- Persisted journals, staged payloads, namespace renames, configuration, install state, backup archives, and cleanup in crash-safe order
- Rejected malformed, incomplete, or symlinked recovery state before changing live files or stopping the shell
- Made interrupted transaction preparation, archive copying, and cleanup automatically resumable
- Waited for an authoritative stock-shell ping and isolated lifecycle-evidence restarts and compositor probes from the production session
- Prevented hidden official Audio and Network keyboard panels from flashing stock Omarchy UI before Shibumi compatibility redirects settle

### Known limits

- Physical mixed-scale multi-monitor, enterprise Wi-Fi, remaining device-backed Bluetooth, clean-chroot packaging, and safe nested-compositor lifecycle acceptance remain external stable gates
- AUR publication remains unavailable until the package name can be registered

## 0.1.1-beta.5: Contract and recovery hardening

Release candidate for 2026-08-07.

### Changed

- Made Omarchy and predecessor baseline identity checks deterministic across C and UTF-8 locales
- Bound release promotion to revision-specific lifecycle, host, and checksummed command evidence
- Kept third-party plugin updates behind Omarchy's authoritative changed-code review prompt

### Fixed

- Retained transaction journals and snapshots when rollback itself fails, allowing later recovery
- Excluded generated Python caches consistently from source staging, payload hashing, and provenance
- Reported retired plugin state without crashing `shibumi-shell status`
- Restarted the shell at the managed repair ownership boundary instead of hot-reloading a replaced bar provider
- Kept popout and connected-panel ownership independent across physical outputs
- Preserved declarative bar visibility after layer-window recovery
- Restored Calendar and Power compatibility routing for the installed Omarchy shortcuts
- Restored the process-wide Audio IPC owner and deliberate Network IPC presentation redirects

### Known limits

- Physical mixed-scale multi-monitor, enterprise Wi-Fi, and remaining device-backed Bluetooth acceptance stay explicit external gates
- AUR publication remains unavailable until the package name can be registered

## 0.1.1-beta.4: Shell and lifecycle stabilization

Release candidate for 2026-08-04.

### Added

- Added the Pacman workspace presentation with V1 and V2 animation support
- Added bounded Carousel picker previews and expanded GPU device diagnostics
- Added storage selection, telemetry, health details, and theme-aware panel controls

### Changed

- Reworked the audio panel with matching mixer controls, native device labels, grouped profiles, and uninterrupted output switching
- Removed unreliable GPU process telemetry while retaining device, driver, utilization, temperature, and memory data
- Refined the Control Center return surface for the stock Omarchy bar
- Aligned Storage controls and active states with the shared panel control system

### Fixed

- Prevented stock Omarchy widgets from contaminating Shibumi layouts during activation
- Prevented the continuity manager from overwriting a trusted Shibumi profile with a mixed stock layout
- Kept the Control Center alive while widgets change between active and inactive states
- Restored V1 widget panel interaction, network rendering, and variant switching stability
- Normalized AI usage percentages before applying usage-fill thresholds
- Kept audio labels, mixer levels, profile grouping, and volume spacing stable
- Restored workspace visibility beyond the persistent range and corrected marker scaling
- Prevented the Update Center open state from freezing

### Known limits

- AUR registration remains unavailable, so `shibumi-shell` cannot be published there yet
- Physical multi-monitor, enterprise Wi-Fi, and the remaining Bluetooth workflows still block a stable release

## 0.1.1-beta.3: Arch package candidate

Released 2026-08-03.

### Added

- Immutable Arch package payload under `/usr/share/shibumi-shell` and stable
  `/usr/bin/shibumi-shell` lifecycle command
- Explicit Omarchy Quattro host-contract preflight before user-state mutation
- Package-aware Health reporting for Pacman, staged payload, and manual AUR
  update checks
- Reproducible release archive, local `makepkg` rehearsal, dependency contract,
  and SHA-pinned GitHub release gate
- Transactional source-checkout to package migration and an explicit
  `--allow-downgrade` package rollback path
- Shibumi-specific host compatibility record for the validated Omarchy and
  Quickshell builds

### Changed

- All 24 plugin manifests and the suite contract now share the beta version
- Retired the Shibumi-owned application menu and its obsolete configuration;
  Omarchy is now the sole application-menu owner, while existing G1 logo
  choices migrate to the dedicated launcher setting
- Use Quattro's full shell restart for install, migration, activation,
  deactivation, and uninstall instead of hot-swapping bar owners through
  `reloadConfig`
- Drain the previous Quickshell instance before publishing a new bar-owner
  configuration, including rollback and interrupted-transaction recovery
- Record the pre-Shibumi bar and restore its complete layout on deactivate or
  uninstall; older install states fall back to Quattro's stock bar definition
- Package transactions install no hooks and never mutate a user's Omarchy
  configuration; setup, update, repair, and removal remain explicit user
  lifecycle operations

### Fixed

- Removed the Update Center panel-state binding loop
- Kept video and screenshot thumbnails stable while previews finish loading
- Restored outside-click dismissal across all picker modes
- Added mouse-wheel navigation to themes, wallpapers, screenshots, and videos
- Restored widget loading for hosts that use the registry fallback
- Made release-archive checksums independent of the Python host's Gzip OS
  header
- Clarified that source installation remains transitional until AUR publication

### Known limits

- AUR registration is currently unavailable, so `shibumi-shell` cannot be
  published there yet
- The candidate package still requires complete validation-system install, upgrade,
  rollback, uninstall, and bar-switch acceptance before publication

## 0.1.1-beta.2: Unpublished release candidate

Tagged 2026-08-03, but not published. Its release gate exposed a
Python-version-dependent Gzip header; `0.1.1-beta.3` supersedes it.

## 0.1.0: Private alpha

Released 2026-07-29.

### Added

- 25 native Omarchy Quattro plugins with one selectable Shibumi bar
- V1 and V2 bar layouts, colors, widget modes, panels, pickers, and workspace styles
- Transactional install, migration, activation, update, rollback, and uninstall
- Per-bar layout continuity between Shibumi and Omarchy
- CPU package, hottest-core, GPU, NVMe, and memory temperature selection
- Machine-readable V1, standalone V2, and embedded V2 evidence inventories
- GitHub issue templates for bugs, features, and third-party host compatibility

### Fixed

- Restored the return path from Omarchy to Shibumi in the Control Center
- Detected `/usr/share/omarchy` when `OMARCHY_PATH` is absent
- Adopted markerless suite-owned alpha plugins during a safe update
- Rejected missing production panel types in the center runtime smoke
- Included Frame and Aurora streak in the workspace-style contract
- Waited for every workspace-style control before marking Appearance ready
- Aligned the Bluetooth panel controls with Quattro and suppressed unreliable
  phone battery percentages
- Closed active panels before idle and screensaver bar pre-hide to prevent
  detached or shifted popouts
- Kept the horizontal bar host edge-local while moving edit dismissal and drag
  feedback into dedicated per-output overlays
- Rendered V2 connected bar cutouts as true negative space and applied one
  native-shaped hosted panel connector to compatible Quattro and third-party
  widgets
- Opened the direct Git installer from **Add plugin**, gated confirmation on a
  valid repository URL, and reported installed plugins by provider family
- Reorganized user, architecture, plugin, development, release, and screenshot
  documentation

### Known limits

- The repository remains private
- Physical multi-monitor, enterprise Wi-Fi, and Bluetooth-device gates remain open
- Shibumi source updates require a trusted checkout and `shibumi-suite update`

[0.1.1-beta.14]: https://github.com/HANCORE-linux/Shibumi-Shell/compare/v0.1.1-beta.13...v0.1.1-beta.14
[0.1.1-beta.13]: https://github.com/HANCORE-linux/Shibumi-Shell/compare/v0.1.1-beta.12...v0.1.1-beta.13
