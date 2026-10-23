#!/usr/bin/env python3
"""DPR1/full renderer lifecycle series; stub stock, no CLI/persistence/desktop acceptance."""
import argparse
import json
from pathlib import Path
import re
import runpy
import shutil
import sys
import tempfile
sys.dont_write_bytecode = True
from lib.isolated_process import run_bounded
from lib.source_snapshot import snapshot, fingerprint, materialize
ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--native-shell", required=True, type=Path)
    args = parser.parse_args()
    native = runpy.run_path(str(ROOT / "tests/native-runtime-regression.py"))["admitted_native"](args.native_shell)
    steps = [(style, edge) for edge in ("top", "bottom")
             for variant in ("shibumi", "full", "fit", "dock", "notch")
             for style in (variant, "omarchy", variant)]
    steps += [("shibumi", "top"), ("omarchy", "top"), ("full", "top"),
              ("omarchy", "bottom"), ("shibumi", "bottom"), ("notch", "bottom"), ("notch", "top")]
    with tempfile.TemporaryDirectory(prefix="bs-", dir="/tmp") as directory:
        base = Path(directory)
        for folder in ("home", "cache", "run", "bin", "native-runtime"):
            (base / folder).mkdir(mode=0o700)
        identities = {}
        for plugin in sorted(ROOT.glob("hancore.shibumi.*")):
            source = snapshot(plugin)
            identities[plugin.name] = fingerprint(source)
            materialize(source, base / plugin.name)
        for module in ("Commons", "Ui"):
            materialize({p[len(module)+1:]:v for p,v in native.items() if p.startswith(module+"/")}, base / module)
        fixtures = ROOT / "tests/fixtures"
        for name in ("AudioTestPanel.qml", "MonitorTestPanel.qml", "StatusTestWidget.qml", "native-runtime/StockBar.qml"):
            shutil.copyfile(fixtures / name, base / name)
        shutil.copyfile(fixtures / "BarSwitchHost.qml", base / "shell.qml")
        (base / "hancore.shibumi.bar/core/BarPanel.qml").write_text('''import QtQuick
import QtQuick.Window
import "../styles/shibumi" as Styles
Item {
  id: panel
  required property var bar
  property var screen: null
  Window {visible:panel.bar.hostReady && panel.bar.styleReady; width:1800; height:100
    Loader {active:panel.bar.hostReady && panel.bar.styleReady; width:1800; height:panel.bar.barSize
      sourceComponent:Component {Styles.BarSurface {bar:panel.bar;screenName:"fixture-output"}}}}
}
''')
        (base / "census.py").write_text('''import json,os
from pathlib import Path
rows=[]
for p in Path('/proc').glob('[0-9]*'):
    try:
        if (p/'exe').resolve().name == 'quickshell': rows.append(int(p.name))
    except OSError: pass
print(json.dumps(rows));raise SystemExit(0 if len(rows)==1 else 1)
''')
        for name, text in {"hyprctl":'{"int":10,"custom":"10 10 10 10"}', "fc-match":"monospace", "bash":"no"}.items():
            path = base / "bin" / name
            path.write_text("#!/bin/sh\nprintf '%s\\n' '"+text+"'\n"); path.chmod(0o700)
        env = {"HOME":"/fixture/home", "XDG_CONFIG_HOME":"/fixture/home/.config", "XDG_CACHE_HOME":"/fixture/cache",
               "XDG_DATA_HOME":"/fixture/home/data", "XDG_DATA_DIRS":"/fixture/home/data", "XDG_STATE_HOME":"/fixture/home/state",
               "XDG_RUNTIME_DIR":"/fixture/run", "PATH":"/fixture/bin", "QT_QPA_PLATFORM":"offscreen", "QT_QUICK_BACKEND":"software",
               "QML_DISABLE_DISK_CACHE":"1", "QT_SCALE_FACTOR":"1", "QT_FORCE_STDERR_LOGGING":"1", "LANG":"C.UTF-8",
               "DBUS_SESSION_BUS_ADDRESS":"unix:path=/fixture/no-session", "DBUS_SYSTEM_BUS_ADDRESS":"unix:path=/fixture/no-system",
               "PIPEWIRE_RUNTIME_DIR":"/fixture/run", "BASELINE":"/fixture/no-native-actions", "STEPS":json.dumps(steps)}
        cmd = ["/usr/bin/bwrap", "--die-with-parent", "--new-session", "--unshare-all", "--ro-bind", "/usr", "/usr",
               "--symlink", "usr/bin", "/bin", "--symlink", "usr/lib", "/lib", "--symlink", "usr/lib", "/lib64",
               "--ro-bind", "/etc/fonts", "/etc/fonts", "--proc", "/proc", "--dev", "/dev", "--tmpfs", "/tmp",
               "--bind", str(base), "/fixture", "--clearenv", "--chdir", "/fixture"]
        for key, value in env.items(): cmd += ["--setenv", key, value]
        cmd += ["/usr/bin/prlimit", "--core=0", "--fsize=16777216", "--", "/bin/sh", "-c",
                "exec /usr/bin/quickshell -p /fixture --no-color > /fixture/shell.log 2>&1"]
        print("BAR_SWITCH_INPUTS "+json.dumps({"plugins":identities,"steps":steps}), flush=True)
        try:
            result = run_bounded(cmd, timeout=180, maximum=1024*1024)
            print((result.stdout+result.stderr).decode(errors="replace"), end="", flush=True)
        finally:
            log = base / "shell.log"
            text = log.read_text(errors="replace") if log.exists() else ""
            print(text, end="", flush=True)
    print("BAR_SWITCH_CLEANUP "+json.dumps({"removed":not base.exists()}), flush=True)
    rows = [json.loads(line.split("BAR_SWITCH_STEP ",1)[1]) for line in text.splitlines() if "BAR_SWITCH_STEP " in line]
    census = [json.loads(line.split("BAR_SWITCH_CENSUS ",1)[1]) for line in text.splitlines() if "BAR_SWITCH_CENSUS " in line]
    # Quickshell 0.3.2 / Qt 6.12 (Omarchy 4.0.6) report the embedded native Ui color bindings as
    # undefined while bars are created and torn down; the unchanged Beta 16.5 fixture shows the
    # same three lines on that stack (hotfix 16.5.1, round 408 gate 16).
    allowed = r'^\s*(?:INFO: (?:Launching config:|Shell ID:|Saving logs to|Configuration Loaded)|WARN quickshell.qmlscanner: Module path contains invalid characters for a module name:|DEBUG qml: BAR_SWITCH_|WARN scene: @Ui/(?:WidgetButton|Panel)\.qml\[\d+:\d+\]: Unable to assign \[undefined\] to QColor$)'
    unexpected = [line for line in text.splitlines() if line.strip() and not re.match(allowed,line)]
    assert result.returncode == 0 and "BAR_SWITCH_DONE" in text, "fixture failed"
    assert not unexpected, unexpected
    assert len(rows)==len(steps)==len(census) and len({r["pid"] for r in rows})==1, "incomplete series"
    for index, row in enumerate(rows):
        assert row["index"]==index and row["step"]==list(steps[index]) and census[index]==[row["pid"]], row
        assert row["bar"] and row["bell"] and row["brightness"], row
        assert all(row[name]=={"present":True,"bound":True,"loader":1} for name in ("center","update","tray","audio","monitor")), row
    print("bar switch regression passed")


if __name__ == "__main__":
    main()
