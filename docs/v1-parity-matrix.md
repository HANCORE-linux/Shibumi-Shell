# QS Rise V1 to Shibumi parity matrix

> **Document status: Current parity tracker.** This matrix tracks the V1
> outcome by feature. It does not redefine the canonical contract in
> `../ARCHITECTURE.md`.

Shibumi must reproduce the approved QS Rise V1 user experience while running as a
native Omarchy Shell plugin. This matrix prevents a structurally clean Shibumi from
silently becoming a reduced product.

The source-surface inventory is executable: `contracts/v1-feature-evidence.json`
maps every one of the 61 QML files in the V1 `modules/` and `panels/`
directories to a concrete Shibumi implementation and regression evidence (or
to an explicit Quattro lifecycle adaptation). The
`tests/v1-feature-evidence-regression.sh` gate rejects missing, duplicate, or
newly unaccounted V1 surfaces. This proves functional inventory coverage; the
same-state visual matrix below remains the separate presentation gate.

Status values:

- **Foundation**: the Shibumi contract exists and has runtime evidence.
- **Partial**: ownership or a substantial implementation exists, but the V1
  user-facing contract or runtime acceptance is incomplete.
- **Planned**: no production port has started.
- **Adapt**: preserve the user outcome through an Omarchy-owned service or
  lifecycle instead of copying V1 infrastructure.
- **Excluded**: requires an explicit product decision and rationale; nothing is
  excluded by default.

| Area | V1 behavior to preserve | Shibumi strategy | Status |
| --- | --- | --- | --- |
| Shibumi default bar | Groups, spacing, chrome, visual hierarchy and motion | Registry-only `hancore.shibumi.bar` host over independent feature plugins; fresh Quattro composition passes while final Wayland parity remains | Partial |
| Multi-monitor | One robust bar per output with screen-local panels | Shared native screen/output core for every style | Partial |
| Bar position | Top and bottom layouts | Shared horizontal window lifecycle; corrected bar, Control Center, Display, AI, power-profile, and Bluetooth routing pass on the physical eDP-1 output | Partial; complete Bottom state comparison and physical multi-output remain |
| Host widgets | Existing configured Omarchy widgets remain usable | All fixed G1-G15 groups resolve registered plugin entry points; unassigned official/custom layout entries remain regional extras | Foundation |
| Compact mode | V1 compact presentation and sizing behavior | Versioned presentation tokens plus per-widget compact delegates; CPU, memory, audio, media FULL/muse, network, battery, power profile, brightness, and Bluetooth implemented locally | Partial; G9 passes its focused single-output gate while G8 and final mixed-scale acceptance remain |
| Control palette | Current V1 colors 01-07 plus foreground, contrast-aware labels, and four-column selection | Process-wide semantic theme map over Quattro roles, canonical/legacy state normalization, and a live-radius four-column Control Center picker | Accepted on the validation system; targeted and complete suites plus radius 12/6 with color02/color06 real-session captures pass |
| G9 FULL/muse | Current V1 24-band Cava, vinyl mark, transport state, click play/pause, and wheel previous/next | Keep the official media state/action owner and use one bounded, lazy process-wide spectrum service; views own presentation only | Ported; multiple real players, native source switching, actual empty/two-source Top/Bottom MediaPanel, failure/retry, lifecycle/resource, and Top/Bottom bar gates pass on the validation system. Remaining degraded/failure presentation and physical multi-output remain |
| Split layout | V1 section splitting and reveal behavior | Positional model, host persistence, hover markers, run chrome, and boundary treatment are implemented locally; Wayland acceptance remains | Partial |
| Drag and drop | Swap groups within and across sections | Root mutation controller plus isolated per-output targets, ghost, invalid-drop return, and cleanup are implemented; Wayland acceptance remains | Partial |
| Workspaces | Persist 10/5/active modes, default/numbers/magic styles and detail panel | Shared Hyprland model, validated Quattro action adapter, lazy screen-local panel, and token-backed V1 bar presentation implemented locally; real-Wayland acceptance remains | Partial |
| Core widgets | Title, clock, tray, audio, media, network, power and battery | Local facades retain official owners where possible; G3/G8 placement plus weather/status/update presentation are implemented, while several panel and runtime gates remain open | Partial |
| CPU and memory | Shared telemetry, compact/full widgets and detail panels | One procfs owner; lazy GPU probe and screen-local panels | Partial; G4 Memory now matches the original 320×201 V1 card and exact Top/Bottom placement. G5 CPU now restores the original `CPU · GPU` header, 16 px CPU/GPU rows, GPU temperature/VRAM rows, separators, 8 px rhythm, 12 px insets, and 320×150 populated / 320×126 degraded geometry while keeping the lazy shared GPU probe. Remaining hover, live-GPU recovery, and multi-output states remain. |
| Status widgets | Idle, DND, recording, Voxtype and related indicators | One process-wide adapter over official idle/DND state plus bounded recording/Voxtype reconciliation; active-only V1 view in G8. Idle/DND mutation, the complete recording-indicator lifecycle, and a real Voxtype recording/transcription cycle pass on the validation system. | Partial |
| Panels | V1 panel workflows, exact visible presentation, states, motion, and screen-local anchoring | Quattro owns services, actions, focus, routing, and lifecycle; Shibumi owns V1-faithful surfaces and controls. Several groups still expose stock or approximate Quattro presentation and therefore remain incomplete. | Partial |
| Application menu | V1 had a separate application/command menu | Deliberately excluded; Omarchy's native menu is authoritative and Shibumi registers no competing menu or service | Host-owned |
| G1 Control Center | V1 wordmark plus complete Shibumi bar configuration | Independent `hancore.shibumi.control-center` widget/panel reusable by every Shibumi bar host | Partial; density, selection states, split/Reactor controls, widget/compact settings, workspaces, appearance, position, logo, picker controls, and the current eight-choice palette are implemented. Top/Bottom main-surface routing and the focused palette gate pass on the validation system; remaining subpages, multi-output, and the final state matrix remain. |
| Notification center | Bell, DND, history, actions and popup behavior | Local V1 bell/badge facade delegates DND, history, actions, and popup ownership to the single official `omarchy.notifications` component/service | Partial; local lifecycle and routing pass, real Wayland actions and placement remain |
| OSD | Volume, brightness and status feedback | Keep official OSD until Quattro exposes an exclusive selectable OSD owner | Adapt |
| Image pickers | Tanzaku, Carousel and Hearthstone | One shared controller/cache with V1-faithful Tanzaku and Hearthstone presentation-only views; delegate the duplicate carousel role to Quattro's native image picker | Partial; Tanzaku and the revised Hearthstone wallpaper view are runtime accepted on the validation system, including navigation, close cleanup, V1 idle-inhibitor glyphs, native-picker coexistence, a 2,091 ms content-unique 4K cold preview, and a 275 ms 11/11-ready warm reopen. Theme/media rendering, remaining Bottom coverage, and physical multi-output gates remain |
| Media browser | Screenshots, videos, posters and cleanup | Shared lazy controller with bounded workers and open/copy/trash actions | Partial; scan/open/close and cleanup pass on the validation system, while real action feedback and edge-case acceptance remain |
| Themes/wallpapers | Discover, preview and apply supported sources | Omarchy theme APIs plus current and user background roots through one shared scanner | Partial; discovery and previews pass on the validation system, while apply and failure-path acceptance remain |
| AI usage | Claude, Codex and OpenCode quota state and warnings | One process-wide V1 single-provider facade; lazy official Claude/Codex scanners and one cache-free OpenCode SQLite adapter | Partial; OpenCode runtime, legacy IPC, and Top/Bottom product-panel routing are accepted on the validation system; Claude/Codex account-data and physical multi-output gates remain |
| Reactor | Approved modes, gating and event behavior | Backend-free Modes 1-6; one lazy root event/quote source for Modes 7-8; style owns only per-output rendering | Partial; all modes are implemented, Mode 0 is zero-work, and Modes 1-8 now have single-output the validation system visual evidence. Mode 7/8 lifecycle and bounded CPU are characterized; physical multi-output acceptance remains. |
| Package/theme updates | User-visible checks, package apply, theme review and apply | Independent G3 Update Center plugin with read-only package/theme scans and actions delegated to visible Omarchy-owned commands | Partial; the compact V1-style package and theme tabs load with real the validation system state, badge preferences, pinned theme review/update/reinstall/remove controls, and no copied shell updater. Real theme apply/failure, package apply, bottom placement, and multi-output remain release gates. |
| Shell self-update | V1 pinned standalone updater and progress UI | Omarchy plugin install/update/rollback lifecycle | Adapt |
| Install/uninstall | Standalone scripts and post-boot hooks | Transactional Shibumi suite installer stages independently validated Omarchy plugins; Omarchy owns runtime activation | Adapt |
| User configuration | V1 cache/config behavior | Host-owned `shell.json` plus versioned Shibumi feature state | Adapt |

## Parity Gate

A row is not complete from visual resemblance alone. Completion requires the
relevant single-monitor, multi-monitor, split/drag, lifecycle, performance, and
failure-path checks. Any intentional difference from V1 must be recorded here
before implementation is accepted.

Likewise, functional equivalence alone does not complete a visible row. Every
shipped widget, tooltip, panel, picker, and Control Center state must pass a
side-by-side QS Rise V1/Shibumi visual comparison at the same theme and scale. Quattro theme
and scale tokens may feed the V1 semantic-token adapter, but stock Quattro
control geometry or styling is not an accepted substitute.

There is no reduced-feature Shibumi release path. Shibumi must meet or exceed the
approved V1/Shibumi behavior, visual finish, responsiveness, resource use, and
stability. Using an official Quattro widget as a temporary backend-compatible
fallback does not complete the corresponding row and does not lower its
acceptance threshold.
