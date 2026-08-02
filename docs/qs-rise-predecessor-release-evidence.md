# QS Rise predecessor release evidence

> **Document status: Historical validation evidence.** This document preserves
> the last suite-managed QS Rise the validation system gate before the Shibumi rename. It
> cannot accept the Shibumi payload or override `../ARCHITECTURE.md`.

Date: 2026-07-22

Every result below belongs to the former `hancore.qsrise.*` namespace. Use
`release-readiness.md` for the current Shibumi gate.

## Proven

- All 22 plugins validate independently against the current Omarchy Quattro
  tree.
- The complete contract regression passes, including plugin containment,
  ownership, QML component loads, and the registry-only bar host.
- Transactional install, update, rollback, interrupted recovery, uninstall,
  cache cleanup, collision handling, and 21-to-22 profile migration pass in
  isolated lifecycle tests.
- the validation system runs the 22-plugin default profile with no disabled QS Rise plugin;
  the live bar confirms the installed payload digest.
- The real 21-to-22 update completed on the validation system without replacing the user's
  bar layout or leaving helper processes.
- Every enabled top-bar panel opens and closes on the validation system without a QS Rise
  QML error or retained worker. Update Center package/theme state is populated.
- G3 contains the local Update Center facade plus the authoritative Quattro
  tray and notification owners. No second tray or notification service exists.
- The rebuilt G1 Control main surface and G3 package/theme tabs load on
  the validation system with real state. Focused regressions cover every V1 Control setting,
  package-state parsing, pinned theme actions, and panel component loading.
- A controlled second-output run on the validation system passed live add/remove, 800x1280
  portrait staging, focused widget routing, output-local panel opening, and
  cleanup. The shell stayed reachable and logged no binding loop, invalid QML
  context, or false output-recovery warning.
- The theme boundary is audited against Omarchy `afa2839a`: QS Rise consumes
  the host's canonical `background`, `foreground`, and `muted` tokens, keeps
  its internal V1 semantic names private, and parses only the bounded V1
  `color02`/`color03` accent extensions from `colors.toml`. Model, Quattro
  runtime, and style-contract regressions pass.
- the validation system hardware checks prove the reversible laptop paths: brightness moved
  from 100 to 95 and back through the official monitor IPC, the power profile
  moved from performance to balanced and back in `app-graphical.slice`, and
  opening/closing the QS Rise Bluetooth panel started and released discovery.
  BAT0 is detected through UPower as present, fully charged, and healthy.
- A reversible real-Wayland Bottom run on the validation system placed the 35 px bar at
  `y=1045` on the 1920x1080 output. The G1 Control, G3 Update Center, centered
  G8 calendar, and right-anchored G11 Network panels all opened upward at the
  correct output-local anchor. The original `shell.json` hash and Top position
  were restored, with no retained panel, worker, crash report, or QS Rise log
  error.
- The separate Tanzaku wallpaper overlay also passed at Bottom with 11 warm
  entries, the current selection visible, and no loading or idle-inhibitor
  residue after close. This covers the non-`QsRisePanel` fullscreen picker
  path; all 15 conventional panel families share the byte-identical geometry
  wrapper already exercised at left, center, and right anchors.
- A separate Bottom state test enabled all 14 stored split boundaries and
  swapped G4/G5 in the persisted left-group order. The bar rendered the split
  islands with CPU before Memory, retained the exact state across
  `reloadConfig`, and restored the original zero-split G4-before-G5 config
  hash.
- A later physical Bottom edit-mode test used the production full-output input
  surface: the drag ghost followed the pointer and a real widget drop swapped
  the target groups. The same run confirmed that conventional panels open
  above the Bottom bar. Releasing a second drag over empty output space returned
  the widget visually to its previous position. A controlled before/after check
  kept the complete `shell.json` hash and group order byte-identical, proving
  that this path performs no layout write. No crash report or retained worker
  was created.
- Restarting the dedicated `app-graphical.slice` shell unit after the physical
  drag changed the Quickshell PID while preserving the complete `shell.json`
  hash, Bottom position, and group order. The replacement instance reached
  `Configuration Loaded`, answered IPC, and created no crash report.
- V1 split handles remain hover-revealed at Bottom: the 14 px `•`/`│` handle
  may overlap the 6 px unsplit cell boundary instead of being clipped. The
  focused style contract, Qt 6 lint, live restart, and the validation system visual check
  pass with unchanged layout state.
- Real picker actions pass on the validation system: the current theme was reapplied, the
  wallpaper moved from BG2 to BG3 and was restored to BG2, and unique
  screenshot/video fixtures passed copy, open, and two-step trash actions.
  Clipboard contents were restored, the exact media windows and trash entries
  were removed, caches were rescanned, and no converter, player, picker,
  filesystem, or crash artifact remained.
- The QS Rise Network panel completed a real Quattro speed test through its
  visible `Run test` action and showed final ping, download, and upload values.
  Opening the panel exercised the same `refresh(true)` backend path used by
  Rescan, refreshed the visible SSID model, and closing it released the
  details sampler. The active WLAN, shell PID, IPC, and crash count remained
  unchanged. A stale saved-only profile was removed through the panel's
  two-step Forget action; it disappeared immediately and did not return after
  reopening the panel or rescanning. The DNS controls also completed a real
  reversible `DHCP -> Cloudflare -> DHCP` round trip through the visible UI and
  Polkit. NetworkManager configuration, resolved state, link DNS, the active
  WLAN, and the shell PID all matched the selected state at each step and the
  original DHCP state was restored without a retained test profile or file.
- A no-audio fullscreen recording through Quattro's real recorder was detected
  by QS Rise, exposed a live elapsed timer, and expanded G8 from 152 to 217 px.
  A physical click on the visible G8 indicator invoked `stopRecording()`,
  finalized a valid 1920x1080 H.264 MP4, removed the recording state, and let
  the temporary test unit exit successfully. The video, preview, helper,
  worker, and state artifacts were then removed. A real Voxtype microphone
  cycle also passed through `recording`, `transcribing`, and back to `idle`;
  the dictated text was inserted and the single shared status stream remained.
- The complete focused regression matrix passes against a read-only snapshot
  of the validation system's current Quattro shell: status, network, quick-access,
  audio/media, style, and full contract suites. Both repository synchronization
  checks, `git diff --check`, and the focused Qt 6 `qmllint` pass. The linter
  reports 83 existing dynamic-type warnings and no errors. This snapshot run
  validates the source contracts but does not replace the final live-log check
  on the exact release payload.
- The follow-up live snapshot on the validation system passes: PID 185076 remains the sole
  QS Rise shell in `app-graphical.slice`, `shell ping` returns `ok`, and the
  Bottom geometry is anchored at y=1043 on eDP-1 at 1920x1080 and scale 1.0.
  The picker is closed, Reactor is inactive in mode 0, and only the Network
  panel deliberately left open by the UI test reports `opened=true`. The
  current log contains `Configuration Loaded` and no QML error line. No worker,
  action-test artifact, or crash newer than the accepted baseline remains.
- A controlled persistence round trip compared the complete loaded `.bar`
  object with `~/.config/omarchy/shell.json` before reload, after
  `reloadConfig`, and after a real restart of the dedicated shell unit. The
  configuration SHA-256 remained
  `21481d540d5820d410cab201681c9fc8a2c852d7d5c431969a51dc020784a6a2`,
  and the replacement process (PID 390580) loaded byte-equivalent semantic
  state for position plus every QS Rise persistence category: menu, order,
  picker, presentation, Reactor, splits, widgets, and workspaces. Transient
  panel-open state correctly returned closed. The restart produced no crash or
  worker and reached `Configuration Loaded`.
- The final-source lifecycle gate passes on the validation system. A complete backup was
  taken, the manually patched pre-test payload was normalized out of the plugin
  root, and the suite uninstaller removed all 22 QS Rise registrations,
  directories, state, cache, and transaction paths. A fresh stock process then
  reached `Configuration Loaded` with no QML error or crash. Installing from a
  clean source snapshot produced 22 registered, enabled, suite-managed plugins,
  22 ownership markers, and a live payload-digest result of `ok`. Fresh defaults
  correctly hid G7, G14, and G15, kept all other applicable groups enabled, used
  Tanzaku and Reactor mode 0, and preserved Bottom. The prior QS Rise settings
  were restored atomically; the complete host configuration outside
  `bar.qsrise` had remained semantically identical throughout.
- A controlled real failed update reached the exposed-candidate stage with a
  distinct Memory-plugin payload, then deliberately returned `not-ready` only
  from the final payload verifier. The update exited nonzero and restored the
  exact configuration hash, install-state hash, suite digest, Memory digest,
  installed status, and live payload. The probe file disappeared, all 22
  ownership markers remained valid, and no transaction, stage, backup, crash,
  worker, or test fixture remained. A fresh replacement process (PID 459508)
  loaded the restored Bottom bar with no QML error.
- The final bounded performance gate passes on that same restored payload and
  stable PID/start time. Across 120.527 seconds at Reactor mode 0 with every
  panel and picker closed, QS-own CPU was 0.191% and child-process CPU was
  0.631%; child p50 was 0%, p95 was 4.973%, and only 17 of 120 one-second
  intervals recorded child growth. After a separate warm-up, 20 Control Center
  and 20 Tanzaku wallpaper open/close cycles retained 3,768 KiB total closed
  PSS (3,223 KiB after the panel block and another 545 KiB after the picker
  block). Maximum open PSS was 569,372 KiB for Control Center and 575,109 KiB
  for the picker. The ten-second tail ended with no open panel, loading picker,
  converter/helper worker, new crash, or QS Rise QML error.
- The final non-destructive candidate matrix passes against current Quattro
  commit `43260b29`. It includes the complete repository contract suite,
  independent validation of all 22 plugin directories, a no-mutation 22-plugin
  install dry-run, 11 transactional lifecycle tests, both vendoring
  synchronization checks, syntax and ShellCheck for all 31 shell scripts,
  bytecode validation for all eight Python files, and `git diff --check`.
  Focused Qt 6 `qmllint` exits 0 with two unresolved external `qs.Commons`
  import warnings and no error. A deliberately broad 302-file lint also exits
  0 but is not used as a quality metric because vendored copies amplify
  incomplete external Quattro type metadata.
- After the final Control Center and Update Center label cleanup, the complete
  contract suite was repeated against the exact shell payload from the validation system's
  `omarchy-dev 4.0.0.r1160.ga64d895-1`. All 22 independent plugin contracts,
  host-facade checks, offscreen widget/panel smokes, update safety regressions,
  and 11 transactional suite lifecycle tests pass. Bash syntax, ShellCheck for
  all 46 shell files, Python bytecode validation for all eight Python files,
  and `git diff --check` also pass. The same payload updated transactionally on
  the validation system, retained one running Quattro shell and a clean 22-plugin managed
  state, and contains neither the Control Center `Text`/`Icon` launcher-label
  prefixes nor icons in the `Check themes` and `Reapply` text actions.
- The matching live audit kept PID 1016328 in the dedicated
  `app-graphical.slice` unit and the complete configuration hash at
  `b597d100e864000266188378fe92cb14fb5629ff3489b2b3a2c40df7de9e83e4`.
  Registry, directory, managed-marker, and install-state counts are each 22;
  the local source and live payload share digest
  `c8e6f64f71bf1c5b75d534831d3ce93bf9d5197adeefc3b29add70d100970172`,
  which verifies as `ok`. IPC remains reachable, only one QS Rise bar layer is
  present, picker and panels are closed, Reactor is inactive in mode 0, and no
  bounded worker or crash newer than the accepted baseline exists. The current
  log contains one known stock Quattro Network-panel binding warning and the
  NetworkManager response to a manual reconnect of an already connected WLAN;
  it contains no QS Rise QML load failure.
- A fresh Top presentation sweep captured the closed bar and the normal loaded
  state of Control, Updates, Workspaces, Notifications, Memory, CPU, Audio, AI,
  Calendar, Media, Quick Access, Network, Power Profile, Battery, Display, and
  Bluetooth. Every panel remained output-bounded, used one QS Rise surface,
  closed without residue, and showed no clipping, overlapping radius, or
  inconsistent header action. Representative Control, Network, and Battery
  tooltips use the same V1 surface treatment. Source comparison confirms the
  V1 widths for the non-extended panels; Power Profile was returned from 230 px
  to the V1 220 px width and passed a live visual counter-check. Network,
  Display, and Bluetooth retain explicitly documented wider panels for their
  approved Quattro capability additions. This sweep covers normal populated
  presentation; it does not replace the remaining per-state side-by-side gate.
- A separate direct `omarchy.weather` summon captured the actual Weather panel,
  rather than the Center facade's default Calendar panel. Its complete current
  conditions, forecast, actions, Top anchor, and V1 surface rendered without
  clipping or overlap and closed without retained state. The same counter-check
  initially found zero registered StatusNotifier items on the session bus. A
  deterministic session-bus fixture now registers one `NeedsAttention`
  StatusNotifier item with a nested DBusMenu. the validation system accepted the populated
  V1 drawer and root app-menu surfaces in
  `docs/mockups/shibumi-v1-parity-g3-tray-drawer-top.png` and
  `docs/mockups/shibumi-v1-parity-g3-tray-app-menu-top-v3.png`; the menu covers
  enabled, checked, disabled, separator, and submenu rows. The current Shibumi
  candidate additionally retains the authoritative root handle while traversing
  children and keeps the root card height during navigation. the validation system therefore
  reaches and triggers `Nested action` at both Top and Bottom; the fixture log
  records two `item=6` menu events. The retained child states are captured in
  `docs/mockups/shibumi-v1-g3-dbus-submenu-top.png` and
  `docs/mockups/shibumi-v1-g3-dbus-submenu-bottom.png`. The fixture is
  not a substitute for the remaining real third-party SNI and multi-output
  gates.
- Theme and wallpaper failure feedback is now deterministic without mutating a
  real user selection. Both paths run through one guarded `Process`, retain a
  bounded and control-character-sanitized stderr reason, write a QS Rise log
  warning, and launch a visible desktop notification only on nonzero exit. An
  isolated real Quickshell/Quattro smoke drove wallpaper exit 7 and theme exit
  8, then verified the exact notification title and reason for each. The
  focused plugin validation, Qt 6 lint, quick-access regression, and complete
  contract suite pass; the validation system also confirms `/usr/bin/notify-send` exists.
- The automatic screensaver lifecycle now consumes Quattro's first-party
  `omarchy.idle` service. A sampled real cycle hid the only QS Rise bar layer
  254 ms before the fullscreen screensaver mapped, restored exactly one layer
  after wake, and never created a second shell instance or bar layer.
- Real output-power and system-sleep gates pass on the validation system. eDP-1 completed a
  DPMS off/on cycle, the laptop completed deep/S3 suspend/resume, and S4
  hibernate restored the saved image. Across all three gates, the shell PID,
  systemd unit, configuration hash, and crash count remained unchanged; one
  fully opaque bar layer, IPC, Idle state, and closed panel/picker state returned
  without a QML error or worker residue.
- A reversible single-output Reactor gate used the production IPC and real
  split-gap renderer on the validation system. Mode 7 formed the expected two-part text and
  rendered a monitor sweep; Mode 8 followed the unchanged V1 fit contract and
  selected its bounded fallback glyph because no bundled quote met the minimum
  cell size in the current dense 1920 px layout. One-second `/proc` samples
  measured QS-own CPU at 0.616% average in split Mode 0, 15.435% / 45.984% peak
  for a Mode-7 text event, 24.512% / 40.121% peak for a Mode-7 monitor sweep,
  and 19.244% / 36.189% peak for a Mode-8 quote event. These transient,
  non-default effects remain materially more expensive than Mode 0 but improve
  on the accepted V1 active-event measurements. The test restored the exact
  configuration hash, zero-split layout, Mode 0, unloaded backend, and closed
  surface state; physical multi-output Reactor acceptance remains open.
- A content-unique 3840x2160 wallpaper completed the real cold-cache path on
  the validation system through the production Hearthstone picker. The live scan added the
  twelfth row and produced its non-empty 512 px preview in 2,091 ms. After the
  exact source, thumbnail, and cache state were restored, the normal warm
  picker exposed all 11 cached entries in 275 ms with 11/11 previews ready.
  Closing either run left zero picker/converter workers and zero random scan
  temporaries. The helper now registers normal temporary files and provides a
  mode-locked recovery cleanup for hard-aborted scans; a regression proves the
  stable wallpaper cache survives that recovery unchanged.

## Residual Runtime Finding

The first real 21-to-22 hot migration produced one native Quickshell child
crash in Qt socket handling. The parent shell remained reachable, and separate
plugin-rescan, reload, and repeated full-update counter-tests produced no new
crash. No QS Rise QML failure was present. The final fresh-install, uninstall,
restart, and controlled rollback sequence completed without recurrence, so this
remains historical evidence rather than a current release blocker.

A later SSH-only diagnostic restart produced two Quickshell crash reports and
three additional system coredumps at the same second. The affected processes
were launched in SSH session scopes, and the primary report ends with an
explicit IPC exit while Qt was tearing down QML text and loader bindings. A
PID-addressed `reloadConfig` counter-test kept the same shell PID reachable and
created no new crash report. This is a test-start-context failure, not evidence
that the QS Rise plugin or a normal config reload crashes the shell. Remote
validation must use IPC calls or a dedicated `app-graphical.slice` unit rather
than `omarchy-restart-shell` from SSH.

The successful in-process uninstall emitted transient `TypeError` warnings
only from Quattro's stock Network, Bluetooth, and Monitor panel sources while
the stock composition was being rebuilt. At that point the shell already
answered IPC, contained no QS Rise registration, and had removed all QS Rise
state and payload paths. A fresh stock process then loaded with zero QML error
lines and no crash. This is retained as host hot-reload evidence; it did not
affect configuration, rollback, ownership, or cleanup correctness.

During the accepted hibernate gate, Quattro's `Restart=always` sleep-monitor
service attempted to reacquire its inhibitor before logind had fully completed
the hibernate operation. That attempt exited 1 and the service recovered on its
next automatic restart two seconds later. The lock completed, current upstream
retains the same monitor implementation, and no QS Rise invariant changed.
This is retained as non-blocking host behavior, not a QS Rise lifecycle failure.

## Required Before Private Release Candidate

1. Repeat a drag during physical output removal. Bottom ghost tracking,
   successful drop, byte-identical invalid-drop return, and process-restart
   persistence are already accepted on the validation system.
2. Complete a real connection to a new protected WLAN, including the password
   path. Network disconnect, saved-profile Forget, reversible DNS mutation,
   Voxtype dictation, theme/wallpaper success and controlled failure feedback,
   screenshot/video open/copy/trash, NetworkManager refresh, speed-test,
   recording detection/timer, and recording indicator stop are accepted.
3. Complete the remaining laptop hardware actions: real display enable/disable
   and Bluetooth pair/connect/forget plus Bluetooth audio where suitable
   devices are available. Brightness and scale mutation, power-profile
   mutation, a physical battery discharge/charge transition, and Bluetooth
   discovery lifecycle are already accepted on the validation system.
4. Complete the V1 presentation gate for every shipped widget, tooltip, panel,
   picker, and Control Center state. Compare V1 and QS Rise side by side at the same
   theme and scale; stock Quattro presentation does not satisfy this gate.
5. Complete the V1 output-lifecycle gate documented in
    [`v1-output-lifecycle-audit.md`](v1-output-lifecycle-audit.md): focused IPC
    routing, narrow/portrait behavior, controlled headless add/remove, real
    display sleep, suspend/resume, and hibernate/resume are accepted; complete
    physical hotplug, hot-unplug during drag, and mixed scale.

## Externally Blocked Or Deferrable

- Physical multi-monitor, hot-unplug, and mixed-scale acceptance require a
  second real output. Existing model, offscreen, and historical headless-output
  tests do not replace that gate.
- Historical predecessor evidence included an independent App Menu and its populated 260 px root card
  passes Top/Bottom the validation system rendering and lifecycle checks. Empty, provider
  error, deeper action routes, and physical multi-output states remain open;
  it is no longer treated as deferred work.
- A new picker style is post-parity work. Quattro remains the native carousel
  owner; QS Rise owns Tanzaku and Hearthstone.
- A second bar style proves multi-bar reuse only after the default bar passes
  release parity.

## Required V1 Presentation Parity

The following work is part of the release implementation, not deferred polish:

- exact V1 notification and weather panel presentation;
- exact V1 audio sliders, meters, device rows, and mute-state presentation;
- consistent V1 panel border, radius, shadow, typography, spacing, and motion;
- complete V1 Control Center density, hierarchy, controls, and selection states;
- exact V1 iconography, tooltip surfaces, popup anchoring, and top/bottom behavior.

Quattro continues to own the relevant platform services, actions, focus,
screen routing, and plugin lifecycle. Those contracts must be retained behind
the V1 presentation rather than exposed as a different stock UI. A panel is
not release-ready until both its functional contract and its V1 visual gate
pass.
