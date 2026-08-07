# Test Shibumi on multiple monitors

Scope: 6 test cycles with two physical monitors. Mark each cycle as `PASS`, `FAIL`, or `NOT TESTABLE`.

## Prepare the test

1. Connect two monitors as an extended desktop, not mirrored
2. Record each monitor's name, resolution, scale, and position
3. Record the original bar version, style, and position
4. Capture a screenshot of the complete desktop
5. Save the output from these commands:

```bash
shibumi-shell status
hyprctl monitors -j
qs list --all --json
```

## Cycle 1: Check both monitor bars

Test these states through **Control Center > Bars**:

| Bar | Style | Position | Result |
| --- | --- | --- | --- |
| V1 | Islands | Top | |
| V1 | Islands | Bottom | |
| V2 | Full | Top | |
| V2 | Fit | Top | |
| V2 | Dock | Bottom | |
| V2 | Notch | Top | |
| V2 | Notch | Bottom | |

Check each state:

- [ ] Each monitor shows exactly one bar
- [ ] No group overlaps or gets clipped
- [ ] Position, outline, and centering are correct
- [ ] Full, Fit, and Dock have shadows; Notch has no shadow
- [ ] Mouse input and tooltips work on both bars

Capture screenshots of V1 Top, V1 Bottom, V2 Notch Top, and V2 Notch Bottom.

## Cycle 2: Check panels, focus, and workspaces

Test on monitor A, then monitor B:

1. Open Control Center, Audio, Weather or Calendar, and Network
2. Close each panel once with `Esc` and once by clicking outside
3. Switch workspaces twice on each monitor
4. Move one window between the monitors

Expected result:

- [ ] Panels open only on the monitor where you clicked the widget
- [ ] No panel appears twice or extends beyond the monitor edge
- [ ] `Esc` and outside clicks close every panel
- [ ] Active and occupied workspaces update correctly
- [ ] Focus changes do not move a bar or panel

## Cycle 3: Check mixed scaling

Mark this cycle as `NOT TESTABLE` if different scales are unavailable.

1. Record the original display settings
2. Set monitor A to `100%`
3. Set monitor B to `125%` or `150%`
4. Check V1 at Top and Bottom
5. Check V2 Notch at Top and Dock at Bottom
6. Open Control Center, Weather, and Network on both monitors
7. Restore the original display settings

Expected result:

- [ ] Bars, icons, and text have matching visual sizes on both monitors
- [ ] Lines and outlines remain sharp and closed
- [ ] Panels have the correct size and position
- [ ] A narrow monitor may reduce content, but nothing overlaps
- [ ] Reduced content returns after you restore the available width

## Cycle 4: Check V1 split and drag

1. Enable V1 Top
2. Enter layout edit mode on monitor B
3. Add one split point
4. Drag one widget group to a valid position
5. Drag one widget group to an invalid position
6. Exit layout edit mode

Expected result:

- [ ] Edit points and the drag ghost appear only on monitor B
- [ ] The split appears at the same boundary on both bars
- [ ] The valid drop updates both bars
- [ ] The invalid drop restores the previous order
- [ ] No drag ghost or input surface remains after exit

## Cycle 5: Check monitor hotplug

Use monitor B as the external monitor.

1. Open the Weather panel on monitor B
2. Physically disconnect monitor B
3. Check the bar and panels on monitor A
4. Reconnect monitor B and wait five seconds
5. Start a V1 drag on monitor B and hold the mouse button
6. Disconnect monitor B, release the mouse button, and reconnect it

Expected result:

- [ ] Monitor A remains usable throughout the cycle
- [ ] Monitor B's panel and drag ghost disappear
- [ ] No invisible surface blocks input
- [ ] Exactly one bar appears on monitor B after each reconnect
- [ ] Style, position, and widget order remain intact

Record a short video of this cycle. Skip only the drag section if you cannot reach the connector safely.

## Cycle 6: Check restart and restore

1. Select a different style and bar position
2. Restart Omarchy Shell through the normal Omarchy action
3. Check both monitors
4. Restore the original bar and monitor configuration
5. Open **Control Center > Health**
6. Run the three preparation commands again

Expected result:

- [ ] Exactly one bar appears on each monitor after restart
- [ ] Style, position, and widgets remain saved
- [ ] Panel routing still works on both monitors
- [ ] Health reports no Shibumi runtime error
- [ ] The original configuration is restored

## Return the results

| Cycle | Result | Short note |
| --- | --- | --- |
| 1. Bars | | |
| 2. Panels and workspaces | | |
| 3. Mixed scaling | | |
| 4. Split and drag | | |
| 5. Hotplug | | |
| 6. Restart | | |

Return the table, screenshots, hotplug video, and terminal output. If a check fails, run `qs log` and include the section starting at the failure time.

Multi-monitor acceptance passes when every executable cycle reports `PASS`. A `NOT TESTABLE` result for cycle 3 leaves mixed-scale acceptance open.
