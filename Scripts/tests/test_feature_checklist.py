"""Exercise the checklist gate through its CLI, without importing its logic."""

from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]


class FeatureChecklistTests(unittest.TestCase):
    def insert_row(self, document, row):
        prefix, heading, section = document.partition("## Spec requirement ownership\n")
        self.assertTrue(heading, "Mutation must reach the checked ownership section")
        original = next(line for line in section.splitlines() if line.startswith("| US-01 |"))
        return prefix + heading + section.replace(original, original + "\n" + row, 1)

    def run_gate(self, document):
        with tempfile.TemporaryDirectory(prefix="vlmsnapper-checklist-") as directory:
            source = Path(directory) / "checklist.md"
            source.write_text(document, encoding="utf-8")
            return subprocess.run(
                [sys.executable, str(ROOT / "Scripts/verify-feature-checklist.py"), str(source)],
                capture_output=True, text=True, check=False, timeout=10,
            )

    def test_missing_requirement_fails_even_with_ownership_heading(self):
        source = (ROOT / "docs/.workings/v1-core/checklist.md").read_text(encoding="utf-8")
        incomplete = "\n".join(line for line in source.splitlines() if not line.startswith("| FM-46 |"))
        result = self.run_gate(incomplete)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("FM-46", result.stderr)

    def test_duplicate_requirement_is_not_hidden_by_unique_count(self):
        source = (ROOT / "docs/.workings/v1-core/checklist.md").read_text(encoding="utf-8")
        duplicate = self.insert_row(source, "| US-01 | Duplicate | 19 | Named acceptance |")
        result = self.run_gate(duplicate)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Duplicate", result.stderr)

    def test_unknown_requirement_cannot_expand_the_contract_silently(self):
        source = (ROOT / "docs/.workings/v1-core/checklist.md").read_text(encoding="utf-8")
        result = self.run_gate(self.insert_row(source, "| FM-47 | Unexpected | 23 | Named acceptance |"))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Unexpected", result.stderr)

    def test_complete_repository_checklist_passes_with_historical_evidence(self):
        source = (ROOT / "docs/.workings/v1-core/checklist.md").read_text(encoding="utf-8")
        result = self.run_gate(source)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("58 requirements", result.stdout)

    def test_blank_or_malformed_ownership_rows_fail(self):
        source = (ROOT / "docs/.workings/v1-core/checklist.md").read_text(encoding="utf-8")
        original = next(line for line in source.splitlines() if line.startswith("| US-01 |"))
        for row in (
            "| US-01 | Description |   | Named acceptance |",
            "| US-01 | Description | 19 |   |",
            "| US-01 | Description | 19 |",
            "| US-01 | Description | 19 | Named acceptance | Extra |",
        ):
            with self.subTest(row=row):
                result = self.run_gate(source.replace(original, row, 1))
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("US-01", result.stderr)

    def test_missing_or_duplicate_section_is_not_accepted(self):
        source = (ROOT / "docs/.workings/v1-core/checklist.md").read_text(encoding="utf-8")
        for document in (
            source.replace("## Spec requirement ownership", "## Retired ownership"),
            source + "\n## Spec requirement ownership\n",
        ):
            with self.subTest(document=document[-60:]):
                result = self.run_gate(document)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("Expected one", result.stderr)


if __name__ == "__main__":
    unittest.main()
