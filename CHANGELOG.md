# Changelog

This changelog records user-visible Shibumi changes.

## 0.1.0: Private alpha

Released 2026-07-29.

### Added

- 25 native Omarchy Quattro plugins with one selectable Shibumi bar
- V1 and V2 bar layouts, colors, widget modes, panels, pickers, and workspace styles
- Transactional install, migration, activation, update, rollback, and uninstall
- Per-bar layout continuity between Shibumi and Omarchy
- CPU package, hottest-core, GPU, NVMe, and memory temperature selection
- Machine-readable V1, standalone V2, and embedded V2 evidence inventories

### Fixed

- Restored the return path from Omarchy to Shibumi in the Control Center
- Detected `/usr/share/omarchy` when `OMARCHY_PATH` is absent
- Adopted markerless suite-owned alpha plugins during a safe update
- Rejected missing production panel types in the center runtime smoke
- Included Frame and Aurora streak in the workspace-style contract
- Waited for all eight workspace-style controls before marking Appearance ready
- Aligned the Bluetooth panel controls with Quattro and suppressed unreliable
  phone battery percentages
- Closed active panels before idle and screensaver bar pre-hide to prevent
  detached or shifted popouts
- Reorganized user, architecture, plugin, development, release, and screenshot
  documentation

### Known limits

- The repository remains private
- Physical multi-monitor, enterprise Wi-Fi, and Bluetooth-device gates remain open
- Shibumi source updates require a trusted checkout and `shibumi-suite update`
