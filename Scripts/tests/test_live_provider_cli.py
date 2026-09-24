"""Exercise the built live-gate CLI without credentials or network calls."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class LiveProviderCLITests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.env = {key: value for key, value in os.environ.items()
                   if key not in ("OPENAI_API_KEY", "GEMINI_API_KEY", "DEEPSEEK_API_KEY",
                                  "VLMSNAPPER_OPENAI_MODEL", "VLMSNAPPER_GEMINI_MODEL",
                                  "VLMSNAPPER_DEEPSEEK_MODEL")}
        subprocess.run(["swift", "build", "--product", "VLMSnapperLiveProviderGate"],
                       cwd=ROOT, env=cls.env, check=True, capture_output=True, timeout=180)
        binary_dir = subprocess.check_output(["swift", "build", "--show-bin-path"],
                                            cwd=ROOT, env=cls.env, text=True, timeout=30).strip()
        cls.binary = str(Path(binary_dir) / "VLMSnapperLiveProviderGate")

    def test_selected_provider_without_key_is_blocked_not_skipped(self):
        with tempfile.TemporaryDirectory() as directory:
            report = Path(directory) / "report.json"
            result = subprocess.run(
                [self.binary, "--provider", "deepseek", "--model", "deepseek-v4-pro",
                 "--output", str(report)], env=self.env, capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 1, result.stderr)
            rows = json.loads(report.read_text())
            self.assertEqual(len(rows), 2)
            self.assertEqual([row["provider"] for row in rows], ["deepseek", "deepseek"])
            self.assertEqual([row["operation"] for row in rows], ["extract", "translate"])
            self.assertTrue(all(row["outcome"] == "blocked" for row in rows))

    def test_help_does_not_require_credentials(self):
        for flag in ("--help", "-h"):
            result = subprocess.run([self.binary, flag], env=self.env,
                                    capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0)
            self.assertIn("Usage:", result.stdout)

    def test_invalid_scope_fails_before_creating_report(self):
        invalid = [[], ["--provider", "deepseek"], ["--model", "a"],
                   ["--provider", "invalid", "--model", "a"], ["--keychain"],
                   ["--provider", "deepseek", "--model", "a", "--model", "b"],
                   ["--unexpected"]]
        with tempfile.TemporaryDirectory() as directory:
            report = Path(directory) / "report.json"
            for args in invalid:
                # No arguments separately preserves the legacy required-output contract.
                command = args + ["--output", str(report)] if args else []
                with self.subTest(args=args):
                    result = subprocess.run([self.binary, *command], env=self.env,
                                            capture_output=True, timeout=10)
                    self.assertEqual(result.returncode, 64)
                    self.assertFalse(report.exists())

    def test_legacy_all_provider_mode_reports_all_missing_credentials(self):
        with tempfile.TemporaryDirectory() as directory:
            report = Path(directory) / "report.json"
            result = subprocess.run([self.binary, "--output", str(report)], env=self.env,
                                    capture_output=True, timeout=10)
            self.assertEqual(result.returncode, 1)
            rows = json.loads(report.read_text())
            self.assertEqual(len(rows), 6)
            self.assertEqual({row["provider"] for row in rows}, {"openai", "gemini", "deepseek"})
            self.assertTrue(all(row["outcome"] == "blocked" for row in rows))
