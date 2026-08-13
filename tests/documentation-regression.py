#!/usr/bin/env python3

from pathlib import Path
import json
import re
import shutil
import subprocess
import sys
import tempfile


REPO_ROOT = Path(__file__).resolve().parents[1]
CURRENT_DOCUMENTS = (
    "README.md",
    "CONTRIBUTING.md",
    "DESIGN.md",
    "docs/README.md",
    "docs/getting-started.md",
    "docs/install.md",
    "docs/plugin-compatibility.md",
    "docs/configuration.md",
    "docs/release-readiness.md",
    "docs/architecture/overview.md",
    "docs/plugins/README.md",
    "docs/screenshots/README.md",
    "docs/development/setup.md",
    "docs/development/testing.md",
    "docs/development/troubleshooting.md",
    "docs/development/release.md",
)
PLUGIN_COUNT_DOCUMENTS = (
    "ARCHITECTURE.md",
    "docs/install.md",
    "docs/architecture/overview.md",
    "docs/development/setup.md",
)
BLUETOOTH_OWNERSHIP_SURFACES = (
    "ARCHITECTURE.md",
    "docs/phase2-validation.md",
    "docs/phase2-ownership-map.md",
    "docs/plugin-suite-inventory.md",
    "docs/v1-widget-parity-audit.md",
    "tests/fixtures/ControlCenterTestPanel.qml",
)
LINK_PATTERN = re.compile(r"(?<!!)\[[^\]]+\]\(([^)]+)\)")


def fail(message: str) -> None:
    print(f"documentation regression failed: {message}", file=sys.stderr)
    raise SystemExit(1)


def local_target(source: Path, raw_target: str) -> Path | None:
    target = raw_target.strip()
    if not target or target.startswith(("#", "http://", "https://", "mailto:")):
        return None
    target = target.split("#", 1)[0]
    return (source.parent / target).resolve()


def verify_source_install_block(block: str) -> None:
    script = block.removeprefix("```bash\n").removesuffix("\n```") + "\n"
    if "\\\n" in script or "&&" in script:
        fail("README source install must not depend on continued command lines")

    syntax = subprocess.run(
        ["bash", "-n"],
        input=script,
        text=True,
        capture_output=True,
        check=False,
    )
    if syntax.returncode != 0:
        fail(f"README source install is invalid Bash: {syntax.stderr.strip()}")
    fish = shutil.which("fish")
    if fish:
        fish_syntax = subprocess.run(
            [fish, "-n"],
            input=script,
            text=True,
            capture_output=True,
            check=False,
        )
        if fish_syntax.returncode != 0:
            fail(
                "README source install is invalid Fish: "
                f"{fish_syntax.stderr.strip()}"
            )

    with tempfile.TemporaryDirectory(prefix="shibumi-doc-install.") as raw_root:
        root = Path(raw_root)
        bin_dir = root / "bin"
        bin_dir.mkdir()
        log_path = root / "commands.log"
        sudo_stub = bin_dir / "sudo"
        sudo_stub.write_text(
            '#!/usr/bin/env bash\nprintf "sudo:%s\\n" "$*" >> "$SHIBUMI_DOC_LOG"\n',
            encoding="utf-8",
        )
        sudo_stub.chmod(0o755)
        git_stub = bin_dir / "git"
        git_stub.write_text(
            "#!/usr/bin/env bash\n"
            'printf "git:%s\\n" "$*" >> "$SHIBUMI_DOC_LOG"\n'
            '[[ $1 == clone ]] || exit 2\n'
            'mkdir -p Shibumi-Shell/scripts\n'
            'printf \'#!/usr/bin/env bash\\n\' > Shibumi-Shell/scripts/shibumi-suite\n'
            'printf \'printf "suite:%%s\\\\n" "$*" >> "$SHIBUMI_DOC_LOG"\\n\' '
            ">> Shibumi-Shell/scripts/shibumi-suite\n"
            'chmod +x Shibumi-Shell/scripts/shibumi-suite\n',
            encoding="utf-8",
        )
        git_stub.chmod(0o755)
        environment = {
            "PATH": f"{bin_dir}:/usr/bin:/bin",
            "SHIBUMI_DOC_LOG": str(log_path),
        }
        execution = subprocess.run(
            ["bash"],
            cwd=root,
            env=environment,
            input=script,
            text=True,
            capture_output=True,
            check=False,
        )
        if execution.returncode != 0:
            fail(
                "README source install cannot run as pasted: "
                f"{execution.stderr.strip()}"
            )
        calls = log_path.read_text(encoding="utf-8")
        if "sudo:pacman -S --needed" not in calls:
            fail("README source install did not invoke Pacman through sudo")
        clone_call = "git:clone https://github.com/HANCORE-linux/Shibumi-Shell.git"
        if clone_call not in calls:
            fail("README source install did not invoke the documented clone")
        if "suite:install --yes" not in calls:
            fail("README source install did not enter the checkout and install")


def main() -> None:
    current_content: dict[str, str] = {}
    for relative in CURRENT_DOCUMENTS:
        source = REPO_ROOT / relative
        if not source.is_file():
            fail(f"missing current document: {relative}")
        content = source.read_text(encoding="utf-8")
        current_content[relative] = content
        for raw_target in LINK_PATTERN.findall(content):
            target = local_target(source, raw_target)
            if target is not None and not target.exists():
                fail(f"broken local link in {relative}: {raw_target}")

    readme = (REPO_ROOT / "README.md").read_text(encoding="utf-8")
    private_project_root = "/home/" + "hancore/Projects/"
    if private_project_root + "Quickshell-Dots" in readme:
        fail("README exposes the internal QS Rise worktree path")

    private_baseline_paths = (
        private_project_root + "Quickshell-Dots",
        private_project_root + "omarchy-updates-pr",
    )
    for relative, content in current_content.items():
        if any(path in content for path in private_baseline_paths):
            fail(f"current documentation exposes a private baseline path: {relative}")

    testing_guide = current_content["docs/development/testing.md"]
    for marker in (
        "contracts/baselines/omarchy-installed-package-b99fd91.json",
        "contracts/baselines/omarchy-installed-source-parity-b99fd91.json",
        "contracts/baselines/omarchy-forward-compat-d6b21f80.json",
        "./tests/omarchy-installed-package-contract-regression.sh",
        "./tests/omarchy-installed-source-parity-contract-regression.sh",
        "./tests/omarchy-forward-compat-contract-regression.sh",
        "contracts/baselines/quickshell-dots-d0896fc-v2-deec8103.json",
        "Shibumi complete contract regression passed",
    ):
        if marker not in testing_guide:
            fail(f"testing guide does not explain the baseline contract: {marker}")

    readme_images = [
        match.group(1) or match.group(2)
        for match in re.finditer(
            r"!\[[^\]]*\]\(([^)]+)\)|<img\s+[^>]*src=\"([^\"]+)\"",
            readme,
        )
    ]
    if not 2 <= len(readme_images) <= 5:
        fail("README landing page must contain between two and five images")
    for raw_target in readme_images:
        target = local_target(REPO_ROOT / "README.md", raw_target)
        if target is not None and not target.is_file():
            fail(f"broken README image: {raw_target}")

    bash_blocks = re.findall(r"```bash\n.*?\n```", readme, flags=re.DOTALL)
    if len(bash_blocks) != 4:
        fail(
            "README landing page must contain package/source install and "
            "package/source uninstall Bash blocks"
        )
    package_install_command = (
        "omarchy pkg aur add shibumi-shell && shibumi-shell install --yes"
    )
    source_install_markers = (
        "sudo pacman -S --needed",
        "ttf-material-symbols-variable",
        "git clone https://github.com/HANCORE-linux/Shibumi-Shell.git",
        "cd Shibumi-Shell",
        "./scripts/shibumi-suite install --yes",
    )
    if sum(package_install_command in block for block in bash_blocks) != 1:
        fail("README landing page is missing the package install command")
    source_install_blocks = [
        block
        for block in bash_blocks
        if all(marker in block for marker in source_install_markers)
    ]
    if len(source_install_blocks) != 1:
        fail("README landing page is missing the source install command")
    verify_source_install_block(source_install_blocks[0])
    install_guide = (REPO_ROOT / "docs/install.md").read_text(encoding="utf-8")
    suite_contract = json.loads(
        (REPO_ROOT / "contracts/plugin-suite-v1.json").read_text(encoding="utf-8")
    )
    plugin_count = len(suite_contract["plugins"])
    count_pattern = re.compile(
        rf"(?:\b{plugin_count}\b[^\n]{{0,80}}\b(?:plugins?|roots?)\b|"
        rf"\b(?:plugins?|roots?)\b[^\n]{{0,80}}\b{plugin_count}\b)",
        flags=re.IGNORECASE,
    )
    stale_pattern = re.compile(
        r"(?:\b25\b[^\n]{0,80}\b(?:plugins?|roots?)\b|"
        r"\b(?:plugins?|roots?)\b[^\n]{0,80}\b25\b)",
        flags=re.IGNORECASE,
    )
    for relative in PLUGIN_COUNT_DOCUMENTS:
        content = (REPO_ROOT / relative).read_text(encoding="utf-8")
        if stale_pattern.search(content):
            fail(f"current documentation reports the retired root count: {relative}")
        if not count_pattern.search(content):
            fail(
                "current documentation does not report the authoritative "
                f"{plugin_count}-root count: {relative}"
            )
    guide_blocks = re.findall(
        r"```bash\n.*?\n```", install_guide, flags=re.DOTALL
    )
    guide_source_blocks = [
        block
        for block in guide_blocks
        if all(marker in block for marker in source_install_markers)
    ]
    if guide_source_blocks != source_install_blocks:
        fail("README and install guide source commands have drifted")
    uninstall_command = (
        "shibumi-shell uninstall --yes && omarchy pkg drop shibumi-shell"
    )
    if sum(uninstall_command in block for block in bash_blocks) != 1:
        fail("README landing page is missing the package uninstall command")
    source_uninstall_command = "./scripts/shibumi-suite uninstall --yes"
    if sum(source_uninstall_command in block for block in bash_blocks) != 1:
        fail("README landing page is missing the source uninstall command")
    if "docs/plugin-compatibility.md" not in readme:
        fail("README landing page is missing the plugin compatibility guide")

    bluetooth_docs = "\n".join(
        " ".join((REPO_ROOT / relative).read_text(encoding="utf-8").split())
        for relative in BLUETOOTH_OWNERSHIP_SURFACES
    ).lower()
    for stale_claim in (
        "one hidden registered `omarchy.bluetooth` component",
        "complete official `omarchy.bluetooth` backend",
        "official `omarchy.bluetooth` |",
        "one shared official backend with local v1-style widgets",
        "the adapter has only two bounded action timers",
        "shibumi bluetooth presentation over omarchy's bluez and audio owner",
        "presentation and service facade have no bluetooth/pipewire import, "
        "process, timer, or file watcher",
    ):
        if stale_claim in bluetooth_docs:
            fail(f"stale Bluetooth ownership claim: {stale_claim}")
    guard_timer_claim = (
        "at most one temporary 30-second retry/expiry timer per native adapter"
    )
    if guard_timer_claim not in bluetooth_docs:
        fail("Bluetooth teardown guard timer is missing from the timer inventory")

    bluetooth_evidence = (
        REPO_ROOT / "docs/audits/evidence/bluetooth-final-2026-08-06.md"
    ).read_text(encoding="utf-8")
    for host_bound_command in (
        "Command: `OMARCHY_PATH=/usr/share/omarchy "
        "./tests/bluetooth-plugin-regression.sh`",
        "Command: `OMARCHY_PATH=/usr/share/omarchy "
        "./tests/contract-regression.sh`",
    ):
        if host_bound_command not in bluetooth_evidence:
            fail(f"Bluetooth evidence lacks installed-host binding: {host_bound_command}")

    print("documentation regression passed")


if __name__ == "__main__":
    main()
