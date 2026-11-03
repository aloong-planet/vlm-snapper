import importlib.util
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "Scripts/desktop-regression-needed.py"
SPEC = importlib.util.spec_from_file_location("desktop_regression_needed", SCRIPT)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)

COVERED_FILE = "VLMSnapper/UI/ProviderAPIKeyField.swift"
OTHER_FILE = "VLMSnapper/UI/CaptureOperationToolbar.swift"
NOT_NEEDED = 10


class DesktopRegressionNeededTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory(prefix="vlmsnapper-desktop-scope-")
        self.addCleanup(directory.cleanup)
        self.repository = Path(directory.name)
        self.git("init", "-q")
        self.write(COVERED_FILE)
        self.write(OTHER_FILE)
        self.commit("base")
        self.git("update-ref", "refs/remotes/origin/main", "HEAD")

    def git(self, *arguments):
        subprocess.run(
            ["git", "-c", "user.name=test", "-c", "user.email=test@example.invalid", *arguments],
            cwd=self.repository, check=True, capture_output=True,
        )

    def write(self, path, content="first\n"):
        file = self.repository / path
        file.parent.mkdir(parents=True, exist_ok=True)
        file.write_text(content)

    def commit(self, message):
        self.git("add", "-A")
        self.git("commit", "-q", "-m", message)

    def run_script(self):
        return subprocess.run([sys.executable, str(SCRIPT)], cwd=self.repository, capture_output=True, text=True)

    def test_no_change_needs_nothing(self):
        self.assertEqual(self.run_script().returncode, NOT_NEEDED)

    def test_other_files_need_nothing_committed_or_not(self):
        self.write(OTHER_FILE, "second\n")
        self.commit("other")
        self.write("docs/note.md")
        self.assertEqual(self.run_script().returncode, NOT_NEEDED)

    def test_committed_change_to_a_covered_file_needs_them_and_names_it(self):
        self.write(COVERED_FILE, "second\n")
        self.commit("covered")
        result = self.run_script()
        self.assertEqual(result.returncode, 0)
        self.assertIn(COVERED_FILE, result.stdout)

    def test_uncommitted_change_needs_them(self):
        self.write(COVERED_FILE, "second\n")
        self.assertEqual(self.run_script().returncode, 0)

    def test_staged_change_needs_them(self):
        self.write(COVERED_FILE, "second\n")
        self.git("add", "-A")
        self.assertEqual(self.run_script().returncode, 0)

    def test_untracked_covered_file_needs_them(self):
        self.write("VLMSnapper/UI/ProviderNewField.swift")
        self.assertEqual(self.run_script().returncode, 0)

    def test_deleted_covered_file_needs_them(self):
        (self.repository / COVERED_FILE).unlink()
        self.commit("delete")
        self.assertEqual(self.run_script().returncode, 0)

    def test_covered_file_renamed_away_needs_them(self):
        self.git("mv", COVERED_FILE, "VLMSnapper/UI/Moved.swift")
        self.commit("rename")
        self.assertEqual(self.run_script().returncode, 0)

    def test_change_already_on_the_default_branch_needs_nothing(self):
        self.write(COVERED_FILE, "second\n")
        self.commit("covered")
        self.git("update-ref", "refs/remotes/origin/main", "HEAD")
        self.assertEqual(self.run_script().returncode, NOT_NEEDED)

    def test_without_the_default_branch_it_cannot_tell_so_runs_them(self):
        self.git("update-ref", "-d", "refs/remotes/origin/main")
        result = self.run_script()
        self.assertEqual(result.returncode, 0)
        self.assertIn("cannot compare", result.stdout)

    def test_every_covered_path_still_names_something_in_the_repository(self):
        tracked = subprocess.run(["git", "ls-files"], cwd=ROOT, capture_output=True, text=True, check=True)
        files = tracked.stdout.splitlines()
        self.assertTrue(files)
        for path in MODULE.COVERED_PATHS:
            self.assertTrue(any(file.startswith(path) for file in files), path)


if __name__ == "__main__":
    unittest.main()
