#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

python3 "$repo_root/tests/test_shibumi_health.py"

health_runner="$repo_root/hancore.shibumi.control-center/manager/shibumi-health"
health_contract="$repo_root/docs/health-diagnostics.md"
health_service="$repo_root/hancore.shibumi.control-center/HealthService.qml"
bar_widget="$repo_root/hancore.shibumi.control-center/BarWidget.qml"
control_panel="$repo_root/hancore.shibumi.control-center/ControlCenterPanel.qml"

[[ -x $health_runner ]] || {
  printf 'health diagnostics regression failed: runner is not executable\n' >&2
  exit 1
}

for contract in \
  '"schemaVersion": 1' \
  '"overall": overall' \
  '"checks": [asdict(check) for check in self.checks]' \
  '["git", "-C", str(root), *arguments]' \
  '"--no-tags"' \
  '"--quiet"' \
  '"status", "--porcelain=v1"' \
  '"rev-list", "--left-right", "--count"' \
  '"SHIBUMI_HEALTH_FETCH_TIMEOUT", 12' \
  '["qs", "list", "--all", "--json"]' \
  '[str(command), "shell", "ping"]' \
  '"--tail",' \
  'SENSITIVE_PATTERNS'; do
  rg -Fq "$contract" "$health_runner" || {
    printf 'health diagnostics regression failed: missing %s\n' "$contract" >&2
    exit 1
  }
done

for contract in \
  'function runChecks(fetchUpdates)' \
  'function ensureFresh(maxAgeSeconds)' \
  '"timeout", "--signal=TERM", "--kill-after=1s", "16s"' \
  'if (healthProbe.running || healthCommand === "") return false' \
  'Number(parsed.schemaVersion || 0) !== 1' \
  'typeof parsed.summary !== "string"' \
  'Array.isArray(parsed.checks)'; do
  rg -Fq "$contract" "$health_service" || {
    printf 'health diagnostics regression failed: missing service contract %s\n' \
      "$contract" >&2
    exit 1
  }
done

rg -Fq 'HealthService { id: healthState }' "$bar_widget" \
  || { printf 'health diagnostics regression failed: lifecycle owner missing\n' >&2; exit 1; }
rg -Fq 'if (opened) healthState.ensureFresh(300)' "$bar_widget" \
  || { printf 'health diagnostics regression failed: open refresh missing\n' >&2; exit 1; }
rg -Fq 'required property var healthService' "$control_panel" \
  || { printf 'health diagnostics regression failed: panel facade missing\n' >&2; exit 1; }

if rg -q 'Timer\s*\{' "$health_service"; then
  printf 'health diagnostics regression failed: health service must not poll\n' >&2
  exit 1
fi

rg -Fq 'Lock**, **Suspend**, **Reboot**, and **Shutdown** remain in Omarchy' \
  "$health_contract" || {
    printf 'health diagnostics regression failed: retired actions undocumented\n' >&2
    exit 1
  }

printf 'health diagnostics regression passed\n'
