#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
bar_root="$repo_root/hancore.shibumi.bar"
omarchy_path=${OMARCHY_PATH:-}

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
sed "s#testOmarchyPath#\"${omarchy_path//\\/\\\\}\"#" \
  "$repo_root/tests/bar-host-registry-smoke.qml" \
  | sed "s#testCommandMarker#\"$tmpdir/run-marker\"#" \
  > "$tmpdir/shell.qml"

set +e
output=$(timeout 6 env \
  HOME="$tmpdir/home" \
  QT_QPA_PLATFORM=offscreen \
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
