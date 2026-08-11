#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source "$repo_root/tests/lib/baselines.sh"
shibumi_load_omarchy_baseline
plugin="$repo_root/hancore.shibumi.update-center"
quickshell_bin=${QUICKSHELL_BIN:-/usr/bin/quickshell}
omarchy_path=$OMARCHY_PATH
tmpdir=$(mktemp -d /tmp/shibumi-update-center.XXXXXX)
trap 'rm -rf -- "$tmpdir"' EXIT

fail() {
  printf 'update center regression failed: %s\n' "$*" >&2
  exit 1
}

[[ -d $omarchy_path/shell ]] \
  || fail 'Omarchy shell is required for the update-center UI smoke'

jq -e '
  .schemaVersion == 1 and
  .id == "hancore.shibumi.update-center" and
  .kinds == ["bar-widget", "service"] and
  .keepLoaded == true and
  .entryPoints.service == "Service.qml" and
  .entryPoints.barWidget == "BarWidget.qml"
' "$plugin/manifest.json" >/dev/null \
  || fail 'manifest does not preserve the service-backed plugin contract'

service="$plugin/Service.qml"
widget="$plugin/BarWidget.qml"
panel="$plugin/UpdateCenterPanel.qml"
packages="$plugin/PackagesTab.qml"
themes="$plugin/ThemesTab.qml"
review="$plugin/scripts/theme-review"
rg -q 'target: "hancore\.shibumi\.update-center"' "$service" \
  || fail 'service IPC target is missing'
rg -q 'serviceFor\("hancore\.shibumi\.update-center"\)' "$widget" \
  || fail 'widget does not consume its singleton service'
rg -q 'serviceFor\("hancore\.shibumi\.state"\)' "$widget" \
  || fail 'widget badge preferences are not stored in Shibumi state'
for preference in packageBadge themeBadge; do
  rg -q "setBadgePreference\\(.*$preference|\"$preference\"" "$widget" "$panel" \
    || fail "missing badge preference: $preference"
done
rg -q 'panelSource: Qt\.resolvedUrl\("UpdateCenterPanel\.qml"\)' "$widget" \
  || fail 'update widget does not lazy-load its panel'
rg -q 'anchorItem: button' "$widget" \
  || fail 'update panel is not anchored to its own bar button'
if rg -Fq 'open: ownerWidget.opened' "$panel"; then
  fail 'update panel binds its lifecycle back to the owner widget'
fi
rg -Fq 'open: true' "$widget" \
  || fail 'update panel does not receive a one-way initial open state'
for deferred_loader_contract in \
  'onOpenedChanged: panelSyncTimer.restart()' \
  'onUpdateServiceChanged: panelSyncTimer.restart()' \
  'onTriggered: root.syncPanelLoader()' \
  'bar.releasePopout(root)' \
  'bar.clearConnectedPanel(root)'; do
  rg -Fq "$deferred_loader_contract" "$widget" \
    || fail "update panel loader lost its deferred lifecycle: $deferred_loader_contract"
done
if rg -Fq 'onOpenedChanged: syncPanelLoader()' "$widget"; then
  fail 'update panel loader synchronously re-enters the inherited open binding'
fi
if rg -q 'popupOpen' "$widget" "$panel"; then
  fail 'update center reintroduces a duplicate popup state'
fi
rg -q '^ShibumiPanel \{' "$panel" \
  || fail 'update panel does not use the Shibumi panel surface'
rg -q 'property Component packagesComponent:' "$panel" \
  || fail 'package tab component is not outside the visual child list'
rg -q 'property Component themesComponent:' "$panel" \
  || fail 'theme tab component is not outside the visual child list'
rg -q 'if \(dx < 0\) panel\.activeTab = "packages"' "$panel" \
  || fail 'left keyboard navigation no longer selects packages'
rg -q 'else if \(dx > 0\) panel\.activeTab = "themes"' "$panel" \
  || fail 'right keyboard navigation no longer selects themes'
if rg -q 'centerOnBar:[[:space:]]*true' "$widget" "$panel"; then
  fail 'update popup must remain anchored below the G3 update button'
fi
rg -q 'interval: 6 \* 60 \* 60 \* 1000' "$service" \
  || fail 'six-hour background checks drifted'
rg -F -q '["omarchy-launch-floating-terminal-with-presentation", "omarchy-update"]' \
  "$service" || fail 'package apply no longer delegates to the full Omarchy update'
if rg -n '(^|[^A-Za-z])(pacman|paru|yay)([^A-Za-z]|$)' \
    --glob '*.qml' --glob '*.js' "$plugin" >/dev/null; then
  fail 'update-center QML invokes a package manager directly'
fi
for package_update_contract in \
    'function openSystemUpdater()' \
    'updateService.launchPackageUpdate()' \
    'typeof panel.ownerWidget.close === "function"' \
    'panel.ownerWidget.close()' \
    'objectName: "packageFooterRefresh"' \
    'objectName: "packageFooterSystemUpdate"' \
    'onClicked: root.openSystemUpdater()'; do
  rg -Fq "$package_update_contract" "$packages" \
    || fail "system update close contract drifted: $package_update_contract"
done
rg -q 'OMARCHY_THEME_UPDATE_STATE=' "$service" \
  || fail 'theme check/apply does not share pinned state'
rg -q 'bash", themeApplyScript, name, target' "$service" \
  || fail 'theme apply does not pass the reviewed target commit'
rg -q 'bash", themeApplyScript, "--all"' "$service" \
  || fail 'bulk theme apply does not use the pinned apply helper'
rg -q 'themeReviewScript' "$service" \
  || fail 'theme review does not use the pinned review helper'
for theme_review_close_contract in \
    'function openThemeReview(theme)' \
    'if (!updateService.viewThemeChanges(theme)) return false' \
    'typeof panel.ownerWidget.close === "function"' \
    'panel.ownerWidget.close()'; do
  rg -Fq "$theme_review_close_contract" "$themes" \
    || fail "theme review close contract drifted: $theme_review_close_contract"
done
theme_review_triggers=$(rg -c -F \
  'onClicked: root.openThemeReview(modelData)' "$themes")
[[ $theme_review_triggers -eq 2 ]] \
  || fail 'both theme review triggers must share the close-aware action'
if sed -n '/text: root\.updateService\.themeRefreshing ? "Checking…" : "Check themes"/,/onClicked: root\.updateService\.refreshThemes()/p' \
    "$themes" | rg -q 'iconText:'; then
  fail 'check-themes text action still includes an icon'
fi
if sed -n '/text: root\.updateService\.currentThemeNeedsReapply/,/onClicked: root\.updateService\.reapplyCurrentTheme()/p' \
    "$themes" | rg -q 'iconText:'; then
  fail 'Re-Apply text action still includes an icon'
fi
for theme_footer_contract in \
    'return "re-applying"' \
    '? "Re-Apply the active theme below"' \
    'objectName: "themeFooterActions"' \
    'objectName: "themeFooterReapply"' \
    'objectName: "themeFooterCheck"' \
    'objectName: "themeFooterUpdate"' \
    '? "Re-Apply current" : "Re-Apply"' \
    'tooltipText: "Re-Apply the active user theme"' \
    'onClicked: root.updateService.reapplyCurrentTheme()' \
    'onClicked: root.updateService.refreshThemes()' \
    'onClicked: root.updateService.updateAllThemes()'; do
  rg -Fq "$theme_footer_contract" "$themes" \
    || fail "theme footer action drifted: $theme_footer_contract"
done
reapply_action_line=$(rg -n -m1 -F \
  'onClicked: root.updateService.reapplyCurrentTheme()' "$themes" \
  | cut -d: -f1)
check_action_line=$(rg -n -m1 -F \
  'onClicked: root.updateService.refreshThemes()' "$themes" \
  | cut -d: -f1)
update_action_line=$(rg -n -m1 -F \
  'onClicked: root.updateService.updateAllThemes()' "$themes" \
  | cut -d: -f1)
(( reapply_action_line < check_action_line
    && check_action_line < update_action_line )) \
  || fail 'theme footer order must be Re-Apply, Check themes, Update clean'
for reapply_status_contract in \
    'actionStatus = "Re-Applying " + name + "…"' \
    'actionStatus = "Re-Applied " + completedName'; do
  rg -Fq "$reapply_status_contract" "$service" \
    || fail "Re-Apply status label drifted: $reapply_status_contract"
done
[[ -x $review ]] || fail 'theme review helper is not executable'
if rg -n '(font\.family|fontFamily): root\.bar\.fontFamily' \
    --glob '*.qml' "$plugin" >/dev/null; then
  fail 'update-center teardown can dereference a released bar font'
fi

mkdir -p "$tmpdir/runtime"
chmod 700 "$tmpdir/runtime"
install -m 0644 "$repo_root/tests/update-center-model-smoke.qml" \
  "$tmpdir/shell.qml"
install -m 0644 "$plugin/Model.js" "$tmpdir/Model.js"
set +e
output=$(timeout 8 env \
  QT_QPA_PLATFORM=offscreen \
  WAYLAND_DISPLAY= \
  XDG_RUNTIME_DIR="$tmpdir/runtime" \
  "$quickshell_bin" -p "$tmpdir" 2>&1)
rc=$?
set -e
printf '%s\n' "$output"
[[ $rc -eq 0 ]] || fail "model smoke exited $rc"
grep -F 'update center model smoke passed' <<<"$output" >/dev/null \
  || fail 'model smoke success marker is missing'

rm -rf -- "$tmpdir/runtime"
mkdir -m 700 "$tmpdir/runtime"
cp -a -- "$plugin" "$tmpdir/update"
install -m 0644 "$repo_root/tests/fixtures/UpdateCenterTestSurface.qml" \
  "$tmpdir/update/ShibumiPanel.qml"
cp -a -- "$omarchy_path/shell/Commons" "$tmpdir/Commons"
cp -a -- "$omarchy_path/shell/Ui" "$tmpdir/Ui"
install -m 0644 "$repo_root/tests/update-center-ui-smoke.qml" \
  "$tmpdir/shell.qml"
set +e
output=$(timeout 8 env \
  QT_QPA_PLATFORM=offscreen \
  WAYLAND_DISPLAY= \
  XDG_RUNTIME_DIR="$tmpdir/runtime" \
  "$quickshell_bin" -p "$tmpdir" 2>&1)
rc=$?
set -e
printf '%s\n' "$output"
[[ $rc -eq 0 ]] || fail "UI smoke exited $rc"
grep -F 'update center UI smoke passed' <<<"$output" >/dev/null \
  || fail 'UI smoke success marker is missing'

install -m 0644 "$repo_root/tests/update-center-owner-smoke.qml" \
  "$tmpdir/shell.qml"
set +e
output=$(timeout 8 env \
  QT_QPA_PLATFORM=offscreen \
  WAYLAND_DISPLAY= \
  XDG_RUNTIME_DIR="$tmpdir/runtime" \
  "$quickshell_bin" -p "$tmpdir" 2>&1)
rc=$?
set -e
printf '%s\n' "$output"
[[ $rc -eq 0 ]] || fail "owner smoke exited $rc"
grep -F 'update center owner smoke passed' <<<"$output" >/dev/null \
  || fail 'owner smoke success marker is missing'
if grep -F 'Binding loop detected' <<<"$output" >/dev/null; then
  fail 'update center owner lifecycle produced a binding loop'
fi

"$repo_root/tests/update-center-package-regression.sh"
"$repo_root/tests/update-center-theme-regression.sh"

printf 'update center regression passed\n'
