#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source "$repo_root/tests/lib/baselines.sh"
shibumi_load_omarchy_baseline
omarchy_path=$OMARCHY_PATH
quickshell_bin=${QUICKSHELL_BIN:-/usr/bin/quickshell}
tmpdir=$(mktemp -d /tmp/shibumi-status.XXXXXX)
trap 'rm -rf -- "$tmpdir"' EXIT

fail() {
  printf 'status plugin regression failed: %s\n' "$*" >&2
  exit 1
}

[[ -d $omarchy_path/shell ]] || fail "Omarchy shell not found: $omarchy_path/shell"
[[ -x $quickshell_bin ]] || fail "Quickshell not found: $quickshell_bin"

mkdir -p "$tmpdir/runtime" "$tmpdir/fixtures"
chmod 700 "$tmpdir/runtime"
cp -a -- "$repo_root/hancore.shibumi.status" "$tmpdir/status"
cp -a -- "$omarchy_path/shell/Commons" "$tmpdir/Commons"
cp -a -- "$omarchy_path/shell/Ui" "$tmpdir/Ui"
install -m 0644 "$repo_root/tests/status-plugin-smoke.qml" "$tmpdir/shell.qml"
install -m 0644 "$repo_root/tests/fixtures/StatusTestWidget.qml" \
  "$repo_root/tests/fixtures/TrayDrawerTestPanel.qml" \
  "$repo_root/tests/fixtures/NotificationPanelTestView.qml" \
  "$tmpdir/fixtures/"

set +e
output=$(timeout 8 env \
  QT_QPA_PLATFORM=offscreen \
  WAYLAND_DISPLAY= \
  XDG_RUNTIME_DIR="$tmpdir/runtime" \
  QML_IMPORT_PATH="$omarchy_path/shell${QML_IMPORT_PATH:+:$QML_IMPORT_PATH}" \
  QML2_IMPORT_PATH="$omarchy_path/shell${QML2_IMPORT_PATH:+:$QML2_IMPORT_PATH}" \
  "$quickshell_bin" -p "$tmpdir" 2>&1)
rc=$?
set -e

printf '%s\n' "$output"
[[ $rc -eq 0 ]] || fail "component smoke exited $rc"
grep -F 'status plugin smoke passed' <<<"$output" >/dev/null \
  || fail "success marker missing"

status_widget="$repo_root/hancore.shibumi.status/BarWidget.qml"
status_service="$repo_root/hancore.shibumi.status/Service.qml"
rg -Fq '["full", "icon", "text"]' "$status_widget" \
  || fail "status widget does not expose Full/Icon/Text display modes"
if rg -q 'SystemTray\.items|NotificationServer|makoctl|pgrep -x hypridle' \
    "$repo_root/hancore.shibumi.status"; then
  fail "status plugin duplicates an official tray, notification, idle, or DND owner"
fi
rg -q 'registered(Source|Component)\("omarchy\.tray"\)' "$status_widget" \
  || fail "status view does not resolve the official tray component"
rg -q 'registered(Source|Component)\("hancore\.shibumi\.update-center"\)' \
  "$status_widget" \
  || fail "status view does not resolve the Shibumi update center"
rg -q 'firstPartyServiceFor\("omarchy\.notifications"\)' "$status_widget" \
  || fail "status view does not resolve the official notification service"
if rg -q 'notification(Source|Component|Loader|Widget)' "$status_widget"; then
  fail "status view retained the removed Quattro notification bar widget"
fi
rg -q 'notificationPanelSource: Qt\.resolvedUrl\("NotificationPanel\.qml"\)' \
  "$status_widget" || fail "status view does not own the V1 notification panel"
tray_view="$repo_root/hancore.shibumi.status/TrayStatusView.qml"
tray_panel="$repo_root/hancore.shibumi.status/TrayDrawerPanel.qml"
tray_menu="$repo_root/hancore.shibumi.status/TrayAppMenuPanel.qml"
rg -q 'pinnedCount \* Commons\.Style\.space\(18\)' "$tray_view" \
  || fail "pinned tray cells do not match the V1 18px geometry"
[[ $(rg -c 'Commons\.Style\.space\(14\)' "$tray_view") -ge 4 ]] \
  || fail "pinned tray icons do not match the V1 14px geometry"
rg -q 'readonly property string drawerTooltipText: totalCount' "$tray_view" \
  || fail "tray drawer tooltip does not retain the current V1 count contract"
rg -q 'drawerCount > 0 \? " \\u00b7 " \+ drawerCount \+ " hidden" : ""' \
  "$tray_view" \
  || fail "tray drawer tooltip does not retain the current V1 hidden-count suffix"
if rg -Fq 'Middle-click an app to open its menu' "$tray_view"; then
  fail "tray drawer tooltip retained an obsolete pre-V1 instruction"
fi
rg -q 'padding: 12' "$tray_panel" \
  || fail "tray drawer does not retain the V1 12px content inset"
rg -q 'fittedContentWidth\(328\)' "$tray_panel" \
  || fail "tray drawer does not retain the V1 328px outer width"
rg -q 'contentHeight: fittedContentHeight\(contentColumn\.implicitHeight\)' \
  "$tray_panel" \
  || fail "tray drawer still clips its V1 content behind a fixed outer cap"
rg -U -q 'function closeTrayDrawer\(\) \{[^}]*trayDrawerOpen = false[^}]*closeChild\(trayWidget\)' \
  "$status_widget" \
  || fail "closing the tray drawer does not dismiss the host app menu"
rg -U -q 'function openTrayDrawer\(\) \{[^}]*closeNotificationPanel\(\)[^}]*trayDrawerOpen = true' \
  "$status_widget" \
  || fail "tray drawer does not expose a deterministic screen-local open path"
for bar_host in "$repo_root/Bar.qml" "$repo_root/hancore.shibumi.bar/Bar.qml"; do
  rg -Fq 'function openStatusTray(screenName: string): string' "$bar_host" \
    || fail "$bar_host does not expose the screen-local status tray route"
  rg -Fq 'function openStatusNotifications(screenName: string): string' \
    "$bar_host" \
    || fail "$bar_host does not expose the screen-local notification route"
done
rg -U -q 'Connections \{[^}]*target: root\.bar[^}]*onLayoutConfigChanged\(\)[^}]*root\.injectChildren\(\)' \
  "$status_widget" \
  || fail "embedded official widgets do not react to host layout settings"
for tray_contract in 'text: "Tray Apps"' 'text: "Pin"' \
  'text: appRow.hasMenu ? "AppMenu" : "No Menu"' \
  'trayBackend.togglePin' 'trayBackend.openTrayMenu'; do
  rg -Fq "$tray_contract" "$tray_panel" \
    || fail "tray drawer lost V1 presentation/action contract: $tray_contract"
done
[[ -f $tray_menu ]] || fail "V1-themed tray app menu is missing"
rg -q '^ShibumiPanel \{' "$tray_menu" \
  || fail "tray app menu does not use the Shibumi panel surface"
rg -q 'QsMenuOpener' "$tray_menu" \
  || fail "tray app menu does not consume the authoritative DBus menu"
rg -q 'owner: ownerWidget' "$tray_menu" \
  || fail "tray app menu does not share the drawer popout owner"
if rg -q 'id: menuOwner' "$tray_menu"; then
  fail "tray app menu retained the competing popout owner"
fi
rg -q 'radius: panel\.controlRadius' "$tray_menu" \
  || fail "tray app menu rows do not follow the live V1 control radius"
for submenu_contract in 'id: rootMenuOpener' \
  'menu: panel.open ? panel.rootMenu : null' \
  'id: submenuOpener' 'entry.updateLayout()' \
  'Math.max(menuColumn.implicitHeight, rootMenuImplicitHeight)' \
  'panel.pushSubmenu(menuEntry.modelData)' 'panel.popSubmenu()'; do
  rg -Fq "$submenu_contract" "$tray_menu" \
    || fail "tray app menu lost current Quickshell submenu lifecycle: $submenu_contract"
done
if rg -q 'entry\.sendOpened\(\)|current\.sendClosed\(\)' "$tray_menu"; then
  fail "tray app menu duplicates QsMenuOpener lifecycle events"
fi
rg -q 'ownerWidget\.openTrayAppMenu\(item, anchor\)' "$tray_panel" \
  || fail "tray drawer bypasses the V1-themed app menu"
rg -q 'anchor\.mapToItem\(null,' "$status_widget" \
  || fail "tray app menu does not preserve the clicked V1 X anchor"
rg -q 'trayAppMenuAnchor = trayAppMenuBarAnchor' "$status_widget" \
  || fail "tray app menu still derives panel geometry from the drawer window"
rg -U -q 'trayAppMenuAnchor = trayAppMenuBarAnchor[^}]*trayDrawerOpen = false[^}]*trayAppMenuOpen = true' \
  "$status_widget" \
  || fail "tray app menu does not replace the full-screen drawer like V1"
rg -Fq 'readonly property bool panelLoaded: notificationPanelLoaded' \
  "$status_widget" \
  || fail "status widget does not expose standard panel-loader diagnostics"
rg -q 'required property var notificationService' \
  "$repo_root/hancore.shibumi.status/NotificationPanel.qml" \
  || fail "V1 notification panel does not receive the official service directly"
rg -q 'notificationService\.pendingModel' \
  "$repo_root/hancore.shibumi.status/NotificationPanel.qml" \
  || fail "V1 notification panel does not consume the official pending model"
rg -q 'notificationService\.pastModel' \
  "$repo_root/hancore.shibumi.status/NotificationPanel.qml" \
  || fail "V1 notification panel does not consume the official recent model"
rg -Fq 'readonly property int notificationCount: pendingCount + recentCount' \
  "$repo_root/hancore.shibumi.status/NotificationStatusView.qml" \
  || fail "notification badge drops seen history entries"
rg -Fq 'visible: root.notificationCount > 0' \
  "$repo_root/hancore.shibumi.status/NotificationStatusView.qml" \
  || fail "notification badge visibility ignores retained history"
rg -Fq 'readonly property int activeCount: pendingCount + recentCount' \
  "$repo_root/hancore.shibumi.status/NotificationPanel.qml" \
  || fail "V1 notification panel drops seen notifications from history"
rg -Fq 'model: panel.activeRows' \
  "$repo_root/hancore.shibumi.status/NotificationPanel.qml" \
  || fail "V1 notification list is not backed by pending and past rows"
rg -Fq 'notificationService.dismissPast(index)' \
  "$repo_root/hancore.shibumi.status/NotificationPanel.qml" \
  || fail "V1 notification panel cannot dismiss recent notifications"
rg -Fq 'notificationService.clearPast()' \
  "$repo_root/hancore.shibumi.status/NotificationPanel.qml" \
  || fail "V1 notification panel cannot clear recent notifications"
if rg -q 'PopupCard|Quickshell\.Services\.Notifications|makoctl' \
    "$repo_root/hancore.shibumi.status/NotificationPanel.qml"; then
  fail "V1 notification presentation duplicates stock chrome or backend ownership"
fi
rg -q 'firstPartyServiceFor\("omarchy\.idle"\)' "$status_service" \
  || fail "status service bypasses the official idle service"
rg -q 'firstPartyServiceFor\("omarchy\.notifications"\)' "$status_service" \
  || fail "status service bypasses the official notification service"
if rg -U -q 'onLoaded: \{[^}]*root\.scheduleChildSync' "$status_widget"; then
  fail "loaded status children recursively reschedule their own loaders"
fi
rg -q 'interval: 45000' "$status_service" \
  || fail "recording reconciliation lost its bounded fallback"
rg -q 'running: root\.runtimeProbesEnabled && root\.recording' "$status_service" \
  || fail "recording elapsed work is not lifecycle bounded"
if rg -q 'bar\.run' "$status_service"; then
  fail "status actions cross the transitional bar-command boundary"
fi
rg -q 'launch\(\["omarchy-capture-screenrecording", "--stop-recording"\]\)' \
  "$status_service" || fail "recording stop is not an argument-vector action"
rg -q 'launch\(\["omarchy-voxtype-model"\]\)' "$status_service" \
  || fail "Voxtype model action is not argument-vector based"
rg -q 'launch\(\["omarchy-voxtype-config"\]\)' "$status_service" \
  || fail "Voxtype config action is not argument-vector based"

printf 'status plugin regression passed\n'
