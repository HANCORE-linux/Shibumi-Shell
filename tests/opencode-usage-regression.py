#!/usr/bin/env python3

import importlib.machinery
import importlib.util
import json
import os
import sqlite3
import subprocess
import tempfile
import time
import unittest
from datetime import datetime, timedelta
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = [
    REPO_ROOT / "scripts" / "opencode-usage",
    REPO_ROOT / "hancore.shibumi.ai" / "scripts" / "opencode-usage",
]


class OpenCodeUsageRegressionTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tempdir = tempfile.TemporaryDirectory(prefix="shibumi-opencode-")
        self.data_dir = Path(self.tempdir.name)
        self.database = self.data_dir / "opencode.db"
        with sqlite3.connect(self.database) as con:
            con.execute(
                """
                create table message (
                  session_id text not null,
                  time_created integer not null,
                  time_updated integer not null,
                  data text not null
                )
                """
            )

    def tearDown(self) -> None:
        self.tempdir.cleanup()

    def add_message(
        self,
        *,
        session: str,
        timestamp_ms: int,
        model: str,
        provider: str = "test-provider",
        input_tokens: int = 0,
        output_tokens: int = 0,
        reasoning_tokens: int = 0,
        cache_read: int = 0,
        cache_write: int = 0,
    ) -> None:
        data = {
            "role": "assistant",
            "modelID": model,
            "providerID": provider,
            "tokens": {
                "input": input_tokens,
                "output": output_tokens,
                "reasoning": reasoning_tokens,
                "cache": {"read": cache_read, "write": cache_write},
            },
        }
        with sqlite3.connect(self.database) as con:
            con.execute(
                "insert into message values (?, ?, ?, ?)",
                (session, timestamp_ms, timestamp_ms, json.dumps(data)),
            )

    def run_scripts(self) -> dict:
        environment = os.environ.copy()
        environment["OPENCODE_DATA_DIR"] = str(self.data_dir)
        outputs = []
        for script in SCRIPTS:
            result = subprocess.run(
                [str(script)],
                check=True,
                capture_output=True,
                text=True,
                env=environment,
                timeout=10,
            )
            outputs.append(json.loads(result.stdout))
        stable_outputs = []
        for output in outputs:
            stable = dict(output)
            stable.pop("updated_at", None)
            stable_outputs.append(stable)
        self.assertEqual(stable_outputs[0], stable_outputs[1])
        return outputs[0]

    def test_models_and_latest_model_use_positive_today_scope(self) -> None:
        now = datetime.now()
        today = now.replace(hour=0, minute=0, second=0, microsecond=0)
        tomorrow = today + timedelta(days=1)
        if (now - today < timedelta(minutes=5)
                or tomorrow - now < timedelta(minutes=5)):
            self.skipTest("local midnight boundary is too close for deterministic scope")
        current_ms = int(time.time() * 1000)
        old_ms = int((today - timedelta(minutes=1)).timestamp() * 1000)

        self.add_message(
            session="old",
            timestamp_ms=old_ms,
            model="historical-model",
            input_tokens=9000,
            output_tokens=1000,
        )
        self.add_message(
            session="current-a",
            timestamp_ms=current_ms - 4000,
            model="current-a",
            input_tokens=100,
            output_tokens=50,
            cache_read=500,
        )
        self.add_message(
            session="current-b",
            timestamp_ms=current_ms - 2000,
            model="current-b",
            input_tokens=20,
            output_tokens=30,
            reasoning_tokens=10,
            cache_write=5,
        )
        # A later assistant row with no scoped usage must neither create a
        # model row nor replace latestModel.
        self.add_message(
            session="zero",
            timestamp_ms=current_ms - 1000,
            model="zero-model",
        )
        self.add_message(
            session="future",
            timestamp_ms=current_ms + 60 * 60 * 1000,
            model="future-model",
            input_tokens=500,
        )

        output = self.run_scripts()
        rows = output["_models"]
        by_name = {row["name"]: row for row in rows}

        self.assertEqual(output["_model"], "current-b (test-provider)")
        self.assertEqual(
            set(by_name),
            {"current-a (test-provider)", "current-b (test-provider)"},
        )
        self.assertNotIn("historical-model (test-provider)", by_name)
        self.assertNotIn("zero-model (test-provider)", by_name)
        self.assertNotIn("future-model (test-provider)", by_name)

        current_a = by_name["current-a (test-provider)"]
        current_b = by_name["current-b (test-provider)"]
        self.assertEqual(current_a["total"], 150)
        self.assertEqual(current_a["inputLabel"], "100")
        self.assertEqual(current_a["outputLabel"], "50")
        self.assertEqual(current_a["cacheReadLabel"], "500")
        self.assertEqual(current_a["todayLabel"], "0")
        self.assertEqual(current_a["pct"], 100)
        self.assertEqual(current_b["total"], 65)
        self.assertEqual(current_b["pct"], 43)
        self.assertEqual(output["_today_tokens"], 215)
        self.assertEqual(output["_day"], today.date().isoformat())

    def test_local_day_bounds_follow_dst_midnights(self) -> None:
        if not hasattr(time, "tzset"):
            self.skipTest("tzset is unavailable")
        old_tz = os.environ.get("TZ")
        try:
            os.environ["TZ"] = "Europe/Berlin"
            time.tzset()
            loader = importlib.machinery.SourceFileLoader(
                "shibumi_opencode_usage", str(SCRIPTS[0])
            )
            spec = importlib.util.spec_from_loader(loader.name, loader)
            self.assertIsNotNone(spec)
            module = importlib.util.module_from_spec(spec)
            loader.exec_module(module)

            spring_start, spring_end, spring_day = module.local_day_bounds(
                datetime(2026, 3, 29, 12, 0, 0)
            )
            autumn_start, autumn_end, autumn_day = module.local_day_bounds(
                datetime(2026, 10, 25, 12, 0, 0)
            )
            self.assertEqual(spring_day, "2026-03-29")
            self.assertEqual(autumn_day, "2026-10-25")
            self.assertEqual(spring_end - spring_start, 23 * 60 * 60 * 1000)
            self.assertEqual(autumn_end - autumn_start, 25 * 60 * 60 * 1000)
        finally:
            if old_tz is None:
                os.environ.pop("TZ", None)
            else:
                os.environ["TZ"] = old_tz
            time.tzset()


if __name__ == "__main__":
    unittest.main(verbosity=2)
