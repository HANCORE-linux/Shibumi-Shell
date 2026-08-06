#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source "$repo_root/tests/lib/baselines.sh"
shibumi_load_omarchy_baseline
omarchy_path=$OMARCHY_PATH
suite="$repo_root/contracts/plugin-suite-v1.json"
registry="$omarchy_path/shell/services/PluginRegistry.qml"
shell_root="$omarchy_path/shell/shell.qml"
plugin_add_cli="$omarchy_path/bin/omarchy-plugin-add"
legacy_plugin_cli="$omarchy_path/bin/omarchy-plugin"
keyboard_panel="$omarchy_path/shell/Ui/KeyboardPanel.qml"

fail() {
  printf 'Quattro contract regression failed: %s\n' "$*" >&2
  exit 1
}

command -v jq >/dev/null 2>&1 || fail 'jq is required'
command -v rg >/dev/null 2>&1 || fail 'ripgrep is required'
[[ -x $omarchy_path/bin/omarchy ]] || fail "missing Omarchy CLI below $omarchy_path"
[[ -x $omarchy_path/bin/omarchy-plugin-validate ]] || fail 'missing official plugin validator'
[[ -f $registry && -f $shell_root && -f $keyboard_panel ]] \
  || fail 'Omarchy Quattro plugin host sources are incomplete'
[[ -x $plugin_add_cli || -x $legacy_plugin_cli ]] \
  || fail 'Omarchy Quattro plugin add command is missing'

[[ ! -e $repo_root/manifest.json ]] \
  || fail 'suite root must not masquerade as one native Omarchy plugin'
if "$omarchy_path/bin/omarchy" plugin validate "$repo_root" >/dev/null 2>&1; then
  fail 'suite root unexpectedly passes the single-plugin validator'
fi

mapfile -t plugin_ids < <(jq -r '.plugins[].id' "$suite")
[[ ${#plugin_ids[@]} -eq 24 ]] || fail 'suite must contain exactly 24 plugins'

for plugin_id in "${plugin_ids[@]}"; do
  directory="$repo_root/$plugin_id"
  manifest="$directory/manifest.json"
  [[ -f $manifest ]] || fail "missing manifest for $plugin_id"
  "$omarchy_path/bin/omarchy" plugin validate "$directory" >/dev/null \
    || fail "official validator rejected $plugin_id"
  [[ $(jq -r '.id' "$manifest") == "$plugin_id" ]] \
    || fail "manifest id does not match directory for $plugin_id"

  while IFS=$'\t' read -r kind entry_key; do
    entry_path=$(jq -r --arg key "$entry_key" '.entryPoints[$key] // empty' "$manifest")
    [[ -n $entry_path && -f $directory/$entry_path ]] \
      || fail "$plugin_id has no loadable $entry_key entry point for kind $kind"
  done < <(jq -r '
    .kinds[] |
    [., ({"bar":"bar", "bar-widget":"barWidget", "service":"service",
          "menu":"menu", "panel":"panel", "overlay":"overlay"}[.] // "")]
    | @tsv
  ' "$manifest")

  if rg -n --glob '*.qml' '^\s*ShellRoot\s*\{' "$directory" >/dev/null; then
    fail "$plugin_id declares its own ShellRoot"
  fi
done

# Quattro's native add/update flow consumes exactly one root manifest and one
# manifest id. Shibumi therefore needs its suite adapter for atomic 24-plugin
# lifecycle handling instead of pretending that `omarchy plugin add <repo>` is
# a supported install path.
plugin_add_contract=$plugin_add_cli
if [[ ! -x $plugin_add_contract ]]; then
  plugin_add_contract=$legacy_plugin_cli
fi
rg -Fq 'omarchy-plugin-validate "$stage"' "$plugin_add_contract" \
  || fail 'native plugin add no longer validates one staged root'
rg -Fq 'id=$(jq -r '\''.id'\'' "$stage/manifest.json")' "$plugin_add_contract" \
  || fail 'native plugin add no longer resolves one root manifest id'
if [[ -x $plugin_add_cli ]]; then
  rg -Fq 'omarchy-shell shell rescanPlugins' "$plugin_add_cli" \
    || fail 'split plugin add no longer rescans through the shell IPC contract'
fi
rg -Fq 'self.run([self.command("omarchy-shell"), "shell", "rescanPlugins"])' \
  "$repo_root/scripts/shibumi_suite/runtime.py" \
  || fail 'suite lifecycle adapter retains the retired plugin rescan route'
rg -Fq 'def reload_config(self, *, timeout: float = 30)' \
  "$repo_root/scripts/shibumi_suite/runtime.py" \
  || fail 'suite reload settling window is too short for a full-bar switch'
rg -Fq 'timeout: float = 60' \
  "$repo_root/scripts/shibumi_suite/runtime.py" \
  || fail 'suite verification settling window is too short for Quattro reload'

for needle in \
  'scan_thirdparty' \
  'for sub in \"$dir\"/*/' \
  'Third-party plugins never shadow first-party ids' \
  'function entryPointUrl' \
  'function isEnabled'; do
  rg -Fq "$needle" "$registry" || fail "PluginRegistry contract drift: $needle"
done

for needle in \
  'function configureBar' \
  'target.omarchyPath = shell.omarchyPath' \
  'target.shell = shell' \
  'target.manifest = manifest' \
  'target.barWidgetRegistry = shell.barWidgetRegistry' \
  'target.pluginRegistry = shell.pluginRegistry' \
  'target.barConfig = shell.barConfig' \
  'falling back to'; do
  rg -Fq "$needle" "$shell_root" || fail "shell host contract drift: $needle"
done

for needle in \
  'property var borderSpec:' \
  'readonly property point cardOrigin:' \
  'BorderSurface {' \
  'id: card' \
  'radius: Style.cornerRadius'; do
  rg -Fq "$needle" "$keyboard_panel" \
    || fail "KeyboardPanel compatibility surface drift: $needle"
done

omarchy_version=unknown
for package_name in omarchy omarchy-dev; do
  if package_version=$(pacman -Q "$package_name" 2>/dev/null | awk '{print $2}'); then
    omarchy_version=$package_version
    break
  fi
done

printf 'Quattro contract regression passed (%s, %d plugins)\n' \
  "$omarchy_version" "${#plugin_ids[@]}"
