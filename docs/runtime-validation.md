# Phase 1 Runtime Validation

> **Document status: Historical validation evidence.** This checklist records
> the early combined-plugin runtime. Use `release-readiness.md` for the current
> plugin-suite acceptance state.

This checklist is for a disposable or secondary Omarchy Quattro machine. Do
not run it on the primary QS Rise V1 session.

## Latest Run

the validation system was tested on 2026-07-16 with Omarchy Quattro, Hyprland 0.55.4,
Quickshell running the official `/usr/share/omarchy/shell/shell.qml`, and one
physical 1920x1080 output at scale 1.0.

Passed:

- plugin validation, registration, activation, and clean V2 load
- stock widget rendering and the Network panel on the invoking output
- top and bottom layer geometry required by QS Rise V1 parity
- bar hide/show without restarting the shell
- shell restart with exactly one replacement shell process and V2 layer
- temporary two-output hotplug with one bar and one widget set per output;
  unplug removed only the temporary output while the shell PID stayed stable

The run found and fixed two V2 lifecycle defects before those gates passed:

- a widget slot inherited invisibility from itself through its child item
- the inactive center fallback still instantiated duplicate widget handlers

Open gates:

- A fractional scale could not be applied on the test session, so mixed-scale
  evidence is still required.
- The intentional broken-plugin test exposed an Omarchy host error at
  `/usr/share/omarchy/shell/shell.qml:257`: the Loader error handler references
  `errorString` as an undefined identifier. The shell stays alive, but the
  built-in bar does not become visible. This must be fixed upstream before the
  fallback gate can pass.

the validation system was restored after the run: its original `shell.json` hash matched,
`omarchy.bar` was the only bar option, the original `bar-off` state was
restored, and no staged plugin, headless output, or test file remained.

The current 22-plugin suite received a focused output-lifecycle run on
2026-07-20 against the official Quattro tree at `ff1d1c3`:

- eDP-1 remained at 1920x1080, scale 1.0, responsive stage 0;
- a temporary 800x1280, scale 1.0 output selected responsive stage 3 and showed
  only G1, G2, G6, G8, G11, and G14;
- focus selection moved from eDP-1 to the temporary output and a generic
  Control Center summon opened only there;
- removing the output left one shell, one output, and zero open panels;
- the current shell log contained zero binding loops, zero invalid-context
  warnings, and zero spurious QS Rise recovery warnings for the removed output.

This accepts the live headless add/remove, portrait, routing, and cleanup
contracts. A physical second monitor, mixed scale, display sleep, suspend, and
hibernate remain separate gates.

The multi-style foundation was re-tested on the validation system later the same day:

- a missing `bar.style` loaded the default `qsrise` renderer
- an unknown style id fell back to `qsrise` on a cold shell start
- the extracted horizontal surface mapped at 1920x26
- the extracted vertical surface mapped at 28x1080 on the right edge
- all 12 configured widget slots belonged to the one physical output, with no
  duplicate style/runtime tree
- the final namespaced Omarchy imports loaded without style or plugin errors

The earlier left/right checks are retained as historical defensive-host
evidence only. QS Rise V1 and the V2 product contract require top and bottom;
vertical layouts are not a release gate.

the validation system was again restored byte-for-byte afterward. Only `omarchy.bar`
remained registered and no staged V2 plugin or style-test cache remained.

## Preconditions

- The source checkout is clean or its exact diff is recorded.
- The test machine runs a current Omarchy Quattro shell.
- The current `~/.config/omarchy/shell.json` is backed up.
- The built-in `omarchy.bar` is known to load before the test.
- No V1 QSRise process is used as evidence for this native plugin.

## Stage The Private Checkout

Plugins may not contain symlinks. Copy the working tree without `.git` into the
test machine's plugin directory:

```bash
plugin_dir="$HOME/.config/omarchy/plugins/hancore.qsrise.bar"
mkdir -p "$plugin_dir"
rsync -a --delete --exclude .git /path/to/omarchy-qsrise-bar/ "$plugin_dir/"
omarchy plugin validate "$plugin_dir"
omarchy-shell shell rescanPlugins
omarchy bar options
```

Expected:

- validation exits 0
- `hancore.qsrise.bar` appears exactly once as a bar option
- the built-in bar remains active until explicitly changed

## Activate And Load

```bash
omarchy bar use hancore.qsrise.bar
omarchy restart shell
```

Expected:

- no second Quickshell process is started
- the Omarchy Shell process owns the QS Rise windows
- one bar appears on every real output
- configured Omarchy widgets remain present and interactive
- the log contains no plugin load error or fallback message

Evidence to capture:

```bash
omarchy bar layout --json
omarchy-shell shell debugBarGeometry
qs list --all
```

## Position Matrix

Run the two QS Rise product positions and inspect every connected output:

```bash
for position in top bottom; do
  omarchy bar position "$position"
  sleep 2
done
```

For each product position verify:

- correct edge and exclusive zone
- no clipped widgets or overlapping sections
- center anchor remains geometrically centered
- tooltips open away from the bar edge
- widget panels open on the invoking output

## Style Matrix

For every registered production style:

1. Set `bar.style` through the host configuration API.
2. Restart the shell and verify the style cold-loads.
3. Repeat the position, output, panel, split, drag, and lifecycle matrices.
4. Confirm that widget and panel state survives changing only the style.
5. Configure an unknown style id and require the `qsrise` fallback without a
   duplicate runtime or hidden worker.

Only the selected style may be instantiated. Adding a visual style does not
reduce the acceptance matrix.

## Lifecycle Matrix

1. Toggle the bar off and on with the normal Omarchy action.
2. Restart Omarchy Shell.
3. Reload `shell.json` by changing the bar position.
4. Disconnect and reconnect an external output.
5. Disable and re-enable an optional bar-widget plugin.

Expected:

- no nameless or 0x0 output window appears
- removing one output does not reload or move another output's bar
- reconnecting an output creates one fresh bar for that output
- no stale tooltip, popout, or widget process remains
- a lost layer window is recovered only on its own output

## Failure And Fallback

Before testing fallback, reset to the built-in bar and preserve a working copy
of the plugin. Introduce a load error only in the staged test copy, then select
the plugin again.

Expected:

- Omarchy logs the third-party bar load failure
- `omarchy.bar` becomes visible
- the shell process stays alive

Restore the valid staged copy before continuing.

## Restore

```bash
omarchy bar reset
omarchy restart shell
```

Expected:

- only the built-in bar is active
- the saved `shell.json` content is restored if the test changed anything
  beyond the active bar id and position
- removing the staged plugin leaves no QS Rise V2 process, window, or state

## Pass Gate

Phase 1 runtime validation passes only when all checks above succeed on the
same source revision. Static lint, fixture tests, or a successful manifest
validation do not replace this matrix.
