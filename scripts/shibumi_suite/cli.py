from __future__ import annotations

import argparse
import copy
import json
import re
import shutil
import sys
import time
from pathlib import Path
from typing import Any

from . import STATE_SCHEMA_VERSION, SUITE_ID
from .config import (
    apply_identity_contract,
    ConfigError,
    apply_profile,
    encode_config,
    entry_id,
    migrate_legacy_config,
    read_config,
    reconcile_profile_additions,
    reconcile_profile_services,
    remove_plugin_ids,
    remove_suite,
    select_omarchy_image_picker,
)
from .model import (
    ContractError,
    PluginSpec,
    Suite,
    plugin_payload_digest,
    suite_payload_digest,
)
from .menu_extension import (
    generated_extension_is_empty,
    install_picker_routing,
    read_extension,
    remove_picker_routing,
)
from .runtime import OmarchyRuntime, RuntimeFailure, RuntimePaths
from .transaction import (
    PluginTransaction,
    SuiteLock,
    TransactionError,
    is_managed_target,
    preflight_legacy_removals,
    preflight_removals,
    preflight_removal_ids,
    preflight_replacements,
    recover_transactions,
)


class CliError(RuntimeError):
    pass


LEGACY_SUITE_ID = "hancore.qsrise"
LEGACY_PLUGIN_PREFIX = "hancore.qsrise"
PLUGIN_PREFIX = "hancore.shibumi"
CONTINUITY_PLUGIN_IDS = {
    "hancore.shibumi.control-center",
    "hancore.shibumi.state",
}
PICKER_PLUGIN_ID = "hancore.shibumi.quick-access"


def repository_root() -> Path:
    return Path(__file__).resolve().parents[2]


def install_state_file(paths: RuntimePaths) -> Path:
    return paths.state_dir / "install.json"


def legacy_state_dir(paths: RuntimePaths) -> Path:
    return paths.state_dir.parent / "qsrise"


def legacy_cache_dir(paths: RuntimePaths) -> Path:
    return paths.cache_dir.parent / "qsrise"


def legacy_install_state_file(paths: RuntimePaths) -> Path:
    return legacy_state_dir(paths) / "install.json"


def legacy_plugin_id(plugin_id: str) -> str:
    if plugin_id == PLUGIN_PREFIX or plugin_id.startswith(PLUGIN_PREFIX + "."):
        return LEGACY_PLUGIN_PREFIX + plugin_id[len(PLUGIN_PREFIX):]
    raise CliError(f"cannot map Shibumi plugin id to legacy namespace: {plugin_id}")


def legacy_plugin_ids(suite: Suite) -> list[str]:
    return [legacy_plugin_id(plugin_id) for plugin_id in suite.plugins]


def load_legacy_install_state(paths: RuntimePaths, suite: Suite) -> dict[str, Any]:
    path = legacy_install_state_file(paths)
    try:
        state = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as error:
        raise CliError("legacy QS Rise suite state was not found") from error
    except (OSError, json.JSONDecodeError) as error:
        raise CliError(f"cannot read legacy install state {path}: {error}") from error

    expected_plugins = set(legacy_plugin_ids(suite))
    plugins = state.get("plugins") if isinstance(state, dict) else None
    if (
        not isinstance(state, dict)
        or state.get("schemaVersion") != STATE_SCHEMA_VERSION
        or state.get("suiteId") != LEGACY_SUITE_ID
        or not isinstance(plugins, list)
        or any(not isinstance(plugin_id, str) for plugin_id in plugins)
        or set(plugins) != expected_plugins
    ):
        raise CliError(f"legacy install state is incompatible: {path}")

    transactions = legacy_state_dir(paths) / "transactions"
    if transactions.is_dir() and any(transactions.iterdir()):
        raise CliError(
            "legacy QS Rise has an unfinished transaction; recover it with "
            "the old qsrise-suite before migrating"
        )
    return state


def load_install_state(paths: RuntimePaths, suite: Suite) -> dict[str, Any]:
    path = install_state_file(paths)
    try:
        state = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as error:
        raise CliError("Shibumi is not installed by this suite") from error
    except (OSError, json.JSONDecodeError) as error:
        raise CliError(f"cannot read install state {path}: {error}") from error
    if (
        not isinstance(state, dict)
        or state.get("schemaVersion") != STATE_SCHEMA_VERSION
        or state.get("suiteId") != SUITE_ID
        or not isinstance(state.get("plugins"), list)
        or not re.fullmatch(r"[0-9a-f]{64}", str(state.get("payloadDigest") or ""))
        or not isinstance(state.get("pluginDigests"), dict)
    ):
        raise CliError(f"invalid Shibumi install state: {path}")
    plugin_ids = state["plugins"]
    known_or_retired = set(suite.plugins) | set(suite.retired_plugins)
    if any(
        not isinstance(plugin_id, str) or plugin_id not in known_or_retired
        for plugin_id in plugin_ids
    ):
        raise CliError("install state references unknown plugins")
    if set(state["pluginDigests"]) != set(plugin_ids) or any(
        not re.fullmatch(r"[0-9a-f]{64}", str(value))
        for value in state["pluginDigests"].values()
    ):
        raise CliError("install state contains invalid plugin payload digests")
    if suite_payload_digest(state["pluginDigests"]) != state["payloadDigest"]:
        raise CliError("install state payload digest is inconsistent")
    origin = str(state.get("installOrigin") or "checkout")
    if origin not in ("checkout", "package"):
        raise CliError("install state contains an invalid payload origin")
    if origin == "package" and (
        state.get("packageName") != "shibumi-shell"
        or not isinstance(state.get("packageVersion"), str)
        or not state.get("packageVersion")
    ):
        raise CliError("package install state is missing authoritative metadata")
    return state


def version_key(value: str) -> tuple[int, int, int, int, tuple[tuple[int, Any], ...]]:
    identifier = r"[0-9A-Za-z-]+"
    match = re.fullmatch(
        r"(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)"
        rf"(?:-({identifier}(?:\.{identifier})*))?"
        rf"(?:\+{identifier}(?:\.{identifier})*)?",
        value,
    )
    if not match:
        raise CliError(f"unsupported Shibumi version: {value}")
    prerelease = match.group(4)
    prerelease_parts = prerelease.split(".") if prerelease else []
    if any(
        item.isdigit() and len(item) > 1 and item.startswith("0")
        for item in prerelease_parts
    ):
        raise CliError(f"unsupported Shibumi version: {value}")
    identifiers: tuple[tuple[int, Any], ...] = tuple(
        (0, int(item)) if item.isdigit() else (1, item)
        for item in prerelease_parts
    )
    return (
        int(match.group(1)),
        int(match.group(2)),
        int(match.group(3)),
        0 if prerelease else 1,
        identifiers,
    )


def refuse_downgrade(
    state: dict[str, Any], suite: Suite, *, allow: bool = False
) -> None:
    installed = str(state.get("suiteVersion") or "")
    if not allow and version_key(suite.version) < version_key(installed):
        raise CliError(
            f"refusing downgrade from {installed} to {suite.version}; "
            "install a compatible newer package or rerun an intentional package "
            "rollback with --allow-downgrade"
        )


def make_install_state(
    suite: Suite,
    plugin_ids: list[str],
    profile: str,
    active_bar: str,
    revision: str,
    payload_digest: str,
    plugin_digests: dict[str, str],
    *,
    activation_mode: str = "managed",
    layout_policy: str = "managed",
    configured_bar: str | None = None,
    previous_bar: dict[str, Any] | None = None,
) -> dict[str, Any]:
    selected_profile = suite.profile(profile)
    if activation_mode not in ("managed", "external"):
        raise CliError(f"invalid activation mode: {activation_mode}")
    if layout_policy not in ("managed", "preserved"):
        raise CliError(f"invalid layout policy: {layout_policy}")
    package = suite.package_metadata()
    result = {
        "schemaVersion": STATE_SCHEMA_VERSION,
        "suiteId": SUITE_ID,
        "suiteVersion": suite.version,
        "profile": profile,
        "activeBar": active_bar,
        "plugins": plugin_ids,
        "installOrigin": "package" if package is not None else "checkout",
        "payloadRoot": str(suite.root),
        "sourceRevision": revision,
        "payloadDigest": payload_digest,
        "pluginDigests": plugin_digests,
        "activation": {
            "activeBar": selected_profile.active_bar,
            "mode": activation_mode,
            "layoutPolicy": layout_policy,
            "configuredBar": configured_bar or selected_profile.active_bar,
            "layout": {
                region: list(selected_profile.layout[region])
                for region in ("left", "center", "right")
            },
            "enableServices": list(selected_profile.enable_services),
            "continuityPlugins": sorted(CONTINUITY_PLUGIN_IDS),
        },
        "updatedEpoch": int(time.time()),
    }
    if package is not None:
        result["packageName"] = package["packageName"]
        result["packageVersion"] = package["version"]
    else:
        result["sourceRoot"] = str(suite.root)
    if isinstance(previous_bar, dict):
        result["previousBar"] = copy.deepcopy(previous_bar)
    return result


def previous_bar_for_state(
    state: dict[str, Any], defaults: dict[str, Any]
) -> dict[str, Any]:
    """Return the pre-Shibumi bar or a Quattro default for older state files."""
    previous = state.get("previousBar")
    if isinstance(previous, dict):
        return copy.deepcopy(previous)
    fallback = defaults.get("bar")
    return copy.deepcopy(fallback) if isinstance(fallback, dict) else {}


def confirm(action: str, assume_yes: bool) -> None:
    if assume_yes:
        return
    if not sys.stdin.isatty() or not sys.stdout.isatty():
        raise CliError(f"refusing non-interactive {action}; pass --yes")
    answer = input(f"{action}? [y/N] ").strip().lower()
    if answer not in ("y", "yes"):
        raise CliError("cancelled")


def validate_sources(runtime: OmarchyRuntime, specs: list[PluginSpec]) -> None:
    for spec in specs:
        runtime.validate_plugin(spec.source)


def default_center_anchor(defaults: dict[str, Any]) -> str:
    bar = defaults.get("bar")
    return str(bar.get("centerAnchor") or "") if isinstance(bar, dict) else ""


def print_plan(label: str, specs: list[PluginSpec], paths: RuntimePaths) -> None:
    print(label)
    print(f"  plugin directory: {paths.plugin_dir}")
    print(f"  shell config:     {paths.config_file}")
    print(f"  plugins:          {len(specs)}")
    for spec in specs:
        print(f"    {spec.id}")


def install_picker_menu_extension(
    transaction: PluginTransaction,
    runtime: OmarchyRuntime,
    previous_state: dict[str, Any] | None = None,
) -> dict[str, Any]:
    raw = read_extension(transaction.paths.menu_extension_file)
    payload = install_picker_routing(raw).encode("utf-8")
    transaction.write_menu_extension(payload)
    runtime.refresh_menu()
    previous = (
        previous_state.get("menuExtension")
        if isinstance(previous_state, dict) else None
    )
    created_file = (
        bool(previous.get("createdFile"))
        if isinstance(previous, dict)
        else not transaction.menu_extension_existed
    )
    if not transaction.menu_extension_existed:
        created_file = True
    return {
        "schemaVersion": 1,
        "createdFile": created_file,
    }


def remove_picker_menu_extension(
    transaction: PluginTransaction,
    runtime: OmarchyRuntime,
    state: dict[str, Any],
) -> None:
    raw = read_extension(transaction.paths.menu_extension_file)
    if raw is None:
        return
    payload = remove_picker_routing(raw)
    metadata = state.get("menuExtension")
    created_file = bool(metadata.get("createdFile")) \
        if isinstance(metadata, dict) else False
    transaction.write_menu_extension(
        None
        if created_file and generated_extension_is_empty(payload)
        else payload.encode("utf-8")
    )
    runtime.refresh_menu()


def activation_drift(
    config: dict[str, Any],
    suite: Suite,
    profile_id: str,
    active_bar: str,
    managed_ids: set[str] | None = None,
) -> list[str]:
    profile = suite.profile(profile_id)
    bar = config.get("bar") if isinstance(config.get("bar"), dict) else {}
    layout = bar.get("layout") if isinstance(bar.get("layout"), dict) else {}
    layout_ids = {
        entry_id(entry)
        for region in ("left", "center", "right")
        for entry in (layout.get(region) if isinstance(layout.get(region), list) else [])
    }
    service_ids = {entry_id(entry) for entry in config.get("plugins", [])}
    drift: list[str] = []
    if str(bar.get("id") or "omarchy.bar") != active_bar:
        drift.append(f"active bar is {bar.get('id') or 'omarchy.bar'}")
    expected_widgets = set(
        profile.layout["left"] + profile.layout["center"] + profile.layout["right"]
    )
    expected_services = set(profile.enable_services)
    managed = set(suite.plugins) if managed_ids is None else managed_ids
    expected_widgets &= managed
    expected_services &= managed
    missing_widgets = expected_widgets - layout_ids
    if missing_widgets:
        drift.append(f"missing widgets: {', '.join(sorted(missing_widgets))}")
    unexpected_widgets = (layout_ids & managed) - expected_widgets
    if unexpected_widgets:
        drift.append(
            f"unexpected widgets: {', '.join(sorted(unexpected_widgets))}"
        )
    missing_services = expected_services - service_ids
    if missing_services:
        drift.append(f"missing services: {', '.join(sorted(missing_services))}")
    unexpected_services = (service_ids & managed) - expected_services
    if unexpected_services:
        drift.append(
            f"unexpected services: {', '.join(sorted(unexpected_services))}"
        )
    return drift


def runtime_enabled_plugin_ids(
    suite: Suite,
    profile_id: str,
) -> set[str]:
    """Return IDs whose enabled flag is meaningful in Quattro's plugin list."""
    profile = suite.profile(profile_id)
    enabled = {
        plugin_id
        for region in ("left", "center", "right")
        for plugin_id in profile.layout[region]
    }
    enabled.add(profile.active_bar)
    enabled.update(
        plugin_id
        for plugin_id in profile.enable_services
        if not suite.plugins[plugin_id].is_bar_widget
    )
    return enabled


def configured_bar_id(config: dict[str, Any]) -> str:
    bar = config.get("bar") if isinstance(config.get("bar"), dict) else {}
    return str(bar.get("id") or "omarchy.bar")


def external_activation(
    state: dict[str, Any],
    config: dict[str, Any],
) -> bool:
    """Return whether the suite explicitly delegates layout ownership."""
    activation = state.get("activation")
    return isinstance(activation, dict) \
        and activation.get("mode") == "external"


def external_runtime_enabled_plugin_ids(
    suite: Suite,
    config: dict[str, Any],
) -> set[str]:
    """Return suite roots enabled by an externally owned bar configuration."""
    bar = config.get("bar") if isinstance(config.get("bar"), dict) else {}
    layout = bar.get("layout") if isinstance(bar.get("layout"), dict) else {}
    enabled = {
        entry_id(entry)
        for region in ("left", "center", "right")
        for entry in (
            layout.get(region) if isinstance(layout.get(region), list) else []
        )
    }
    enabled.update(
        plugin_id
        for plugin_id in (
            entry_id(entry) for entry in config.get("plugins", [])
        )
        if plugin_id in suite.plugins
        and not suite.plugins[plugin_id].is_bar_widget
    )
    enabled &= set(suite.plugins)
    enabled.discard("hancore.shibumi.bar")
    return enabled


def external_activation_drift(
    config: dict[str, Any],
    suite: Suite,
    profile_id: str,
) -> list[str]:
    """Check dependencies without claiming ownership of host or widget layout."""
    services = {entry_id(entry) for entry in config.get("plugins", [])}
    missing = set(suite.profile(profile_id).enable_services) - services
    return (
        [f"missing services: {', '.join(sorted(missing))}"]
        if missing else []
    )


def preserve_external_bar(
    config: dict[str, Any],
    profile: Any,
) -> dict[str, Any]:
    """Keep the host and layout byte-semantics while enabling suite services."""
    return reconcile_profile_services(
        apply_identity_contract(config),
        profile,
    )


def command_install(
    args: argparse.Namespace,
    suite: Suite,
    paths: RuntimePaths,
    runtime: OmarchyRuntime,
) -> int:
    if args.no_activate != args.keep_layout:
        raise CliError(
            "--no-activate and --keep-layout must be used together"
        )
    if install_state_file(paths).exists():
        raise CliError("Shibumi is already suite-managed; use update")
    if legacy_install_state_file(paths).exists():
        raise CliError(
            "legacy QS Rise is installed; use 'shibumi-suite migrate'"
        )
    profile = suite.profile(args.profile)
    specs = suite.selected(profile.install)
    validate_sources(runtime, specs)
    current, _ = read_config(paths.config_file, paths.defaults_file)
    external = args.no_activate and args.keep_layout
    desired = remove_plugin_ids((
        preserve_external_bar(current, profile)
        if external
        else apply_identity_contract(
            apply_profile(current, profile, suite.plugins)
        )
    ), suite.retired_plugins)
    preflight_replacements(paths.plugin_dir, specs)
    preflight_removal_ids(paths.plugin_dir, suite.retired_plugins)
    label = (
        f"Install Shibumi profile {profile.id} with the current bar and layout"
        if external else f"Install Shibumi profile {profile.id}"
    )
    print_plan(label, specs, paths)
    if args.dry_run:
        print("Dry run complete; no files changed.")
        return 0
    confirm(
        "Install Shibumi and keep the current bar and layout"
        if external else "Install and activate Shibumi",
        args.yes,
    )

    revision = suite.revision()
    with PluginTransaction(
        paths, runtime, restart_on_reconcile=not external
    ) as transaction:
        transaction.preflight_targets(specs)
        payload_digest, plugin_digests = transaction.stage(
            specs, revision=revision, suite_version=suite.version
        )
        desired_state = make_install_state(
            suite,
            list(profile.install),
            profile.id,
            profile.active_bar,
            revision,
            payload_digest,
            plugin_digests,
            activation_mode="external" if external else "managed",
            layout_policy="preserved" if external else "managed",
            configured_bar=configured_bar_id(desired),
            previous_bar=current.get("bar"),
        )
        transaction.expose()
        transaction.stage_removal_ids(suite.retired_plugins)
        runtime.rescan()
        if not external:
            transaction.stop_shell()
        transaction.write_config(encode_config(desired))
        if external:
            runtime.reload_config()
        else:
            runtime.restart_shell()
            transaction.mark_shell_started()
        if PICKER_PLUGIN_ID in profile.install:
            desired_state["menuExtension"] = install_picker_menu_extension(
                transaction, runtime
            )
        if external:
            runtime.verify_update(
                set(profile.install),
                payload_digest,
                enabled_plugin_ids=external_runtime_enabled_plugin_ids(
                    suite, desired
                ),
            )
        else:
            runtime.verify_install(
                set(profile.install),
                profile.active_bar,
                payload_digest,
                enabled_plugin_ids=runtime_enabled_plugin_ids(
                    suite, profile.id
                ),
            )
        transaction.finish(desired_state, archive_previous=True)
    if external:
        print(
            f"Installed Shibumi ({len(specs)} plugins); "
            "kept the current bar and layout."
        )
    else:
        print(f"Installed and activated Shibumi ({len(specs)} plugins).")
    return 0


def command_migrate(
    args: argparse.Namespace,
    suite: Suite,
    paths: RuntimePaths,
    runtime: OmarchyRuntime,
) -> int:
    if install_state_file(paths).exists():
        raise CliError("Shibumi is already suite-managed; use update")

    legacy_state = load_legacy_install_state(paths, suite)
    profile_id = str(legacy_state.get("profile") or "default")
    profile = suite.profile(profile_id)
    specs = suite.selected(profile.install)
    old_plugin_ids = legacy_plugin_ids(suite)
    validate_sources(runtime, specs)
    current, _ = read_config(paths.config_file, paths.defaults_file)
    defaults, _ = read_config(paths.defaults_file, paths.defaults_file)
    # Migration changes the private namespace and applies the versioned Shibumi
    # identity contract. User layout order, widget options, third-party entries,
    # bar position, and all unrelated keys stay equivalent after JSON decoding.
    desired = reconcile_profile_services(
        apply_identity_contract(migrate_legacy_config(current)), profile
    )
    preflight_replacements(paths.plugin_dir, specs)
    preflight_legacy_removals(paths.plugin_dir, old_plugin_ids)

    print_plan("Migrate QS Rise to Shibumi", specs, paths)
    print(f"  legacy plugins:   {len(old_plugin_ids)}")
    if args.dry_run:
        print("Dry run complete; no files changed.")
        return 0
    confirm("Migrate QS Rise to Shibumi", args.yes)

    revision = suite.revision()
    with PluginTransaction(
        paths, runtime, restart_on_reconcile=True
    ) as transaction:
        transaction.preflight_targets(specs)
        payload_digest, plugin_digests = transaction.stage(
            specs, revision=revision, suite_version=suite.version
        )
        previous_bar = previous_bar_for_state(legacy_state, defaults)
        current_bar = current.get("bar")
        if isinstance(current_bar, dict) and "transparent" in current_bar:
            previous_bar["transparent"] = copy.deepcopy(
                current_bar["transparent"]
            )
        else:
            previous_bar.pop("transparent", None)
        desired_state = make_install_state(
            suite,
            list(profile.install),
            profile.id,
            profile.active_bar,
            revision,
            payload_digest,
            plugin_digests,
            previous_bar=previous_bar,
        )
        desired_state["migratedFrom"] = {
            "suiteId": LEGACY_SUITE_ID,
            "suiteVersion": legacy_state.get("suiteVersion"),
            "sourceRevision": legacy_state.get("sourceRevision"),
            "payloadDigest": legacy_state.get("payloadDigest"),
            "migratedEpoch": int(time.time()),
        }

        transaction.expose()
        runtime.rescan()
        transaction.stop_shell()
        transaction.write_config(encode_config(desired))
        runtime.restart_shell()
        transaction.mark_shell_started()
        if PICKER_PLUGIN_ID in profile.install:
            desired_state["menuExtension"] = install_picker_menu_extension(
                transaction, runtime
            )
        runtime.verify_install(
            set(profile.install),
            profile.active_bar,
            payload_digest,
            enabled_plugin_ids=runtime_enabled_plugin_ids(
                suite, profile.id
            ),
        )
        transaction.stage_legacy_removal(old_plugin_ids)
        runtime.rescan()
        runtime.verify_uninstall(set(old_plugin_ids))
        transaction.finish(desired_state, archive_previous=True)

    old_state_dir = legacy_state_dir(paths)
    old_cache_dir = legacy_cache_dir(paths)
    if old_state_dir.is_dir():
        shutil.rmtree(old_state_dir)
    if old_cache_dir.is_dir():
        shutil.rmtree(old_cache_dir)
    print(
        "Migrated QS Rise to Shibumi; preserved user settings and applied "
        "the one-time Shibumi identity default."
    )
    return 0


def command_update(
    args: argparse.Namespace,
    suite: Suite,
    paths: RuntimePaths,
    runtime: OmarchyRuntime,
) -> int:
    state = load_install_state(paths, suite)
    refuse_downgrade(
        state, suite, allow=bool(getattr(args, "allow_downgrade", False))
    )
    profile_id = str(state.get("profile") or "default")
    profile = suite.profile(profile_id)
    plugin_ids = list(profile.install)
    specs = suite.selected(profile.install)
    validate_sources(runtime, specs)
    current, _ = read_config(paths.config_file, paths.defaults_file)
    defaults, _ = read_config(paths.defaults_file, paths.defaults_file)
    external = external_activation(state, current)
    retired_installed = set(state["plugins"]) & set(suite.retired_plugins)
    current_installed = set(state["plugins"]) - retired_installed
    drift = (
        external_activation_drift(current, suite, profile_id)
        if external
        else activation_drift(
            current,
            suite,
            profile_id,
            str(state.get("activeBar") or "hancore.shibumi.bar"),
            current_installed,
        )
    )
    if drift and not external:
        raise CliError(
            "Shibumi is installed but inactive; run 'shibumi-suite activate' "
            f"first ({'; '.join(drift)})"
        )
    desired = remove_plugin_ids((
        preserve_external_bar(current, profile)
        if external
        else reconcile_profile_services(
            reconcile_profile_additions(
                apply_identity_contract(current),
                profile,
                current_installed,
                suite.plugins,
            ),
            profile,
        )
    ), suite.retired_plugins)
    adoptable_plugin_ids = current_installed
    preflight_replacements(
        paths.plugin_dir, specs, adoptable_plugin_ids
    )
    preflight_removal_ids(paths.plugin_dir, retired_installed)
    print_plan("Update installed Shibumi plugins", specs, paths)
    if retired_installed:
        print("  retire:           " + ", ".join(sorted(retired_installed)))
    if args.dry_run:
        print("Dry run complete; no files changed.")
        return 0
    confirm("Update Shibumi", args.yes)

    revision = suite.revision()
    with PluginTransaction(
        paths, runtime, restart_on_reconcile=not external
    ) as transaction:
        transaction.preflight_targets(specs, adoptable_plugin_ids)
        payload_digest, plugin_digests = transaction.stage(
            specs, revision=revision, suite_version=suite.version
        )
        desired_state = make_install_state(
            suite,
            plugin_ids,
            profile_id,
            str(state.get("activeBar") or "hancore.shibumi.bar"),
            revision,
            payload_digest,
            plugin_digests,
            activation_mode="external" if external else "managed",
            layout_policy="preserved" if external else "managed",
            configured_bar=configured_bar_id(desired),
            previous_bar=previous_bar_for_state(state, defaults),
        )
        # Hidden staging paths are ignored by Quattro's plugin watcher. Check
        # the authoritative lock service only after staging is complete and
        # immediately before the first live plugin directory is renamed.
        runtime.require_session_unlocked("Shibumi update")
        # Managed updates replace every live plugin root. Drain the shell before
        # publishing them so Quattro cannot begin a hot reload while the
        # subsequent restart is deregistering and recreating IPC handlers.
        if not external:
            transaction.stop_shell()
        transaction.expose()
        transaction.stage_removal_ids(retired_installed)
        transaction.write_config(encode_config(desired))
        if external:
            runtime.rescan()
            runtime.reload_config()
            runtime.reload_payload()
        else:
            runtime.restart_shell()
            transaction.mark_shell_started()
        if PICKER_PLUGIN_ID in plugin_ids:
            desired_state["menuExtension"] = install_picker_menu_extension(
                transaction, runtime, state
            )
        runtime.verify_update(
            set(plugin_ids),
            payload_digest,
            enabled_plugin_ids=(
                external_runtime_enabled_plugin_ids(suite, desired)
                if external
                else runtime_enabled_plugin_ids(suite, profile_id)
            ),
        )
        transaction.finish(desired_state, archive_previous=True)
    print(f"Updated Shibumi ({len(specs)} plugins).")
    return 0


def command_repair(
    args: argparse.Namespace,
    suite: Suite,
    paths: RuntimePaths,
    runtime: OmarchyRuntime,
) -> int:
    """Restore the complete suite payload and its active profile atomically."""
    state = load_install_state(paths, suite)
    refuse_downgrade(
        state, suite, allow=bool(getattr(args, "allow_downgrade", False))
    )
    profile_id = str(state.get("profile") or "default")
    profile = suite.profile(profile_id)
    plugin_ids = list(profile.install)
    specs = suite.selected(profile.install)
    validate_sources(runtime, specs)
    current, _ = read_config(paths.config_file, paths.defaults_file)
    defaults, _ = read_config(paths.defaults_file, paths.defaults_file)
    external = external_activation(state, current)
    retired_installed = set(state["plugins"]) & set(suite.retired_plugins)
    current_installed = set(state["plugins"]) - retired_installed
    desired = remove_plugin_ids((
        preserve_external_bar(current, profile)
        if external
        else apply_identity_contract(
            apply_profile(current, profile, suite.plugins)
        )
    ), suite.retired_plugins)
    adoptable_plugin_ids = current_installed
    preflight_replacements(
        paths.plugin_dir, specs, adoptable_plugin_ids
    )
    preflight_removal_ids(paths.plugin_dir, retired_installed)
    print_plan(
        f"Repair Shibumi profile {profile.id}",
        specs,
        paths,
    )
    if args.dry_run:
        print("Dry run complete; no files changed.")
        return 0
    confirm(
        "Repair the complete Shibumi payload"
        + (
            " while keeping the current bar and layout"
            if external else " and restore its managed layout"
        ),
        args.yes,
    )

    revision = suite.revision()
    with PluginTransaction(
        paths, runtime, restart_on_reconcile=not external
    ) as transaction:
        transaction.preflight_targets(specs, adoptable_plugin_ids)
        payload_digest, plugin_digests = transaction.stage(
            specs, revision=revision, suite_version=suite.version
        )
        desired_state = make_install_state(
            suite,
            plugin_ids,
            profile_id,
            profile.active_bar,
            revision,
            payload_digest,
            plugin_digests,
            activation_mode="external" if external else "managed",
            layout_policy="preserved" if external else "managed",
            configured_bar=configured_bar_id(desired),
            previous_bar=previous_bar_for_state(state, defaults),
        )
        if not external:
            transaction.stop_shell()
        transaction.expose()
        transaction.stage_removal_ids(retired_installed)
        transaction.write_config(encode_config(desired))
        if external:
            runtime.rescan()
            runtime.reload_config()
            runtime.reload_payload()
        else:
            runtime.restart_shell()
            transaction.mark_shell_started()
        if PICKER_PLUGIN_ID in plugin_ids:
            desired_state["menuExtension"] = install_picker_menu_extension(
                transaction, runtime, state
            )
        if external:
            runtime.verify_update(
                set(plugin_ids),
                payload_digest,
                enabled_plugin_ids=external_runtime_enabled_plugin_ids(
                    suite, desired
                ),
            )
        else:
            runtime.verify_install(
                set(plugin_ids),
                profile.active_bar,
                payload_digest,
                enabled_plugin_ids=runtime_enabled_plugin_ids(
                    suite, profile_id
                ),
            )
        transaction.finish(desired_state, archive_previous=True)
    print(
        f"Repaired Shibumi ({len(specs)} plugins)"
        + (
            "; kept the current bar and layout."
            if external else " and restored its managed layout."
        )
    )
    return 0


def command_activate(
    args: argparse.Namespace,
    suite: Suite,
    paths: RuntimePaths,
    runtime: OmarchyRuntime,
) -> int:
    state = load_install_state(paths, suite)
    retired_installed = set(state["plugins"]) & set(suite.retired_plugins)
    if retired_installed:
        raise CliError(
            "installed Shibumi contains retired plugins; run "
            "'shibumi-suite update' before activation"
        )
    profile_id = str(state.get("profile") or "default")
    profile = suite.profile(profile_id)
    current, _ = read_config(paths.config_file, paths.defaults_file)
    desired = apply_identity_contract(
        apply_profile(current, profile, suite.plugins)
    )
    specs = suite.selected(profile.install)
    preflight_replacements(paths.plugin_dir, specs)
    print_plan(f"Activate Shibumi profile {profile.id}", specs, paths)
    if args.dry_run:
        print("Dry run complete; no files changed.")
        return 0
    confirm("Activate Shibumi and restore its configured layout", args.yes)

    with PluginTransaction(
        paths, runtime, restart_on_reconcile=True
    ) as transaction:
        transaction.stop_shell()
        transaction.write_config(encode_config(desired))
        runtime.restart_shell()
        transaction.mark_shell_started()
        runtime.verify_install(
            set(profile.install),
            str(state.get("activeBar") or profile.active_bar),
            str(state["payloadDigest"]),
            enabled_plugin_ids=runtime_enabled_plugin_ids(
                suite, profile_id
            ),
        )
        activated_state = copy.deepcopy(state)
        activation = activated_state.setdefault("activation", {})
        activation["mode"] = "managed"
        activation["layoutPolicy"] = "managed"
        activation["configuredBar"] = profile.active_bar
        activated_state["updatedEpoch"] = int(time.time())
        transaction.finish(activated_state, archive_previous=False)
    print("Activated Shibumi and restored its configured layout.")
    return 0


def command_deactivate(
    args: argparse.Namespace,
    suite: Suite,
    paths: RuntimePaths,
    runtime: OmarchyRuntime,
) -> int:
    state = load_install_state(paths, suite)
    current, _ = read_config(paths.config_file, paths.defaults_file)
    defaults, _ = read_config(paths.defaults_file, paths.defaults_file)
    active_bar = str(state.get("activeBar") or "hancore.shibumi.bar")
    profile_id = str(state.get("profile") or "default")
    profile = suite.profile(profile_id)
    if args.keep_layout:
        desired = remove_plugin_ids(select_omarchy_image_picker(
            preserve_external_bar(current, profile)
        ), suite.retired_plugins)
        bar = desired.get("bar")
        if isinstance(bar, dict) and str(bar.get("id") or "") == active_bar:
            bar.pop("id", None)
        desired_state = copy.deepcopy(state)
        activation = desired_state.setdefault("activation", {})
        activation["mode"] = "external"
        activation["layoutPolicy"] = "preserved"
        activation["configuredBar"] = configured_bar_id(desired)
        desired_state["updatedEpoch"] = int(time.time())
    else:
        desired = remove_plugin_ids(select_omarchy_image_picker(
            remove_suite(
                current,
                suite.plugins,
                active_bar,
                default_center_anchor(defaults),
                True,
                CONTINUITY_PLUGIN_IDS,
                previous_bar_for_state(state, defaults),
            )
        ), suite.retired_plugins)
        desired_state = state
    print_plan(
        (
            "Use the stock Omarchy bar with the current Shibumi widget layout"
            if args.keep_layout
            else "Deactivate Shibumi and restore the stock Omarchy bar"
        ),
        suite.selected(tuple(
            plugin_id
            for plugin_id in state["plugins"]
            if plugin_id in suite.plugins
        )),
        paths,
    )
    if args.dry_run:
        print("Dry run complete; no files changed.")
        return 0
    confirm(
        (
            "Switch to the stock Omarchy bar and keep the current widget layout"
            if args.keep_layout
            else "Deactivate Shibumi while retaining its plugins and settings"
        ),
        args.yes,
    )

    with PluginTransaction(
        paths, runtime, restart_on_reconcile=True
    ) as transaction:
        transaction.stop_shell()
        transaction.write_config(encode_config(desired))
        runtime.restart_shell()
        transaction.mark_shell_started()
        if args.keep_layout:
            runtime.verify_update(
                set(state["plugins"]),
                str(state["payloadDigest"]),
                enabled_plugin_ids=external_runtime_enabled_plugin_ids(
                    suite, desired
                ),
            )
        else:
            runtime.verify_deactivation(
                set(state["plugins"]),
                active_bar,
                allowed_enabled=CONTINUITY_PLUGIN_IDS,
            )
        transaction.finish(desired_state, archive_previous=False)
    print(
        (
            "Switched to the stock Omarchy bar; kept Shibumi widgets, "
            "plugins, and settings."
            if args.keep_layout
            else "Deactivated Shibumi and restored the stock Omarchy bar; "
            "plugins and settings were retained."
        )
    )
    return 0


def command_uninstall(
    args: argparse.Namespace,
    suite: Suite,
    paths: RuntimePaths,
    runtime: OmarchyRuntime,
) -> int:
    state = load_install_state(paths, suite)
    plugin_ids = list(dict.fromkeys(state["plugins"]))
    current_plugin_ids = [
        plugin_id for plugin_id in plugin_ids if plugin_id in suite.plugins
    ]
    retired_plugin_ids = [
        plugin_id for plugin_id in plugin_ids if plugin_id in suite.retired_plugins
    ]
    specs = suite.selected(tuple(current_plugin_ids))
    current, _ = read_config(paths.config_file, paths.defaults_file)
    defaults, _ = read_config(paths.defaults_file, paths.defaults_file)
    desired = remove_plugin_ids(select_omarchy_image_picker(
        remove_suite(
            current,
            suite.plugins,
            str(state.get("activeBar") or "hancore.shibumi.bar"),
            default_center_anchor(defaults),
            args.keep_settings,
            restore_bar=(
                previous_bar_for_state(state, defaults)
                if str(state.get("activation", {}).get("mode") or "managed")
                == "managed"
                else None
            ),
        )
    ), retired_plugin_ids)
    preflight_removals(paths.plugin_dir, specs)
    preflight_removal_ids(paths.plugin_dir, retired_plugin_ids)
    print_plan("Uninstall Shibumi", specs, paths)
    if args.dry_run:
        print("Dry run complete; no files changed.")
        return 0
    confirm("Uninstall Shibumi and restore the stock bar", args.yes)

    with PluginTransaction(
        paths, runtime, restart_on_reconcile=True
    ) as transaction:
        remove_picker_menu_extension(transaction, runtime, state)
        transaction.stop_shell()
        transaction.write_config(encode_config(desired))
        runtime.restart_shell()
        transaction.mark_shell_started()
        transaction.stage_removal(specs)
        transaction.stage_removal_ids(retired_plugin_ids)
        runtime.rescan()
        runtime.verify_uninstall(set(plugin_ids))
        transaction.finish(None, archive_previous=False)

    if paths.state_dir.is_dir():
        shutil.rmtree(paths.state_dir)
    if paths.cache_dir.is_dir():
        shutil.rmtree(paths.cache_dir)
    print("Uninstalled Shibumi and restored the stock Omarchy bar.")
    return 0


def command_status(suite: Suite, paths: RuntimePaths) -> int:
    state_path = install_state_file(paths)
    state: dict[str, Any] | None = None
    if state_path.is_file():
        try:
            state = load_install_state(paths, suite)
        except CliError as error:
            print(f"State: invalid ({error})")
            return 1
    package = suite.package_metadata()
    print(
        "Suite payload: "
        f"{suite.version} ({'package ' + package['packageName'] if package else 'source checkout'}; "
        f"{suite.revision()})"
    )
    if state is None:
        if legacy_install_state_file(paths).exists():
            print("Install state: legacy QS Rise detected; run migrate")
            return 1
        print("Install state: not installed")
        return 0
    print(
        "Install state: "
        f"{state.get('suiteVersion')} ({state.get('sourceRevision')})"
    )
    if state.get("installOrigin") == "package":
        print(
            "Staged from package: "
            f"{state.get('packageName')} {state.get('packageVersion')}"
        )
    else:
        print(f"Staged from checkout: {state.get('sourceRoot', 'unknown')}")
    print(f"Profile: {state.get('profile')}")
    missing: list[str] = []
    unmanaged: list[str] = []
    modified: list[str] = []
    pending_retirement: list[str] = []
    for plugin_id in state["plugins"]:
        target = paths.plugin_dir / plugin_id
        if plugin_id in suite.retired_plugins:
            pending_retirement.append(plugin_id)
            if target.exists() and not is_managed_target(target, plugin_id):
                unmanaged.append(plugin_id)
            elif target.exists():
                try:
                    actual_digest = plugin_payload_digest(target)
                except ContractError:
                    modified.append(plugin_id)
                else:
                    if actual_digest != state["pluginDigests"][plugin_id]:
                        modified.append(plugin_id)
            continue
        if not target.exists():
            missing.append(plugin_id)
        elif not is_managed_target(target, plugin_id):
            unmanaged.append(plugin_id)
        else:
            try:
                actual_digest = suite.plugins[plugin_id].payload_digest(target)
            except ContractError:
                modified.append(plugin_id)
            else:
                if actual_digest != state["pluginDigests"][plugin_id]:
                    modified.append(plugin_id)
    print(f"Managed plugins: {len(state['plugins']) - len(missing) - len(unmanaged)}")
    if missing:
        print(f"Missing: {', '.join(missing)}")
    if unmanaged:
        print(f"Ownership mismatch: {', '.join(unmanaged)}")
    if modified:
        print(f"Locally modified: {', '.join(modified)}")
    if pending_retirement:
        print(f"Pending retirement: {', '.join(pending_retirement)}")
    try:
        config, _ = read_config(paths.config_file, paths.defaults_file)
        bar = config.get("bar") if isinstance(config.get("bar"), dict) else {}
        print(f"Configured bar: {bar.get('id', 'omarchy.bar')}")
        profile_id = str(state.get("profile") or "default")
        drift = (
            external_activation_drift(config, suite, profile_id)
            if external_activation(state, config)
            else activation_drift(
                config,
                suite,
                profile_id,
                str(state.get("activeBar") or "hancore.shibumi.bar"),
            )
        )
        if drift:
            print(f"Configuration drift: {'; '.join(drift)}")
    except ConfigError as error:
        print(f"Config: invalid ({error})")
        print("Repair with: shibumi-suite repair")
        return 1
    unhealthy = bool(
        missing or unmanaged or modified or pending_retirement or drift
    )
    if unhealthy:
        print("Repair with: shibumi-suite repair")
    return 1 if unhealthy else 0


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(
        prog="shibumi-suite",
        description="Install and update the Shibumi Omarchy plugin suite transactionally.",
    )
    subparsers = result.add_subparsers(dest="command", required=True)

    install = subparsers.add_parser("install", help="install and activate Shibumi")
    install.add_argument("--profile", default="default")
    install.add_argument(
        "--no-activate",
        action="store_true",
        help="keep the currently configured bar",
    )
    install.add_argument(
        "--keep-layout",
        action="store_true",
        help="preserve the current bar widget layout (requires --no-activate)",
    )
    install.add_argument("--dry-run", action="store_true")
    install.add_argument("--yes", "-y", action="store_true")

    migrate = subparsers.add_parser(
        "migrate", help="migrate a suite-managed QS Rise install to Shibumi"
    )
    migrate.add_argument("--dry-run", action="store_true")
    migrate.add_argument("--yes", "-y", action="store_true")

    update = subparsers.add_parser("update", help="update the installed plugin set")
    update.add_argument("--dry-run", action="store_true")
    update.add_argument("--yes", "-y", action="store_true")
    update.add_argument(
        "--allow-downgrade",
        action="store_true",
        help="stage an intentionally installed older package payload",
    )

    repair = subparsers.add_parser(
        "repair",
        help="restore the complete suite payload and activate its managed layout",
    )
    repair.add_argument("--dry-run", action="store_true")
    repair.add_argument("--yes", "-y", action="store_true")
    repair.add_argument(
        "--allow-downgrade",
        action="store_true",
        help="repair from an intentionally installed older package payload",
    )

    activate = subparsers.add_parser(
        "activate", help="activate Shibumi and restore its managed layout"
    )
    activate.add_argument("--dry-run", action="store_true")
    activate.add_argument("--yes", "-y", action="store_true")

    deactivate = subparsers.add_parser(
        "deactivate",
        help="restore the stock Omarchy bar while retaining Shibumi",
    )
    deactivate.add_argument("--dry-run", action="store_true")
    deactivate.add_argument("--yes", "-y", action="store_true")
    deactivate.add_argument(
        "--keep-layout",
        action="store_true",
        help="keep Shibumi widgets in the stock bar layout",
    )

    uninstall = subparsers.add_parser("uninstall", help="remove Shibumi")
    uninstall.add_argument("--keep-settings", action="store_true")
    uninstall.add_argument("--dry-run", action="store_true")
    uninstall.add_argument("--yes", "-y", action="store_true")

    subparsers.add_parser("status", help="show installed suite state")
    return result


def main(argv: list[str] | None = None) -> int:
    args = parser().parse_args(argv)
    try:
        suite = Suite.load(repository_root())
        paths = RuntimePaths.from_environment()
        paths.validate()
        runtime = OmarchyRuntime(paths.omarchy_root)
        if args.command == "status":
            return command_status(suite, paths)

        with SuiteLock(paths.lock_file):
            recovered = recover_transactions(paths, runtime)
            if recovered:
                print(f"Recovered {recovered} interrupted Shibumi transaction(s).")
            if args.command == "install":
                return command_install(args, suite, paths, runtime)
            if args.command == "migrate":
                return command_migrate(args, suite, paths, runtime)
            if args.command == "update":
                return command_update(args, suite, paths, runtime)
            if args.command == "repair":
                return command_repair(args, suite, paths, runtime)
            if args.command == "activate":
                return command_activate(args, suite, paths, runtime)
            if args.command == "deactivate":
                return command_deactivate(args, suite, paths, runtime)
            if args.command == "uninstall":
                return command_uninstall(args, suite, paths, runtime)
        raise CliError(f"unsupported command: {args.command}")
    except (
        CliError,
        ConfigError,
        ContractError,
        RuntimeFailure,
        TransactionError,
    ) as error:
        print(f"shibumi-suite: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
