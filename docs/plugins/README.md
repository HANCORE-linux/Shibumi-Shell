# Shibumi plugin catalog

Status: reference

Shibumi `0.1.1-beta.8` contains 24 independently registered Omarchy plugins. The
default suite profile installs all of them as one verified transaction.

The authoritative inventory is
[`../../contracts/plugin-suite-v1.json`](../../contracts/plugin-suite-v1.json).
Each plugin's `manifest.json` defines its Omarchy kinds and entry points.

## Core plugins

| Plugin | Role |
| --- | --- |
| `hancore.shibumi.bar` | Selectable full-bar host |
| `hancore.shibumi.state` | Validated persistent Shibumi configuration |
| `hancore.shibumi.control-center` | G1 Control Center and bar wordmark |
| `hancore.shibumi.reactor` | Cross-feature event choreography |
| `hancore.shibumi.telemetry` | Shared process-wide telemetry |
| `hancore.shibumi.power-state` | Shared battery and power-profile state |

## Feature plugins

| Plugin | Role | Primary surface |
| --- | --- | --- |
| `hancore.shibumi.workspaces` | G2 | Workspace widget and service |
| `hancore.shibumi.update-center` | Update owner | Arch and Git-theme update state |
| `hancore.shibumi.status` | G3 | Tray and notification presentation |
| `hancore.shibumi.memory` | G4 | Memory widget and panel |
| `hancore.shibumi.cpu` | G5 | CPU widget, panel, and GPU telemetry adapter |
| `hancore.shibumi.audio` | G6 | Audio widget and panel |
| `hancore.shibumi.ai` | G7 | AI usage widget and panel |
| `hancore.shibumi.center` | G8 | Clock, weather, calendar, and update presentation |
| `hancore.shibumi.media` | G9 | Media controls and visualization |
| `hancore.shibumi.quick-access` | G10 | Theme, wallpaper, and picker workflows |
| `hancore.shibumi.network` | G11 | Network widget and panel |
| `hancore.shibumi.battery` | G12 | Battery widget and panel |
| `hancore.shibumi.brightness` | G13 | Monitor brightness widget and panel |
| `hancore.shibumi.power-profile` | G14 | Power-profile widget and panel |
| `hancore.shibumi.bluetooth` | G15 | Bluetooth widget, service, and panel |
| `hancore.shibumi.temperature` | G16 | Selectable temperature source |
| `hancore.shibumi.gpu` | G17 | GPU widget and panel |
| `hancore.shibumi.storage` | G18 | Storage widget, service, and panel |

AI usage, power profile, and Bluetooth are disabled by default in the V1
configuration. Hardware-dependent widgets may remain hidden when their
required device or service is unavailable.

## Host service reuse

Shibumi uses native Quattro owners where they provide sufficient state and
actions, including media, audio, notifications, tray, background, network,
monitor, Bluetooth, weather, idle, and system-update services.

Shibumi owns its presentation and adds a narrow adapter only where the host
contract cannot produce the approved behavior. It must not create a duplicate
platform owner.

## Installation model

Quattro's repository installer expects one root manifest. Shibumi instead has
24 top-level plugin roots and uses `scripts/shibumi-suite` to install, update,
verify, roll back, and remove them together.

Individual plugin directories are not advertised as unsupported ad hoc
installs. Use the suite adapter so dependencies, ownership markers, config
continuity, and runtime verification remain intact.

Shibumi deliberately does not ship an application launcher menu. Omarchy's
native menu remains the sole owner. Read [plugin compatibility](../plugin-compatibility.md)
before using visible Shibumi widgets with another bar host.
