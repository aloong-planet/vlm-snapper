import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


CHECKER = Path(__file__).resolve().parents[1] / "verify-swift-testing-log.py"


class SwiftTestingLogTests(unittest.TestCase):
    def check_log(self, content):
        with tempfile.TemporaryDirectory(prefix="vlmsnapper-test-completion-") as directory:
            log = Path(directory) / "test.log"
            log.write_text(content, encoding="utf-8")
            return subprocess.run(
                [sys.executable, str(CHECKER), str(log)],
                capture_output=True, text=True, check=False,
            )

    def test_xctest_success_cannot_mask_unfinished_swift_testing(self):
        result = self.check_log(
            "Test Suite 'Selected tests' passed.\n"
            "Executed 3 tests, with 0 failures (0 unexpected).\n"
            "◇ Test run started.\n"
            "✔ Test \"temporary hiding keeps the query\" passed after 2.265 seconds.\n"
            "◇ Test \"type Provider search and Pinned compose\" started.\n"
        )
        self.assertNotEqual(result.returncode, 0, "Incomplete tests must fail the gate")

    def test_complete_nonempty_run_passes(self):
        result = self.check_log(
            "Build complete! (3.60s)\n◇ Test run started.\n"
            "✔ Test run with 16 tests in 2 suites passed after 9.914 seconds.\n"
        )
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_empty_failed_and_mixed_runs_fail(self):
        for content in [
            "",
            "Executed 5 tests, with 0 failures\n",
            "◇ Test run started.\n✔ Test run with 0 tests in 0 suites passed after 0.001 seconds.\n",
            "◇ Test run started.\n✘ Test run with 331 tests in 72 suites failed after 20.208 seconds with 5 issues.\n",
            "✔ Test run with 1 test in 1 suite passed after 0.1 seconds.\n◇ Test run started.\n",
            "◇ Test run started.\n✔ Test run with 1 test in 1 suite passed after 0.1 seconds.\n◇ Test run started.\n",
            "◇ Test run started.\n✔ Test run with 1 test in 1 suite passed after 0.1 seconds.\n◇ Test \"late work\" started.\n",
        ]:
            with self.subTest(content=content):
                self.assertNotEqual(self.check_log(content).returncode, 0)

    def test_singular_summary_and_crlf_pass(self):
        result = self.check_log(
            "◇ Test run started.\r\n"
            "✔ Test run with 1 test in 1 suite passed after 1.234 seconds.\r\n"
        )
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_missing_file_fails(self):
        with tempfile.TemporaryDirectory(prefix="vlmsnapper-missing-log-") as directory:
            result = subprocess.run(
                [sys.executable, str(CHECKER), str(Path(directory) / "missing.log")],
                capture_output=True, text=True, check=False,
            )
        self.assertNotEqual(result.returncode, 0)


if __name__ == "__main__":
    unittest.main()
