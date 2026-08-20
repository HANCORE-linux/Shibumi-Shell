# Step 1D Notifications compatibility validation

Status: implementation in progress on the Step 1D worktree. This slice keeps
Omarchy as the sole Notifications owner and adds only a Shibumi primitive-row
adapter; it does not create a second notification daemon or server.

## Reproduced failure

The current Omarchy Notifications service exposes the live `popupModel` plus
host actions such as `dismissPopup`, `clearPopups`, `focusApp`, and
`showRecentHistory`. Shibumi Status still expected the older
`pendingModel`/`pastModel` shape. A real notification produced an Omarchy toast,
but the Shibumi panel showed `No notifications`.

The failure was reproduced with a uniquely named critical notification on the
local DP-1 output before the adapter was deployed.

## Implementation

- `hancore.shibumi.status/NotificationAdapter.qml` copies host rows into
  Shibumi-owned primitive `pendingModel` and `pastModel` models.
- Current hosts use `popupModel`; legacy hosts with `pendingModel` and
  `pastModel` remain supported and take precedence when present.
- DND, dismiss, clear, focus, and history actions resolve against the current
  host service at call time.
- Host absence and host replacement clear and rebuild the adapter models.
- The raw host reference remains private to an internal adapter object and does
  not escape to the bar or panel views.
- The current host has no public recent-history model. The panel therefore
  provides explicit `Live` and `Recent` tabs; selecting Recent asks the host to
  replay its host-owned history. Rows are labeled `LIVE`/`RECENT`, with
  `color03` for Live and `color04` for Recent. The adapter buffers notifications
  that arrive during the host replay and suppresses stale replay results after
  Clear all. The Clear all control and per-row dismiss actions remain
  available on both tabs; current-host replay dismissals are filtered from the
  current view even though the host has no persistent per-entry history delete.
  The adapter never reads private host state files. Legacy `pastModel` history
  remains supported.

## Validation

Passed:

- notification adapter smoke and regression, including current and legacy host
  shapes, host replacement, unavailable state, DND, dismiss, focus, clear,
  history replay, negative-ID empty-history sentinels, replay races, and
  post-replay live notifications;
- production-boundary regression;
- documentation regression;
- unpinned status-plugin smoke against the installed Omarchy host;
- local live probe: active row appeared in the Shibumi panel and authoritative
  host dismissal removed it;
- Machine 2 (`192.168.2.128`) live probe on `eDP-1`: active row appeared in the
  Shibumi panel and authoritative host dismissal succeeded;
- both live probes retained one production Quickshell process and
  `omarchy-shell shell ping: ok`;
- final local installation from this worktree was updated with the history
  panel, and the live probe visibly rendered the explicit `Live`/`Recent` tabs;
  a separate batch of 10 normal notifications rendered with `LIVE` labels and
  a batch of 10 normal-urgency notifications was sent while DND was enabled
  for the Recent replay check. A second live batch of 10 normal and 5 DND
  notifications was generated after the final tab-order deployment; the Live
  tab showed all 10 normal rows and the 5 DND rows remain available through
  Recent.

The pinned status/contract gate remains blocked by the known installed Omarchy
shell-content baseline drift. This is an environment validation limitation,
not a runtime error in this slice.

Step 1D remains open until the complete applicable contract gate, independent
review, and final user visual/interaction acceptance are recorded.
