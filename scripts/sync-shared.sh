#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
mode=${1:---check}

case "$mode" in
  --check | --write) ;;
  *)
    printf 'Usage: %s [--check|--write]\n' "$0" >&2
    exit 2
    ;;
esac

# ShibumiPanel retains three lifecycle timers, so it cannot enter the passive
# State presentation library. Keep its existing copies drift-checked until its
# scheduling contract can be separated without changing panel behavior.
mappings=(
  "shared/presentation/ShibumiPanel.qml:widgets/ShibumiPanel.qml"
  "shared/presentation/ShibumiPanel.qml:hancore.shibumi.control-center/ShibumiPanel.qml"
  "shared/presentation/ShibumiPanel.qml:hancore.shibumi.update-center/ShibumiPanel.qml"
  "shared/presentation/ShibumiPanel.qml:hancore.shibumi.memory/ShibumiPanel.qml"
  "shared/presentation/ShibumiPanel.qml:hancore.shibumi.cpu/ShibumiPanel.qml"
  "shared/presentation/ShibumiPanel.qml:hancore.shibumi.audio/ShibumiPanel.qml"
  "shared/presentation/ShibumiPanel.qml:hancore.shibumi.media/ShibumiPanel.qml"
  "shared/presentation/ShibumiPanel.qml:hancore.shibumi.workspaces/ShibumiPanel.qml"
  "shared/presentation/ShibumiPanel.qml:hancore.shibumi.status/ShibumiPanel.qml"
  "shared/presentation/ShibumiPanel.qml:hancore.shibumi.center/ShibumiPanel.qml"
  "shared/presentation/ShibumiPanel.qml:hancore.shibumi.network/ShibumiPanel.qml"
  "shared/presentation/ShibumiPanel.qml:hancore.shibumi.brightness/ShibumiPanel.qml"
  "shared/presentation/ShibumiPanel.qml:hancore.shibumi.bluetooth/ShibumiPanel.qml"
  "shared/presentation/ShibumiPanel.qml:hancore.shibumi.battery/ShibumiPanel.qml"
  "shared/presentation/ShibumiPanel.qml:hancore.shibumi.power-profile/ShibumiPanel.qml"
  "shared/presentation/ShibumiPanel.qml:hancore.shibumi.ai/ShibumiPanel.qml"
  "shared/presentation/ShibumiPanel.qml:hancore.shibumi.temperature/ShibumiPanel.qml"
  "shared/presentation/ShibumiPanel.qml:hancore.shibumi.gpu/ShibumiPanel.qml"
  "shared/presentation/ShibumiPanel.qml:hancore.shibumi.storage/ShibumiPanel.qml"
)

failed=0
for mapping in "${mappings[@]}"; do
  source_path=${mapping%%:*}
  target_path=${mapping#*:}
  source_file="$repo_root/$source_path"
  target_file="$repo_root/$target_path"

  [[ -f $source_file ]] || {
    printf 'Missing shared source: %s\n' "$source_path" >&2
    failed=1
    continue
  }

  if [[ $mode == --write ]]; then
    install -Dm0644 -- "$source_file" "$target_file"
  elif ! cmp -s -- "$source_file" "$target_file"; then
    printf 'Vendored file drift: %s -> %s\n' "$source_path" "$target_path" >&2
    failed=1
  fi
done

(( failed == 0 )) || exit 1
printf 'Shibumi active panel vendoring %s passed\n' "${mode#--}"
