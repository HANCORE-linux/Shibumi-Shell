#!/usr/bin/env python3
"""Near-neighbor checks for the narrow shared-runtime dependency exception."""
import json
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from scripts.shared_runtime_contract import (
    IMPORTERS,
    MODULE,
    MODULE_FILES,
    PRESENTATION_IMPORTERS,
    PRESENTATION_MODULE,
    PRESENTATION_MODULE_FILES,
    approved_import_spans,
)

LINE = 'import "../hancore.shibumi.state/runtime" as SuiteRuntime\n'
PRESENTATION_LINE = (
    'import "../hancore.shibumi.state/lib/presentation" as Presentation\n')
CHECKER = Path(__file__).resolve().with_name("plugin-import-boundary.py")
ROOT = Path(__file__).resolve().parents[1]
SCOPED_SERVICE_IDS = (
    "hancore.shibumi.ai",
    "hancore.shibumi.bluetooth",
    "hancore.shibumi.brightness",
    "hancore.shibumi.center",
    "hancore.shibumi.network",
    "hancore.shibumi.quick-access",
    "hancore.shibumi.status",
    "hancore.shibumi.update-center",
)


class RuntimeImports(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="runtime-import-contract-")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        module = self.root / MODULE
        module.mkdir(parents=True)
        for name in MODULE_FILES:
            (module / name).write_text("// inert fixture\n")
        self.source = self.root / "hancore.shibumi.bar/Bar.qml"
        self.source.parent.mkdir()
        self.source.write_text(LINE)

    def allowed(self, text=LINE, source=None):
        return approved_import_spans(self.root, source or self.source, text)

    def test_exact_import_and_only_its_literal(self):
        for text in (LINE, "pragma ComponentBehavior: Bound\n\n" + LINE,
                     "\t" + LINE.replace("\n", "\r\n")):
            spans = self.allowed(text)
            self.assertEqual(len(spans), 1)
            for start, end in spans:
                self.assertEqual(text[start:end], '"../hancore.shibumi.state/runtime"')
        text = LINE + 'property string unrelated: "../hancore.shibumi.state/runtime"\n'
        spans = self.allowed(text)
        self.assertEqual(len(spans), 1)
        self.assertLess(next(iter(spans))[1], text.index("property"))

    def test_complete_current_importer_roster_through_public_checker(self):
        expected = {"hancore.shibumi." + name for name in (
            "ai/Service.qml", "audio/BarWidget.qml", "audio/Service.qml",
            "bar/Bar.qml", "battery/BarWidget.qml", "bluetooth/Service.qml",
            "brightness/Service.qml", "center/Service.qml",
            "control-center/BarWidget.qml", "control-center/PluginUpdateService.qml",
            "cpu/BarWidget.qml", "cpu/Service.qml", "gpu/BarWidget.qml",
            "media/BarWidget.qml", "media/Service.qml", "memory/BarWidget.qml",
            "network/Service.qml", "power-profile/BarWidget.qml",
            "power-state/Service.qml", "quick-access/Service.qml",
            "reactor/Service.qml", "status/Service.qml", "storage/BarWidget.qml",
            "storage/Service.qml", "telemetry/Service.qml",
            "temperature/BarWidget.qml", "update-center/Service.qml",
            "workspaces/BarWidget.qml", "workspaces/WorkspaceService.qml")}
        self.assertEqual(IMPORTERS, expected)
        for name in sorted(expected):
            with self.subTest(importer=name):
                source = self.root / name
                source.parent.mkdir(parents=True, exist_ok=True)
                source.write_text(LINE)
                for content, code in ((LINE, 0), (LINE.replace("SuiteRuntime", "Other"), 1), (LINE, 0)):
                    source.write_text(content)
                    result = subprocess.run([sys.executable, str(CHECKER), str(source.parent)],
                        capture_output=True, text=True, timeout=4)
                    self.assertEqual(result.returncode, code, result.stdout + result.stderr)
                neighbor = source.with_name("Undeclared.qml")
                neighbor.write_text(LINE)
                result = subprocess.run([sys.executable, str(CHECKER), str(source.parent)],
                    capture_output=True, text=True, timeout=4)
                self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
                self.assertIn("Plugin imports escape", result.stderr)
                neighbor.unlink()

    def test_scoped_bar_services_publish_their_real_owner(self):
        for plugin_id in SCOPED_SERVICE_IDS:
            with self.subTest(plugin_id=plugin_id):
                source = ROOT / plugin_id / "Service.qml"
                text = source.read_text(encoding="utf-8")
                self.assertIn(LINE.strip(), text)
                blocks = re.findall(r"SuiteRuntime\.Provider\s*\{([^}]+)\}", text,
                                    flags=re.DOTALL)
                owned = [block for block in blocks
                         if f'pluginId: "{plugin_id}"' in block]
                self.assertEqual(len(owned), 1)
                for contract in ("owner: root", "host: root.shell",
                                 "manifest: root.manifest",
                                 'implementationVersion: "0.1.1-beta.15.3"'):
                    self.assertIn(contract, owned[0])

    def test_near_neighbors_receive_no_exception(self):
        cases = [LINE * 2, "/*\n" + LINE + "*/\n",
            "property string code: `\n" + LINE + "`\n", LINE.replace("SuiteRuntime", "Other"),
            LINE.replace("/runtime", ""), LINE.replace("/runtime", "/runtime/Runtime.qml"),
            LINE.replace("/runtime", "/runtime/"), LINE.replace("../", "../../"),
            LINE.replace("../", "%2e%2e/"), LINE.replace("../", r"\u002e\u002e/"),
            LINE.replace("hancore", "HANCORE"), LINE.replace("../", "file:///"),
            LINE.replace("../", "https://example.invalid/"),
            LINE.replace("import ", "property string source: ").replace(" as SuiteRuntime", "")]
        for text in cases:
            with self.subTest(text=text):
                self.assertEqual(self.allowed(text), set())
        for name in ("Unknown.qml", "bar.qml"):
            other = self.source.with_name(name)
            other.write_text(LINE)
            self.assertEqual(self.allowed(source=other), set())

    def test_public_checker_rejects_alternate_import_forms(self):
        cases = [
            'import "/tmp/outside" as Outside\n',
            'import "file:///tmp/outside" as Outside\n',
            'import "qrc:/outside" as Outside\n',
            'import "https://example.invalid/outside" as Outside\n',
            'import "%2e%2e/outside" as Outside\n',
            r'import "\u002e\u002e/outside" as Outside' + '\n',
            '/* comment */ import /* comment */ "/tmp/outside" as Outside\n',
            '// comment\u2028import "/tmp/outside" as Outside\n',
            '\ufeffimport "/tmp/outside" as Outside\n',
            '.import "../outside.js" as Outside\n',
            LINE.replace("SuiteRuntime", "Other"), LINE * 2,
        ]
        for text in [LINE, *cases, LINE]:
            self.source.write_text(text)
            result = subprocess.run([sys.executable, str(CHECKER), str(self.source.parent)],
                capture_output=True, text=True, timeout=4)
            with self.subTest(text=text):
                self.assertEqual(result.returncode, 0 if text == LINE else 1,
                    result.stdout + result.stderr)
                if text != LINE:
                    self.assertIn("Plugin imports escape", result.stderr)
        self.source.write_text(LINE + '// import "/tmp/comment"\n'
            + 'property string note: \'import "/tmp/string"\'\n')
        result = subprocess.run([sys.executable, str(CHECKER), str(self.source.parent)],
            capture_output=True, text=True, timeout=4)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_esm_and_canonical_paths_through_public_checker(self):
        module = self.source.with_name("consumer.mjs")
        bad = [
            'import value from "/tmp/outside.mjs";',
            'import {value as alias} from "file:///tmp/outside.mjs";',
            'import * as value from "https://example.invalid/outside.mjs";',
            'export * from "/tmp/outside.mjs";',
            'export {value} from "../outside.mjs";',
            'import("/tmp/outside.mjs");', 'import(dynamicName);',
            'import("local.mjs" + suffix);',
            *[f'import value from "{path}";' for path in
              ("./local.mjs", "sub/../local.mjs", "local//file.mjs", "local/")],
        ]
        for name in ("consumer.mjs", "consumer.MJS", "consumer.js"):
            module = self.source.with_name(name)
            for text in ['import value from "local.mjs";', *bad,
                         'export * from "local.mjs";']:
                module.write_text(text)
                result = subprocess.run([sys.executable, str(CHECKER), str(self.source.parent)],
                    capture_output=True, text=True, timeout=4)
                with self.subTest(name=name, text=text):
                    self.assertEqual(result.returncode, 1 if text in bad else 0, result.stderr)
                    if text in bad:
                        self.assertIn("Plugin imports escape", result.stderr)
            module.unlink()
        for path in (self.source, self.root / "absent"):
            result = subprocess.run([sys.executable, str(CHECKER), str(path)],
                capture_output=True, text=True, timeout=4)
            self.assertEqual(result.returncode, 1)
            self.assertIn("requires a directory", result.stderr)

    def test_javascript_lexical_boundaries_through_public_checker(self):
        module = self.source.with_name("lexical.mjs")
        outside = 'import value from "/tmp/outside.mjs";'
        bad = [
            'const pattern = /"/; ' + outside,
            'const pattern = /["/]/g; ' + outside,
            'if (true) /"/.test("x"); ' + outside,
            'object.if(1) / "2"; ' + outside,
            'value++ / "2"; ' + outside,
            'const a\u0301\u200d = 1; a\u0301\u200d / "2"; ' + outside,
            'export default /"/; ' + outside,
            'import "local.mjs"\n/"/; ' + outside,
            'const value = `${import("/tmp/outside.mjs")}`;',
            'const value = `${`${import("/tmp/outside.mjs")}`}`;',
            'const value = `${(()=>{return import("/tmp/outside.mjs")})()}`;',
            'const pattern = /unterminated\n' + outside,
            '/* unterminated\n' + outside,
        ]
        good = [
            'const pattern = /"/; const text = \'import "/tmp/string"\';',
            'const pattern = /["/]/g; import value from "local.mjs";',
            'const value = `not code: import "/tmp/string"`;',
            'const value = `${\'import "/tmp/string"\'}`;',
            'f(10) / 2 + g(4) / 2; import value from "local.mjs";',
        ]
        for text in [*good, *bad, *good]:
            module.write_text(text)
            result = subprocess.run([sys.executable, str(CHECKER), str(self.source.parent)],
                capture_output=True, text=True, timeout=4)
            with self.subTest(text=text):
                self.assertEqual(result.returncode, 1 if text in bad else 0, result.stderr)
                if text in bad:
                    self.assertIn("Plugin imports escape", result.stderr)

    def test_missing_extra_and_nonregular_module_members(self):
        target = self.root / MODULE / "Runtime.qml"
        target.unlink()
        self.assertEqual(self.allowed(), set())
        target.write_text("// restored\n")
        self.assertTrue(self.allowed())
        extra = target.with_name("undeclared.qml")
        extra.write_text("// extra\n")
        self.assertEqual(self.allowed(), set())
        extra.unlink()
        target.unlink()
        target.mkdir()
        self.assertEqual(self.allowed(), set())

    def test_source_and_module_symlinks_refuse(self):
        target = self.root / MODULE / "Runtime.qml"
        target.unlink()
        target.symlink_to("Provider.qml")
        self.assertEqual(self.allowed(), set())
        target.unlink()
        target.write_text("// restored\n")
        self.source.unlink()
        self.source.symlink_to(target)
        self.assertEqual(self.allowed(), set())
        self.source.unlink()
        self.source.write_text(LINE)
        module = self.root / MODULE
        held = self.root / "held-module"
        module.rename(held)
        module.symlink_to(held, target_is_directory=True)
        self.assertEqual(self.allowed(), set())

    def test_declared_media_importer_uses_same_physical_module(self):
        source = self.root / "hancore.shibumi.media/Service.qml"
        source.parent.mkdir()
        source.write_text(LINE)
        self.assertTrue(self.allowed(source=source))
        shutil.rmtree(self.root / MODULE)
        self.assertEqual(self.allowed(source=source), set())


class PresentationImports(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(
            prefix="presentation-import-contract-")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        module = self.root / PRESENTATION_MODULE
        module.mkdir(parents=True)
        for name in PRESENTATION_MODULE_FILES:
            (module / name).write_text("// inert fixture\n")
        self.source = self.root / "hancore.shibumi.ai/AiUsagePanel.qml"
        self.source.parent.mkdir()
        self.source.write_text(PRESENTATION_LINE)

    def allowed(self, text=PRESENTATION_LINE, source=None):
        return approved_import_spans(
            self.root, source or self.source, text)

    def test_production_roster_and_direct_state_dependency_are_exact(self):
        actual = set()
        for source in ROOT.glob("hancore.shibumi.*/*.qml"):
            if PRESENTATION_LINE.strip() in source.read_text(encoding="utf-8"):
                actual.add(source.relative_to(ROOT).as_posix())
        self.assertEqual(actual, PRESENTATION_IMPORTERS)
        self.assertEqual(len(actual), 60)

        contract = json.loads(
            (ROOT / "contracts/plugin-suite-v1.json").read_text())
        by_id = {row["id"]: row for row in contract["plugins"]}
        consumers = {name.split("/", 1)[0] for name in actual}
        self.assertEqual(len(consumers), 19)
        self.assertLess(
            [row["id"] for row in contract["plugins"]].index(
                "hancore.shibumi.state"),
            min([row["id"] for row in contract["plugins"]].index(plugin)
                for plugin in consumers))
        for plugin in consumers:
            with self.subTest(plugin=plugin):
                self.assertIn("hancore.shibumi.state", by_id[plugin]["requires"])
                manifest = json.loads(
                    (ROOT / plugin / "manifest.json").read_text())
                self.assertIn("hancore.shibumi.state",
                              manifest["x-shibumi"]["requires"])

    def test_exact_import_and_alias_only(self):
        spans = self.allowed()
        self.assertEqual(len(spans), 1)
        start, end = next(iter(spans))
        self.assertEqual(
            PRESENTATION_LINE[start:end],
            '"../hancore.shibumi.state/lib/presentation"')
        for text in (
            PRESENTATION_LINE * 2,
            PRESENTATION_LINE.replace("Presentation", "Other"),
            PRESENTATION_LINE.replace("/presentation", "/presentation/"),
            PRESENTATION_LINE.replace("../", "../../"),
            PRESENTATION_LINE.replace("../", "%2e%2e/"),
            PRESENTATION_LINE.replace("../", "file:///"),
            "// " + PRESENTATION_LINE,
        ):
            with self.subTest(text=text):
                self.assertEqual(self.allowed(text), set())

    def test_undeclared_importer_and_incomplete_or_nonregular_module_refuse(self):
        undeclared = self.source.with_name("Undeclared.qml")
        undeclared.write_text(PRESENTATION_LINE)
        self.assertEqual(self.allowed(source=undeclared), set())

        module = self.root / PRESENTATION_MODULE
        member = module / "HostTokens.qml"
        member.unlink()
        self.assertEqual(self.allowed(), set())
        member.write_text("// restored\n")
        self.assertTrue(self.allowed())
        extra = module / "Unexpected.qml"
        extra.write_text("// extra\n")
        self.assertEqual(self.allowed(), set())
        extra.unlink()
        member.unlink()
        member.symlink_to("IconText.qml")
        self.assertEqual(self.allowed(), set())

    def test_public_checker_accepts_only_the_declared_complete_module(self):
        result = subprocess.run(
            [sys.executable, str(CHECKER), str(self.source.parent)],
            capture_output=True, text=True, timeout=4)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.source.write_text(PRESENTATION_LINE.replace(
            " as Presentation", " as Other"))
        result = subprocess.run(
            [sys.executable, str(CHECKER), str(self.source.parent)],
            capture_output=True, text=True, timeout=4)
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("Plugin imports escape", result.stderr)

    def test_library_remains_passive(self):
        module = ROOT / PRESENTATION_MODULE
        self.assertEqual(
            {path.name for path in module.iterdir()},
            set(PRESENTATION_MODULE_FILES))
        self.assertEqual(
            (module / "qmldir").read_text(encoding="utf-8"),
            "module Shibumi.Presentation\n"
            "ControlCenterIconText 1.0 ControlCenterIconText.qml\n"
            "HostTokens 1.0 HostTokens.qml\n"
            "IconText 1.0 IconText.qml\n"
            "PacmanWorkspaceMarker 1.0 PacmanWorkspaceMarker.qml\n"
            "PillSurface 1.0 PillSurface.qml\n"
            "ShibumiPanelToolTip 1.0 ShibumiPanelToolTip.qml\n"
            "ShibumiPillToolTip 1.0 ShibumiPillToolTip.qml\n")
        forbidden = re.compile(
            r"\b(Process|FileView|Timer|WorkerScript|PersistentProperties)\s*\{")
        for source in module.glob("*.qml"):
            with self.subTest(source=source.name):
                text = source.read_text(encoding="utf-8")
                self.assertIsNone(forbidden.search(text))
                self.assertNotIn("pragma Singleton", text)
                self.assertNotIn(".pragma library", text)
                self.assertNotIn("import Quickshell", text)
                self.assertNotIn("import qs.Services", text)


if __name__ == "__main__":
    unittest.main()
