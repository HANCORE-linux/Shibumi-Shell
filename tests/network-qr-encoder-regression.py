#!/usr/bin/env python3

from __future__ import annotations

import hashlib
import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest import mock


ROOT = Path(__file__).resolve().parents[1]
ENCODER = ROOT / "hancore.shibumi.network" / "NetworkQrEncoder.js"

VECTORS = (
    (
        "WIFI:T:nopass;S:Guest;H:false;;",
        37,
        "cad50c3c4375a7515e4a63676307cdfe4dda4803a85c283730c31678788250a5",
    ),
    (
        r"WIFI:T:WPA;S:Private\;Office;P:correct\;horse;H:false;;",
        41,
        "24880828c6d16c5789a961992b98792deeffeecd1fa291463b098a7cc33da9fb",
    ),
    (
        "WIFI:T:WPA;S:" + r"\;" * 32 + ";P:" + r"\;" * 63 + ";H:false;;",
        69,
        "245dad0638792633c85fa1af98d8277679037e91a105093256ce3812c78e1610",
    ),
    (
        "WIFI:T:nopass;S:Café 東京;H:false;;",
        37,
        "94eb0bb3862669c98ba4a269ed43e0906735618c4bf95b33e7844a666ed9dd25",
    ),
    (
        "WIFI:T:SAE;S:WPA3;P:dragonfly;H:false;;",
        37,
        "2c7403e67f62fa27350c47ca4eff60f5cce67fe80afabe7ad8a5cf54f946f976",
    ),
    (
        "WIFI:T:nopass;S:HiddenOpen;H:true;;",
        37,
        "074752fc2b843eaa95ca4fae9fccce636b3c2dc9ad92d7981f8c32677cf50115",
    ),
    (
        "WIFI:T:WPA;S:HiddenSecure;P:correcthorse;H:true;;",
        41,
        "d20ec5d15af9e9d15a11195deadf69835535572404926da5837128da575dd6ad",
    ),
)

BOUNDARY_VECTORS = (
    (1, 29, "11f639996ae78e9167d082468fdc347ce7f15e2ade14540df1f35a83b706309b"),
    (13, 29, "a0d403aee6b9d451846de3fc51d8b922165bf2adf0c2788c345ae664b2266225"),
    (14, 33, "486dee7c2dfbbfdfbd2bc292ec9e1cf84056eade37105c62b3104f6df96310aa"),
    (25, 33, "0ed4a7b87669e09c10c4be7897d1007bce27ccd48aa1ef70e20d8bb43bc9e70f"),
    (26, 37, "b6cec184dee9b8bfca6312ac1a64c9c1ff29f7248f55b5f94aaf67e0fe06bfb4"),
    (41, 37, "ccff8bb1471c9040317835db685d9c39e78d2c6cc75c195c4a63c226c2cac2a1"),
    (42, 41, "5a07de8fa37d7e30f1596a6384a8ccd380e2faf6a7863ad28af100da562fbe44"),
    (61, 41, "40c4932f6214b684a17dab20d299ef1063d9e507ed7b90a6543179244aa35d0f"),
    (62, 45, "ca2c17907c75e8598d610de04ee432063df87d0f3e14dd925271c02b5b559f84"),
    (83, 45, "2305cb195b946cda99f3aa9f0844ada0daf072c5b0ed321d3eda0e12b527ff25"),
    (84, 49, "56e3c6c5c13412c07fbd5d55d4095b40463d5c8447486ea918fc3189ea2efca0"),
    (105, 49, "80c25ddb9ca3a42bdb6e929e5b974cdaca2fd0a631bdecb022fda00419309d21"),
    (106, 53, "76c1d8529ff95ac6f29c3d7c06d24f6a8ae3780399c8f85a8237598fd54cdde9"),
    (121, 53, "3ee2e318ad5f5be42c0d7355a9cdddc7a023b4fcaa4ced39b1c9c6db140d4b9b"),
    (122, 57, "989166a9b755a42bad43b66e6c8950c688c6ff4fea388671d95f0d61a78e854f"),
    (151, 57, "06499f9c503f584a348e16a3c054f6c3467867b4cbb5fd05013dc87f232cb654"),
    (152, 61, "e6a63a61e387517c8bb7730aaea6bbd454b310dc34e5ea69e71a979c65d8ba66"),
    (179, 61, "30ea97aa0c0f6f808cfedfad739347593f66735554a8016ed4e48313ccf2bdae"),
    (180, 65, "10814c9509c8a095e9317d6077615466c26c2e0e877114280129f80a16520728"),
    (212, 65, "d6ef8d2904dc3cb674a454f05765d64bf5b6c68b5836c788d214efc4069528e9"),
    (213, 69, "c820ee0f7b408fa0b48f171518d1a1e11698fdf405c005267a22b10d5d7c4777"),
    (240, 69, "44dd83f2e302a06511d22f3829a7df63e325788ed436147cbd1b1b50ccb49172"),
)


def required_tool(name: str) -> str:
    path = shutil.which(name)
    if not path:
        raise RuntimeError(f"missing required QR verification tool: {name}")
    return path


def encode_vectors(payloads: list[str]) -> list[dict[str, object]]:
    source = "\n".join(
        line for line in ENCODER.read_text(encoding="utf-8").splitlines()
        if not line.startswith(".pragma ")
    )
    harness = r"""
const fs = require("fs");
const payloads = JSON.parse(fs.readFileSync(0, "utf8"));
const results = payloads.map(function(payload) { return encode(payload); });
process.stdout.write(JSON.stringify(results));
"""
    with tempfile.TemporaryDirectory(prefix="shibumi-qr-node-") as directory:
        script = Path(directory) / "encoder.js"
        script.write_text(source + "\n" + harness, encoding="utf-8")
        completed = subprocess.run(
            ["/usr/bin/node", str(script)],
            input=json.dumps(payloads, ensure_ascii=False),
            text=True,
            capture_output=True,
            check=False,
            timeout=10,
        )
    if completed.returncode != 0:
        raise AssertionError("bounded QR encoder harness failed")
    return json.loads(completed.stdout)


def pbm(rows: list[str], scale: int = 6) -> bytes:
    size = len(rows)
    output = ["P1", f"{size * scale} {size * scale}"]
    for row in rows:
        expanded = " ".join(bit for bit in row for _ in range(scale))
        output.extend(expanded for _ in range(scale))
    return ("\n".join(output) + "\n").encode("ascii")


class NetworkQrEncoderRegressionTests(unittest.TestCase):
    def test_verified_wifi_vectors(self) -> None:
        self.assertTrue(ENCODER.is_file())
        self.assertTrue(Path("/usr/bin/node").is_file())
        results = encode_vectors([payload for payload, _, _ in VECTORS])
        self.assertEqual(len(results), len(VECTORS))
        zbar = required_tool("zbarimg")

        for result, (payload, expected_size, expected_hash) in zip(
            results, VECTORS, strict=True
        ):
            self.assertEqual(set(result), {"ok", "code", "size", "rows"})
            self.assertIs(result["ok"], True)
            self.assertEqual(result["code"], "ready")
            self.assertEqual(result["size"], expected_size)
            rows = result["rows"]
            self.assertIsInstance(rows, list)
            self.assertEqual(len(rows), expected_size)
            self.assertTrue(all(
                isinstance(row, str)
                and len(row) == expected_size
                and set(row) <= {"0", "1"}
                for row in rows
            ))
            quiet = "0" * expected_size
            self.assertEqual(rows[:4], [quiet] * 4)
            self.assertEqual(rows[-4:], [quiet] * 4)
            digest = hashlib.sha256("\n".join(rows).encode("ascii")).hexdigest()
            self.assertEqual(digest, expected_hash)

            with tempfile.TemporaryDirectory(
                prefix="shibumi-qr-decode-"
            ) as directory:
                image = Path(directory) / "vector.pbm"
                image.write_bytes(pbm(rows))
                decoded = subprocess.run(
                    [zbar, "--quiet", "--raw", str(image)],
                    capture_output=True,
                    check=False,
                    timeout=10,
                )
            self.assertEqual(decoded.returncode, 0)
            self.assertEqual(
                decoded.stdout.rstrip(b"\n").decode("utf-8"), payload
            )

    def test_all_versions_and_capacity_transitions(self) -> None:
        payloads = ["A" * length for length, _, _ in BOUNDARY_VECTORS]
        results = encode_vectors(payloads)
        zbar = required_tool("zbarimg")
        self.assertEqual(len(results), len(BOUNDARY_VECTORS))
        self.assertEqual(
            {int(result["size"]) for result in results},
            set(range(29, 70, 4)),
        )
        for result, payload, (_, expected_size, expected_hash) in zip(
            results, payloads, BOUNDARY_VECTORS, strict=True
        ):
            self.assertIs(result["ok"], True)
            self.assertEqual(result["code"], "ready")
            self.assertEqual(result["size"], expected_size)
            rows = result["rows"]
            digest = hashlib.sha256(
                "\n".join(rows).encode("ascii")
            ).hexdigest()
            self.assertEqual(digest, expected_hash)
            with tempfile.TemporaryDirectory(
                prefix="shibumi-qr-boundary-"
            ) as directory:
                image = Path(directory) / "vector.pbm"
                image.write_bytes(pbm(rows))
                decoded = subprocess.run(
                    [zbar, "--quiet", "--raw", str(image)],
                    capture_output=True,
                    check=False,
                    timeout=10,
                )
            self.assertEqual(decoded.returncode, 0)
            self.assertEqual(decoded.stdout.rstrip(b"\n"), payload.encode())

    def test_missing_verifier_fails_explicitly(self) -> None:
        with mock.patch("shutil.which", return_value=None):
            with self.assertRaisesRegex(RuntimeError, "missing required"):
                required_tool("zbarimg")

    def test_invalid_input_fails_without_rows(self) -> None:
        results = encode_vectors(["", "A" * 241])
        self.assertEqual(results, [
            {"ok": False, "code": "invalid", "size": 0, "rows": []},
            {"ok": False, "code": "invalid", "size": 0, "rows": []},
        ])


if __name__ == "__main__":
    unittest.main(verbosity=2)
