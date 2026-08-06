#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source "$repo_root/tests/lib/baselines.sh"
shibumi_load_omarchy_baseline
omarchy_path=$OMARCHY_PATH
quickshell_bin=${QUICKSHELL_BIN:-/usr/bin/quickshell}
tmpdir=$(mktemp -d /tmp/shibumi-storage.XXXXXX)
trap 'rm -rf -- "$tmpdir"' EXIT

fail() {
  printf 'storage plugin regression failed: %s\n' "$*" >&2
  exit 1
}

[[ -d $omarchy_path/shell ]] || fail "Omarchy shell not found: $omarchy_path/shell"
[[ -x $quickshell_bin ]] || fail "Quickshell not found: $quickshell_bin"

mkdir -p "$tmpdir/runtime"
chmod 700 "$tmpdir/runtime"
cp -a -- "$repo_root/hancore.shibumi.storage" "$tmpdir/storage"
install -m 0644 "$repo_root/tests/fixtures/ShibumiPanelTest.qml" \
  "$tmpdir/storage/ShibumiPanel.qml"
cp -a -- "$omarchy_path/shell/Commons" "$tmpdir/Commons"
cp -a -- "$omarchy_path/shell/Ui" "$tmpdir/Ui"
install -m 0644 "$repo_root/tests/storage-plugin-smoke.qml" "$tmpdir/shell.qml"
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
grep -F 'storage plugin smoke passed' <<<"$output" >/dev/null \
  || fail "success marker missing"
if grep -Eq 'storage-plugin-smoke:|TypeError|ReferenceError|Binding loop|Unable to assign' \
    <<<"$output"; then
  fail "QML runtime error detected"
fi
telemetry="$repo_root/hancore.shibumi.storage/StorageTelemetry.qml"
panel="$repo_root/hancore.shibumi.storage/StoragePanel.qml"
widget="$repo_root/hancore.shibumi.storage/BarWidget.qml"
rg -Fq 'device.type !== "disk"' "$telemetry" \
  || fail "inventory no longer filters physical disks"
rg -Fq '/^(loop|ram|zram)/' "$telemetry" \
  || fail "virtual block devices are not excluded"
rg -Fq '"--output=source,size,used,avail,pcent"' "$telemetry" \
  || fail "root device evidence is missing"
if rg -q 'udisksctl|requestVolumeAction|actionCommandFor|storageAction|canMount|canUnmount|TextAction' \
    "$telemetry" "$panel"; then
  fail "storage write capability returned"
fi
if rg -Fq 'driveRow.modelData.percent)) / 100' "$panel"; then
  fail "per-drive progress bars returned"
fi
if rg -Fq 'summaryPercent)) / 100' "$panel"; then
  fail "storage summary progress bar returned"
fi
for panel_contract in \
  'function freeSummary(usedPercent, freeBytes, totalBytes)' \
  'return (100 - usage) + "% FREE · "' \
  'panel.freeSummary(driveRow.modelData.percent' \
  'driveRow.modelData.freeBytes' \
  'driveRow.modelData.totalBytes'; do
  rg -Fq "$panel_contract" "$panel" \
    || fail "compact storage panel contract missing: $panel_contract"
done
for selection_contract in \
  'readonly property int selectedPercent:' \
  'stateService.setGroupSetting(stateGroupId, "source", target)' \
  'text: String(Math.min(100, root.selectedPercent))'; do
  rg -Fq "$selection_contract" "$widget" \
    || fail "storage bar selection contract missing: $selection_contract"
done
for selection_contract in \
  'ownerWidget.stateService.paletteColor("color04")' \
  '"NOT MOUNTED"' \
  'label: "LSBLK INFO"' \
  'label: panel.barTabLabel' \
  'function showInfo(source)' \
  'id: infoRing' \
  'id: infoDot' \
  'id: infoStem' \
  'Accessible.name: "LSBLK INFO"' \
  'panel.detailRows()' \
  'String(panel.detailDrive.volumes.length)' \
  'rootChoicePointer.containsMouse' \
  'drivePointer.containsMouse' \
  'panel.controlHoverFillColor' \
  'panel.controlBorderWidth' \
  'panel.selectSource("root")' \
  'panel.ownerWidget.selectedSource === String(modelData.path || "")' \
  'ownerWidget.setStorageSource(target)'; do
  rg -Fq "$selection_contract" "$panel" \
    || fail "storage panel selection contract missing: $selection_contract"
done
for bar_accent_contract in \
  'color: selected ? panel.controlActiveFillColor' \
  'color: driveRow.selected ? panel.controlActiveFillColor' \
  'border.color: selected || activeFocus ? panel.controlAccent' \
  '? panel.controlAccent : driveRow.hovered' \
  'accent: panel.controlAccent' \
  'border.color: panel.controlAccent'; do
  rg -Fq "$bar_accent_contract" "$panel" \
    || fail "storage controls lost standard color roles: $bar_accent_contract"
done
if rg -Fq 'paletteColor("color03")' "$panel"; then
  fail "storage selection still has a panel-specific color03 role"
fi
[[ $(rg -Fc 'spacing: panel.driveGroupSpacing' "$panel") -eq 2 ]] \
  || fail "drive group separator spacing is not symmetric"

printf 'storage plugin regression passed\n'
