#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
helper="$repo_root/shared/telemetry/shibumi-gpu-probe"
fixture_bin="$repo_root/tests/fixtures/gpu-bin"
fixture_root=$(mktemp -d /tmp/shibumi-gpu-probe.XXXXXX)
trap 'rm -rf -- "$fixture_root"' EXIT

fail() {
  printf 'GPU probe regression failed: %s\n' "$*" >&2
  exit 1
}

[[ -x $helper ]] || fail "helper is missing or not executable"

nvidia_output=$(PATH="$fixture_bin:/usr/bin" "$helper" 1)
grep -Fxq 'nvidia|28|39|1908|8192' <<<"$nvidia_output" \
  || fail "NVIDIA summary changed"
grep -Fxq 'meta|NVIDIA GeForce RTX 2080 SUPER|nvidia|610.43.03' \
  <<<"$nvidia_output" || fail "NVIDIA model or driver changed"
grep -Fxq 'status|ok' <<<"$nvidia_output" \
  || fail "NVIDIA completion marker changed"
grep -Fxq 'proc|101|17|183|Hyprland' <<<"$nvidia_output" \
  || fail "NVIDIA multi-sample utilization retention changed"
grep -Fxq 'proc|102|-1|941|electron' <<<"$nvidia_output" \
  || fail "NVIDIA unknown utilization was fabricated as zero"
grep -Fxq 'proc|103|21|264|renderer' <<<"$nvidia_output" \
  || fail "NVIDIA multi-sample maximum aggregation changed"
if grep -Fq 'other-gpu' <<<"$nvidia_output"; then
  fail "NVIDIA process rows crossed GPU ownership"
fi
if grep -Eq '^proc\|[^|]+\|0\|' <<<"$nvidia_output"; then
  fail "NVIDIA unknown utilization regressed to a false zero"
fi

sys_root="$fixture_root/sys"
proc_root="$fixture_root/proc"
pci_root="$sys_root/bus/pci/devices/0000:03:00.0"
mkdir -p "$sys_root/class/drm/card0" "$pci_root/hwmon/hwmon0" \
  "$sys_root/bus/pci/drivers/amdgpu" "$sys_root/module/amdgpu" \
  "$proc_root/201/fdinfo"
ln -s "$pci_root" "$sys_root/class/drm/card0/device"
ln -s "$sys_root/bus/pci/drivers/amdgpu" "$pci_root/driver"
printf '%s\n' 47 >"$pci_root/gpu_busy_percent"
printf '%s\n' 56000 >"$pci_root/hwmon/hwmon0/temp1_input"
printf '%s\n' 17179869184 >"$pci_root/mem_info_vram_total"
printf '%s\n' 4294967296 >"$pci_root/mem_info_vram_used"
printf '%s\n' 6.14.2 >"$sys_root/module/amdgpu/version"
printf '%s\n' game >"$proc_root/201/comm"
printf '%s\n' \
  'drm-driver: amdgpu' \
  'drm-pdev: 0000:03:00.0' \
  'drm-client-id: 7' \
  'drm-engine-gfx: 600000000 ns' \
  'drm-engine-compute: 200000000 ns' \
  'drm-memory-vram: 524288 KiB' \
  >"$proc_root/201/fdinfo/3"

amd_output=$(env \
  PATH="$fixture_bin:/usr/bin" \
  SHIBUMI_GPU_DISABLE_NVIDIA=1 \
  SHIBUMI_GPU_SYS_ROOT="$sys_root" \
  SHIBUMI_GPU_PROC_ROOT="$proc_root" \
  SHIBUMI_TEST_GPU_MODEL='AMD Radeon RX 7900 XTX' \
  "$helper" 1)
grep -Fxq 'sysfs|47|56|4096|16384' <<<"$amd_output" \
  || fail "AMD summary or VRAM conversion changed"
grep -Fxq 'meta|AMD Radeon RX 7900 XTX|amdgpu|6.14.2' <<<"$amd_output" \
  || fail "AMD model or driver changed"
grep -Fxq 'status|ok' <<<"$amd_output" \
  || fail "AMD completion marker changed"
grep -Fxq 'counter|201|800000000|512|game' <<<"$amd_output" \
  || fail "AMD process counters changed"

rm "$sys_root/class/drm/card0/device" "$pci_root/driver"
mkdir -p "$sys_root/bus/pci/drivers/xe" "$sys_root/module/xe" \
  "$proc_root/301/fdinfo"
intel_pci_root="$sys_root/bus/pci/devices/0000:04:00.0"
mkdir -p "$intel_pci_root/hwmon/hwmon0"
ln -s "$intel_pci_root" "$sys_root/class/drm/card0/device"
ln -s "$sys_root/bus/pci/drivers/xe" "$intel_pci_root/driver"
printf '%s\n' 31 >"$intel_pci_root/gpu_busy_percent"
printf '%s\n' 49000 >"$intel_pci_root/hwmon/hwmon0/temp1_input"
printf '%s\n' compositor >"$proc_root/301/comm"
printf '%s\n' \
  'drm-driver: xe' \
  'drm-pdev: 0000:04:00.0' \
  'drm-client-id: 9' \
  'drm-engine-render: 550000000 ns' \
  'drm-memory-system: 262144 KiB' \
  >"$proc_root/301/fdinfo/4"

intel_output=$(env \
  PATH="$fixture_bin:/usr/bin" \
  SHIBUMI_GPU_DISABLE_NVIDIA=1 \
  SHIBUMI_GPU_SYS_ROOT="$sys_root" \
  SHIBUMI_GPU_PROC_ROOT="$proc_root" \
  SHIBUMI_TEST_GPU_MODEL='Intel Arc A770' \
  "$helper" 1)
grep -Fxq 'sysfs|31|49|0|0' <<<"$intel_output" \
  || fail "Intel summary changed"
grep -Fxq 'meta|Intel Arc A770|xe|' <<<"$intel_output" \
  || fail "Intel model or driver changed"
grep -Fxq 'status|ok' <<<"$intel_output" \
  || fail "Intel completion marker changed"
grep -Fxq 'counter|301|550000000|256|compositor' <<<"$intel_output" \
  || fail "Intel process counters changed"

summary_output=$(env \
  PATH="$fixture_bin:/usr/bin" \
  SHIBUMI_GPU_DISABLE_NVIDIA=1 \
  SHIBUMI_GPU_SYS_ROOT="$sys_root" \
  SHIBUMI_GPU_PROC_ROOT="$proc_root" \
  SHIBUMI_TEST_GPU_MODEL='Intel Arc A770' \
  "$helper" 0)
if grep -Eq '^(proc|counter)\|' <<<"$summary_output"; then
  fail "summary probe scanned process details"
fi

printf 'GPU probe regression passed\n'
