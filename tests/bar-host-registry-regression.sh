#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source "$repo_root/tests/lib/baselines.sh"
shibumi_load_omarchy_baseline
bar_root="$repo_root/hancore.shibumi.bar"
omarchy_path=$OMARCHY_PATH

fail() {
  printf 'bar host registry regression failed: %s\n' "$*" >&2
  exit 1
}

for endpoint in 'function openControlCenter(): string' \
    'function closeControlCenter(): string' \
    'function setWidgetAppearanceForVariant(groupId: string, variant: string,'; do
  rg -Fq "$endpoint" "$repo_root/hancore.shibumi.bar/Bar.qml" \
    || fail "missing Shibumi Control Center IPC endpoint: $endpoint"
done
rg -Fq 'if (name !== "separator") return "variant-required"' \
  "$repo_root/hancore.shibumi.bar/Bar.qml" \
  || fail "legacy appearance IPC still accepts variant-scoped keys"
for v2_native_widget in \
    'hancore.shibumi.temperature' \
    'hancore.shibumi.gpu' \
    'hancore.shibumi.storage'; do
  rg -Fq "\"$v2_native_widget\"" "$repo_root/hancore.shibumi.bar/Bar.qml" \
    || fail "V2 does not suppress the V1 provider entry for $v2_native_widget"
done
rg -Fq '!GroupRegistry.isAssignedModule(id)' \
  "$repo_root/hancore.shibumi.bar/Bar.qml" \
  || fail "assigned suite widgets do not require explicit V1 installation"
rg -Fq 'else if (isV1AdditionalSuiteWidget(id))' \
  "$repo_root/hancore.shibumi.bar/Bar.qml" \
  || fail "V1 suite removal does not preserve the neutral host entry"
for provider_lifecycle_contract in \
    'function onPluginsChanged()' \
    'v1PluginReconcileTimer.restart()' \
    'function restoreWidgetFamilyProviderStates(stateValues)' \
    'function removeBarWidgetAndRestoreFamilies(widgetId, groupValues)' \
    'function conflictingLayoutProviderIds(widgetId)'; do
  rg -Fq "$provider_lifecycle_contract" \
    "$repo_root/hancore.shibumi.bar/Bar.qml" \
    || fail "provider lifecycle contract drifted: $provider_lifecycle_contract"
done

for bar_host in \
    "$repo_root/Bar.qml" \
    "$repo_root/hancore.shibumi.bar/Bar.qml"; do
  for fixed_property in \
      'readonly property bool requestedTransparent: false' \
      'readonly property bool transparent: false'; do
    rg -Fq "$fixed_property" "$bar_host" \
      || fail "opaque facade contract drifted in ${bar_host#$repo_root/}: $fixed_property"
  done
  if rg -q 'config\.transparent|^[[:space:]]*(requestedTransparent|transparent)[[:space:]]*=' \
      "$bar_host"; then
    fail "Shibumi applies the stock transparency preference in ${bar_host#$repo_root/}"
  fi
  rg -Uq 'function setRequestedTransparency\(value\) \{[^}]*return false' \
    "$bar_host" \
    || fail "transparency compatibility method is not a no-op in ${bar_host#$repo_root/}"
  rg -Fq 'function toggleGroupSeparator(groupId, editingValue)' "$bar_host" \
    || fail "V2 separator route lacks edit context in ${bar_host#$repo_root/}"
  rg -Fq 'layoutStateController.interactiveMutationAllowed(editingValue)' \
    "$bar_host" \
    || fail "V2 separator route bypasses layout protection in ${bar_host#$repo_root/}"
done

for bar_surface in \
    "$repo_root/styles/shibumi/BarSurface.qml" \
    "$repo_root/hancore.shibumi.bar/styles/shibumi/BarSurface.qml"; do
  rg -Fq 'visible: true' "$bar_surface" \
    || fail "V1/V2 chrome is not explicitly opaque in ${bar_surface#$repo_root/}"
  if rg -q 'bar\.transparent' "$bar_surface"; then
    fail "bar surface still consumes stock transparency in ${bar_surface#$repo_root/}"
  fi
done

[[ -n $omarchy_path && -d $omarchy_path/shell ]] \
  || fail 'OMARCHY_PATH must reference a Quattro checkout'
[[ -x /usr/bin/quickshell ]] || fail 'quickshell is required'
"$repo_root/scripts/sync-bar-host.sh" --check >/dev/null

tmpdir=$(mktemp -d /tmp/shibumi-bar-host.XXXXXX)
trap 'rm -rf -- "$tmpdir"' EXIT
mkdir -p "$tmpdir/home" "$tmpdir/runtime" "$tmpdir/fixtures"
chmod 700 "$tmpdir/runtime"

cp -a "$omarchy_path/shell/Commons" "$tmpdir/"
cp -a "$omarchy_path/shell/Ui" "$tmpdir/"
cp -a "$bar_root/core" "$tmpdir/"
cp "$repo_root/tests/fixtures/BarPanelStub.qml" "$tmpdir/core/BarPanel.qml"
mkdir -p "$tmpdir/services"
cp "$bar_root/services/HostWidgetResolver.qml" "$tmpdir/services/"
cp -a "$bar_root/styles" "$tmpdir/"
cp "$bar_root/Bar.qml" "$tmpdir/Bar.qml"
cp "$repo_root/tests/fixtures/ResolverTestWidget.qml" "$tmpdir/fixtures/"
cp "$repo_root/tests/fixtures/ResolverReplacementWidget.qml" "$tmpdir/fixtures/"
cp "$repo_root/tests/fixtures/DirectPreferredHostedPanelWidget.qml" "$tmpdir/fixtures/"
cp "$repo_root/tests/fixtures/MisleadingItemHostedPanelWidget.qml" "$tmpdir/fixtures/"
cp "$repo_root/tests/fixtures/NestedHostedPanelWidget.qml" "$tmpdir/fixtures/"
cp "$repo_root/tests/hosted-panel-loader-smoke.qml" "$tmpdir/shell.qml"

set +e
nested_output=$(timeout 8 env \
  HOME="$tmpdir/home" \
  DBUS_SESSION_BUS_ADDRESS= \
  WAYLAND_DISPLAY= \
  QT_QPA_PLATFORM=offscreen \
  QT_QPA_PLATFORMTHEME= \
  XDG_RUNTIME_DIR="$tmpdir/runtime" \
  /usr/bin/quickshell -p "$tmpdir" 2>&1)
nested_rc=$?
set -e
printf '%s\n' "$nested_output"

[[ $nested_rc -eq 0 ]] || fail "nested hosted-panel smoke exited $nested_rc"
grep -q 'hosted panel loader smoke passed' <<<"$nested_output" \
  || fail 'nested hosted-panel smoke did not reach its success marker'
if grep -Eq 'Binding loop|TypeError|ReferenceError|is not a type|failed to load' \
    <<<"$nested_output"; then
  fail 'nested hosted-panel runtime log contains a composition error'
fi

sed "s#testOmarchyPath#\"${omarchy_path//\\/\\\\}\"#" \
  "$repo_root/tests/bar-host-registry-smoke.qml" \
  | sed "s#testCommandMarker#\"$tmpdir/run-marker\"#" \
  > "$tmpdir/shell.qml"

set +e
output=$(timeout 6 env \
  HOME="$tmpdir/home" \
  DBUS_SESSION_BUS_ADDRESS= \
  WAYLAND_DISPLAY= \
  QT_QPA_PLATFORM=offscreen \
  QT_QPA_PLATFORMTHEME= \
  XDG_RUNTIME_DIR="$tmpdir/runtime" \
  /usr/bin/quickshell -p "$tmpdir" 2>&1)
rc=$?
set -e
printf '%s\n' "$output"

[[ $rc -eq 0 ]] || fail "smoke exited $rc"
grep -q 'bar host registry smoke passed' <<<"$output" \
  || fail 'smoke did not reach its success marker'
[[ $(<"$tmpdir/run-marker") == ok ]] \
  || fail 'bar run() did not execute through the Quattro host contract'
if grep -Eq 'Binding loop|TypeError|ReferenceError|is not a type|failed to load|rejected invalid bar style' \
    <<<"$output"; then
  fail 'runtime log contains a host composition error'
fi

printf 'bar host registry regression passed\n'
