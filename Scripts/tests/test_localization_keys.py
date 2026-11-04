import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "verify-localization-keys.py"
CLEAN = '"action.copy" = "%@ copy";\n"action.save" = "Save";\n'


class LocalizationKeysTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory(prefix="vlmsnapper-localization-keys-")
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name)
        self.sources = self.root / "Sources"
        self.sources.mkdir()
        self.write_dictionary("en", CLEAN)
        self.write_dictionary("zh-Hans", CLEAN)

    def write_dictionary(self, language, content):
        directory = self.root / "Localization" / f"{language}.lproj"
        directory.mkdir(parents=True, exist_ok=True)
        (directory / "Localizable.strings").write_text(content, encoding="utf-8")

    def write_source(self, content, name="Code.swift"):
        (self.sources / name).write_text(content, encoding="utf-8")

    def run_script(self):
        return subprocess.run(
            [sys.executable, str(SCRIPT), "--dictionaries", str(self.root / "Localization"),
             "--sources", str(self.sources)],
            capture_output=True, text=True,
        )

    def assert_fails_naming(self, *names):
        result = self.run_script()
        self.assertEqual(result.returncode, 1, result.stderr)
        for name in names:
            self.assertIn(name, result.stderr)

    def assert_passes(self):
        result = self.run_script()
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_matching_dictionaries_pass(self):
        self.assert_passes()

    def test_key_missing_from_the_second_language_fails(self):
        self.write_dictionary("en", CLEAN + '"only.english" = "English";\n')
        self.assert_fails_naming("zh-Hans", "only.english")

    def test_key_missing_from_the_first_language_fails(self):
        self.write_dictionary("zh-Hans", CLEAN + '"only.chinese" = "中文";\n')
        self.assert_fails_naming("en", "only.chinese")

    def test_commented_out_key_counts_as_missing(self):
        self.write_dictionary("zh-Hans", '"action.copy" = "%@ 复制";\n/* "action.save" = "保存"; */\n')
        self.assert_fails_naming("zh-Hans", "action.save")

    def test_key_behind_a_line_comment_counts_as_missing(self):
        self.write_dictionary("zh-Hans", '"action.copy" = "%@ 复制";\n// "action.save" = "保存";\n')
        self.assert_fails_naming("zh-Hans", "action.save")

    def test_escaped_quote_inside_a_value_is_text(self):
        value = '"action.copy" = "%@ \\"copy\\"";\n"action.save" = "Save";\n'
        self.write_dictionary("en", value)
        self.write_dictionary("zh-Hans", value)
        self.assert_passes()

    def test_duplicate_key_fails_in_either_language(self):
        for language in ("en", "zh-Hans"):
            with self.subTest(language=language):
                self.write_dictionary("en", CLEAN)
                self.write_dictionary("zh-Hans", CLEAN)
                self.write_dictionary(language, CLEAN + '"action.save" = "Again";\n')
                self.assert_fails_naming(language, "duplicate key action.save")

    def test_different_format_specifiers_fail_in_either_direction(self):
        for language in ("en", "zh-Hans"):
            with self.subTest(language=language):
                self.write_dictionary("en", CLEAN)
                self.write_dictionary("zh-Hans", CLEAN)
                self.write_dictionary(language, '"action.copy" = "copy";\n"action.save" = "Save";\n')
                self.assert_fails_naming("action.copy", "format specifiers differ")

    def test_different_format_kinds_fail(self):
        for english, chinese in (("%@ copy", "%d 复制"), ("%1$@ copy", "%1$d 复制")):
            with self.subTest(english=english, chinese=chinese):
                self.write_dictionary("en", f'"action.copy" = "{english}";\n"action.save" = "Save";\n')
                self.write_dictionary("zh-Hans", f'"action.copy" = "{chinese}";\n"action.save" = "保存";\n')
                self.assert_fails_naming("action.copy", "format specifiers differ")

    def test_translation_may_reorder_positional_arguments(self):
        self.write_dictionary("en", '"action.copy" = "%1$@ of %2$d";\n"action.save" = "Save";\n')
        self.write_dictionary("zh-Hans", '"action.copy" = "%2$d 中的 %1$@";\n"action.save" = "保存";\n')
        self.assert_passes()

    def test_percent_sign_is_not_an_argument(self):
        self.write_dictionary("en", '"action.copy" = "100%% of %@";\n"action.save" = "Save";\n')
        self.write_dictionary("zh-Hans", '"action.copy" = "%@ 的全部";\n"action.save" = "保存";\n')
        self.assert_passes()

    def test_comment_markers_inside_a_value_are_text(self):
        value = '"action.copy" = "%@ https://example.invalid/*";\n"action.save" = "Save";\n'
        self.write_dictionary("en", value)
        self.write_dictionary("zh-Hans", value)
        self.assert_passes()

    def test_entry_that_cannot_be_read_fails(self):
        self.write_dictionary("en", CLEAN + '"broken.entry" = "no semicolon"\n')
        self.assert_fails_naming("cannot read an entry", "broken.entry")

    def test_fewer_than_two_languages_fails(self):
        (self.root / "Localization/zh-Hans.lproj/Localizable.strings").unlink()
        (self.root / "Localization/zh-Hans.lproj").rmdir()
        self.assert_fails_naming("fewer than two languages")

    def test_keys_named_in_code_must_exist(self):
        sources = {
            "localized": 'localized("missing.first")',
            "localizedString": 'VLMSnapperLocalization.localizedString(\n    forKey: "missing.second"\n)',
        }
        for name, source in sources.items():
            with self.subTest(form=name):
                self.write_source(source)
                self.assert_fails_naming("missing.")

    def test_keys_mapped_in_the_strings_file_must_exist(self):
        self.write_source('case "transport": "failure.missing"\n', name="VLMSnapperStrings.swift")
        self.assert_fails_naming("failure.missing")

    def test_keys_that_exist_in_code_pass(self):
        self.write_source('localized("action.copy")\nlocalizedString(forKey: "action.save")\n')
        self.assert_passes()

    def test_user_defaults_keys_are_not_dictionary_keys(self):
        self.write_source('defaults.integer(forKey: "historyRetentionDays")\n')
        self.write_source('defaults.set(1, forKey: "history.retention")\n', name="Other.swift")
        self.assert_passes()

    def test_dotted_literals_elsewhere_are_not_keys(self):
        self.write_source('root.appendingPathComponent("history.sqlite")\n')
        self.assert_passes()


if __name__ == "__main__":
    unittest.main()
