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

nvidia_sys="$fixture_root/nvidia-sys"
nvidia_pci="$nvidia_sys/bus/pci/devices/0000:01:00.0"
mkdir -p "$nvidia_sys/class/drm/card0" "$nvidia_pci" \
  "$nvidia_sys/bus/pci/drivers/nvidia"
ln -s "$nvidia_pci" "$nvidia_sys/class/drm/card0/device"
ln -s "$nvidia_sys/bus/pci/drivers/nvidia" "$nvidia_pci/driver"
nvidia_output=$(env \
  PATH="$fixture_bin:/usr/bin" \
  SHIBUMI_GPU_SYS_ROOT="$nvidia_sys" \
  "$helper")
[[ $(sed -n '1p' <<<"$nvidia_output") \
    == 'nvidia|28|39|1908|8192' \
  && $(sed -n '2p' <<<"$nvidia_output") \
    == 'meta|NVIDIA GeForce RTX 2080 SUPER|nvidia|610.43.03' ]] \
  || fail "pre-upgrade NVIDIA parser compatibility changed"
grep -Fxq 'device|pci:0000:01:00.0|nvidia|28|39|1908|8192|NVIDIA GeForce RTX 2080 SUPER|nvidia|610.43.03|' \
  <<<"$nvidia_output" || fail "first NVIDIA device changed"
grep -Fxq 'device|pci:0000:02:00.0|nvidia|72|61|12288|24576|NVIDIA GeForce RTX 4090|nvidia|610.43.03|' \
  <<<"$nvidia_output" || fail "second NVIDIA device changed"
[[ $(grep -c '^device|' <<<"$nvidia_output") -eq 2 ]] \
  || fail "NVIDIA devices were duplicated through DRM"
grep -Fxq 'status|ok' <<<"$nvidia_output" \
  || fail "NVIDIA completion marker changed"
if grep -Eq '^(proc|counter)\|' <<<"$nvidia_output"; then
  fail "NVIDIA probe still emits process details"
fi

nvidia_fallback_output=$(env \
  PATH="$fixture_bin:/usr/bin" \
  SHIBUMI_GPU_SYS_ROOT="$nvidia_sys" \
  SHIBUMI_TEST_NVIDIA_MALFORMED_BUS=1 \
  SHIBUMI_TEST_GPU_MODEL='Fallback NVIDIA GPU' \
  "$helper")
grep -Fxq 'device|pci:0000:01:00.0|sysfs|0|0|0|0|Fallback NVIDIA GPU|nvidia||card0' \
  <<<"$nvidia_fallback_output" \
  || fail "malformed NVIDIA PCI ID did not fall back to stable DRM identity"
[[ $(grep -c '^device|' <<<"$nvidia_fallback_output") -eq 1 ]] \
  || fail "malformed NVIDIA PCI ID duplicated the DRM device"
if grep -Fq 'nvidia:' <<<"$nvidia_fallback_output"; then
  fail "unstable NVIDIA runtime index was published"
fi

nvidia_na_output=$(env \
  PATH="$fixture_bin:/usr/bin" \
  SHIBUMI_GPU_SYS_ROOT="$nvidia_sys" \
  SHIBUMI_TEST_NVIDIA_NA=1 \
  SHIBUMI_TEST_GPU_MODEL='Fallback NVIDIA GPU' \
  "$helper")
grep -Fxq 'device|pci:0000:01:00.0|sysfs|0|0|0|0|Fallback NVIDIA GPU|nvidia||card0' \
  <<<"$nvidia_na_output" \
  || fail "invalid NVIDIA metrics did not fall back to DRM telemetry"
if grep -Fq '|nvidia|0|39|1908|8192|' <<<"$nvidia_na_output"; then
  fail "invalid NVIDIA metrics created a false NVIDIA backend"
fi

amd_sys="$fixture_root/amd-sys"
mkdir -p "$amd_sys/class/drm/card0" "$amd_sys/class/drm/card1" \
  "$amd_sys/bus/pci/drivers/amdgpu" "$amd_sys/module/amdgpu"
printf '%s\n' 6.14.2 >"$amd_sys/module/amdgpu/version"

amd_igpu="$amd_sys/bus/pci/devices/0000:03:00.0"
mkdir -p "$amd_igpu/hwmon/hwmon0"
ln -s "$amd_igpu" "$amd_sys/class/drm/card0/device"
ln -s "$amd_sys/bus/pci/drivers/amdgpu" "$amd_igpu/driver"
printf '%s\n' 17 >"$amd_igpu/gpu_busy_percent"
printf '%s\n' 49000 >"$amd_igpu/hwmon/hwmon0/temp1_input"

amd_dgpu="$amd_sys/bus/pci/devices/0000:04:00.0"
mkdir -p "$amd_dgpu/hwmon/hwmon0"
ln -s "$amd_dgpu" "$amd_sys/class/drm/card1/device"
ln -s "$amd_sys/bus/pci/drivers/amdgpu" "$amd_dgpu/driver"
printf '%s\n' 73 >"$amd_dgpu/gpu_busy_percent"
printf '%s\n' 61000 >"$amd_dgpu/hwmon/hwmon0/temp1_input"
printf '%s\n' 17179869184 >"$amd_dgpu/mem_info_vram_total"
printf '%s\n' 4294967296 >"$amd_dgpu/mem_info_vram_used"

amd_output=$(env \
  PATH="$fixture_bin:/usr/bin" \
  SHIBUMI_GPU_DISABLE_NVIDIA=1 \
  SHIBUMI_GPU_SYS_ROOT="$amd_sys" \
  SHIBUMI_TEST_GPU_MODEL_03='AMD Ryzen 9 7950X Integrated Graphics' \
  SHIBUMI_TEST_GPU_MODEL_04='AMD Radeon RX 7900 XTX' \
  "$helper")
[[ $(sed -n '1p' <<<"$amd_output") == 'sysfs|17|49|0|0' \
  && $(sed -n '2p' <<<"$amd_output") \
    == 'meta|AMD Ryzen 9 7950X Integrated Graphics|amdgpu|6.14.2' ]] \
  || fail "pre-upgrade AMD parser compatibility changed"
grep -Fxq 'device|pci:0000:03:00.0|sysfs|17|49|0|0|AMD Ryzen 9 7950X Integrated Graphics|amdgpu|6.14.2|card0' \
  <<<"$amd_output" || fail "AMD integrated GPU changed"
grep -Fxq 'device|pci:0000:04:00.0|sysfs|73|61|4096|16384|AMD Radeon RX 7900 XTX|amdgpu|6.14.2|card1' \
  <<<"$amd_output" || fail "AMD dedicated GPU changed"
[[ $(grep -c '^device|' <<<"$amd_output") -eq 2 ]] \
  || fail "multi-AMD enumeration changed"
grep -Fxq 'status|ok' <<<"$amd_output" \
  || fail "AMD completion marker changed"
if grep -Eq '^(proc|counter)\|' <<<"$amd_output"; then
  fail "AMD probe still emits process details"
fi

intel_sys="$fixture_root/intel-sys"
intel_pci="$intel_sys/bus/pci/devices/0000:05:00.0"
mkdir -p "$intel_sys/class/drm/card0" "$intel_pci/hwmon/hwmon0" \
  "$intel_sys/bus/pci/drivers/xe" "$intel_sys/module/xe"
ln -s "$intel_pci" "$intel_sys/class/drm/card0/device"
ln -s "$intel_sys/bus/pci/drivers/xe" "$intel_pci/driver"
printf '%s\n' 31 >"$intel_pci/gpu_busy_percent"
printf '%s\n' 49000 >"$intel_pci/hwmon/hwmon0/temp1_input"

intel_output=$(env \
  PATH="$fixture_bin:/usr/bin" \
  SHIBUMI_GPU_DISABLE_NVIDIA=1 \
  SHIBUMI_GPU_SYS_ROOT="$intel_sys" \
  SHIBUMI_TEST_GPU_MODEL='Intel Arc A770' \
  "$helper")
grep -Fxq 'device|pci:0000:05:00.0|sysfs|31|49|0|0|Intel Arc A770|xe||card0' \
  <<<"$intel_output" || fail "Intel device changed"
grep -Fxq 'status|ok' <<<"$intel_output" \
  || fail "Intel completion marker changed"
if grep -Eq '^(proc|counter)\|' <<<"$intel_output"; then
  fail "Intel probe still emits process details"
fi

printf 'GPU probe regression passed\n'
