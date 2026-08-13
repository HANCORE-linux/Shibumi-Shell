# Changelog

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
