# V1 Output Lifecycle And Resume Audit

> **Document status: Normative supporting contract and validation evidence.**
> The lifecycle requirements remain binding. `release-readiness.md` records
> which physical acceptance gates currently pass.

Date: 2026-07-22

This audit defines the V1 behavior that the Omarchy Quattro plugin must preserve
for multiple outputs, output power cycles, suspend, hibernate, and resume. It is
based on the V1 commit history and current source, not on commit subjects alone.

## V1 History

| Commit | Release | Proven contract |
| --- | --- | --- |
| `6553da8` | `v2.3.1` | Filters nameless and 0x0 Wayland placeholder screens, recreates the bar delegate when a real `ShellScreen` disappears and returns, and retries a lost or closed layer window without reloading the complete shell. |
| `406f91f` | `v2.3.2` | Expands the lifecycle from the first real output to one bar per real output. |
| `e416b98` | `v2.4.0` | Routes singleton popups to the invoking output, synchronizes layout anchors, and adds per-output popup-dismiss layers. |
| `a71e52c` | after `v2.4.0` | Closes popups and unregisters layout ownership when the active output is hot-unplugged. |
| `d19851f` | after `v2.4.0` | Routes picker/media opens to the invoking output and dismisses keyboard popups when focus moves to another monitor. |
| `f8da217` | `v2.5.1` | Prevents overlap on narrow and portrait outputs with hysteretic G8 and side-group presentation stages. |

The lifecycle foundation therefore predates `v2.5.0`; it was already included
in `v2.5.0` and gained the narrow/portrait correction in `v2.5.1`. The V1
history contains no dedicated logind `PrepareForSleep` handler. Its bar recovery
after display sleep or resume is the output/layer-window lifecycle above.

## Current Plugin Result

Implemented:

- `Bar.qml` keeps the native `Quickshell.screens` model in `Variants` and creates
  one `BarPanel` per output.
- `BarPanel.qml` rejects nameless and 0x0 placeholder screens.
- `WindowRecovery.qml` handles `resourcesLost` and `closed`, retries the
  affected layer window up to three times, and leaves other outputs running.
- Every output owns its own widget instances, panel anchors, tooltip window,
  and `DragSession`; destruction unregisters module slots, tooltip ownership,
  popout ownership, drag targets, and drag state.
- G10 picker/media IPC already resolves the focused Hyprland output and falls
  back to a live bar output.
- General bar-widget summons now prefer the explicitly requested output or
  Hyprland's focused output. Hide and open-state queries cover every live
  per-output instance instead of an arbitrary first widget.
- Horizontal side groups now use V1's four non-persistent presentation stages
  with hysteresis. Hidden groups retain user settings and order but release
  drag-target ownership until visible again.

Runtime-proven on the validation system against the official Quattro shell:

- A temporary 800x1280 headless output and the physical 1920x1080 eDP-1 output
  received independent bar instances in the same shell process.
- The narrow output selected presentation stage 3 and retained exactly G1, G2,
  G6, G8, G11, and G14. The physical output remained at stage 0.
- Moving Hyprland focus changed the selected bar instance, and a generic
  Control Center summon opened only on the focused output.
- Removing the temporary output left one real output, zero open panels, and
  the same reachable shell. The current log contained no binding loop, invalid
  QML context, or false `WindowRecovery` warning for the removed output.
- During a real automatic screensaver cycle of the pre-rename predecessor, the
  bar consumed Quattro's `omarchy.idle` service and hid its only historical
  `qsrise-bar` layer 254 ms before the fullscreen screensaver client mapped.
  The same shell process restored exactly one bar layer after wake. This is
  historical lifecycle evidence and does not accept the renamed Shibumi payload.
- A real eDP-1 DPMS cycle changed `dpmsStatus` from true to false and back to
  true. The Quickshell PID, configuration hash, and crash count remained
  unchanged; IPC, all 15 visible groups, and the single bar layer recovered.
- A real deep/S3 suspend from 13:52:13 to 13:56:36 resumed the same boot, shell
  PID, systemd unit, configuration, and single bar layer. IPC, Idle, picker,
  Reactor, and panel-closed state remained valid, with no new crash or QML
  error.
- A real S4 hibernate resumed the saved system image rather than cold-booting:
  boot ID `847c6cbb-5e77-40ee-8a67-a8057c895a2a`, shell PID `1016328`, process
  start time, configuration hash, and crash count were identical before and
  after. One shell instance and one fully opaque bar layer returned, with IPC
  reachable and no open panel or worker residue.

Runtime acceptance still open:

- Physical mixed-scale and hot-unplug-during-drag behavior has not been accepted
  on the current release payload.

## Current Quattro Treatment

Revalidated against installed Quattro package
`4.0.0.r1214.g4a02da2-1` and upstream commit
`4a02da20d58d912a74748845bc55b5ec73acd65f` on 2026-07-22.

- The stock bar also creates one `PanelWindow` per `Quickshell.screens` entry,
  but it has no `resourcesLost`/`closed` layer-window recovery. Shibumi's
  targeted `WindowRecovery` therefore remains required for V1 parity.
- Stock `summonBarWidget(pluginId)` still returns the first matching live
  widget and receives no invoking-output context. Shibumi's focused-output
  fallback is necessary locally; the missing host-level contract remains
  tracked as `QTR-008`.
- Quattro owns system sleep preparation outside the bar. Its user service
  watches logind `PrepareForSleep` through a delay inhibitor, synchronizes
  clamshell outputs, requests the session lock, and waits until it is secure.
- Quattro reconciles laptop outputs on Hyprland monitor add/remove events with
  bounded retries and a docked-laptop-only polling fallback. Wake restores
  display/keyboard brightness and reconciles clamshell state again.
- The lock service rejects nameless/0x0 screens, waits for screen stabilization,
  retries when no real output exists, and avoids immediately blanking after a
  suspended timer resumes.
- On hibernate resume, Quattro's `Restart=always` sleep monitor made one
  immediate restart attempt while logind still considered the hibernate
  operation active. `systemd-inhibit` returned status 1, and the service
  restarted successfully two seconds later. Locking completed, and this did
  not change the Shibumi process, state, layer, or crash count. Current upstream
  retains the same monitor implementation, so this is recorded as host
  lifecycle behavior rather than a Shibumi failure.

These system contracts complement the plugin; they do not replace per-window
bar recovery. The plugin must not add a second sleep inhibitor or lock owner.

## Required Implementation And Acceptance

1. Preserve the existing native screen model, placeholder rejection, and
   targeted `WindowRecovery`; do not replace them with a full shell reload.
2. Preserve deterministic focused/output-aware routing for bar-widget IPC while
   retaining the proposed host-level `QTR-008` contract.
3. Preserve V1's non-persistent narrow/portrait presentation policy without
   changing user widget toggles, saved order, or split state.
4. On two physical outputs, test clicks, keyboard/IPC opens, tooltips, panels,
   split/drag, mixed scale, hot-unplug, reconnect, and primary-output changes.
5. With a popup open and separately while edit/drag mode is active, remove its
   output. The other bar must remain usable and no stale surface, input region,
   tooltip, popout owner, drag target, or worker may remain.
6. Test DPMS/display sleep, suspend/resume, and hibernate/resume. After every
   cycle, require exactly one bar per real output, the same shell PID when the
   compositor keeps it alive, valid panel routing, and no new QML/layer errors.
7. If the compositor destroys and recreates `ShellScreen` objects, require a
   fresh delegate only for those outputs. If only the backing layer window is
   lost, require targeted recovery through `WindowRecovery`.

Static regression and headless-output tests protect the implementation contract,
and the controlled headless run proves live add/remove, portrait staging,
focused routing, and cleanup. Real DPMS, deep suspend, and hibernate/resume now
pass. The headless run still does not constitute mixed-scale or physical
multi-monitor acceptance.
