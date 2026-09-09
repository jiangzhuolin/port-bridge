import json
from pathlib import Path
from string import Formatter
import tempfile
import unittest
from unittest.mock import patch

from bridge import Config, Rule
from i18n import LocalizedError, ZH_CN, error_text, translate
from settings import Settings


class TranslationTests(unittest.TestCase):
    def test_catalog_placeholders_match(self):
        def fields(message):
            return {name for _, name, _, _ in Formatter().parse(message) if name is not None}
        for source, translated in ZH_CN.items():
            with self.subTest(source=source):
                self.assertEqual(fields(source), fields(translated))

    def test_nested_errors_and_user_values(self):
        # User-provided text must never be treated as translation keys or format strings.
        name = "running {error} 测试"
        self.assertIn(name, translate("zh_CN", "{name}  ·  Connections: {total} total / Errors: {errors}",
                                      name=name, total=2, errors=0))
        message = LocalizedError("Connection to the target timed out")
        self.assertEqual(translate("zh_CN", "Connection failed / interrupted: {error}", error=message),
                         "连接失败 / 中断：连接目标超时")
        self.assertEqual(error_text(OSError("system detail {x}"), "zh_CN"), "system detail {x}")

    def test_validation_can_be_rendered_in_both_languages(self):
        with self.assertRaises(LocalizedError) as raised:
            Rule("id", "").validate()
        self.assertEqual(error_text(raised.exception, "en"), "Enter a rule name")
        self.assertEqual(error_text(raised.exception, "zh_CN"), "请输入规则名称")
        self.assertEqual(translate("en", "running"), "Running")
        self.assertEqual(translate("zh_CN", "running"), "运行中")


class SettingsTests(unittest.TestCase):
    def test_default_round_trip_and_existing_rules_unchanged(self):
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            settings = Settings(folder / "settings.json")
            rules = Config(folder / "rules.json")
            rule = Rule("id", "用户规则", target_host="192.0.2.10")
            rules.save([rule])
            original = rules.path.read_bytes()
            self.assertEqual(settings.language(), "en")
            self.assertFalse(settings.path.exists())
            for language in ("zh_CN", "en"):
                settings.save_language(language)
                self.assertEqual(Settings(settings.path).language(), language)
                self.assertEqual(rules.path.read_bytes(), original)
                self.assertEqual(rules.load(), [rule])

    def test_unknown_language_fallback_and_other_fields_preserved(self):
        with tempfile.TemporaryDirectory() as directory:
            settings = Settings(Path(directory) / "settings.json")
            for value in ("fr", None, [], 1):
                settings.path.write_text(json.dumps({"language": value, "future": True}), encoding="utf-8")
                self.assertEqual(settings.language(), "en")
            settings.save_language("zh_CN")
            self.assertTrue(settings.load()["future"])

    def test_corrupt_settings_are_not_overwritten(self):
        with tempfile.TemporaryDirectory() as directory:
            settings = Settings(Path(directory) / "settings.json")
            for original in ("{broken", "[]", "null"):
                settings.path.write_text(original, encoding="utf-8")
                with self.assertRaises(ValueError):
                    settings.save_language("zh_CN")
                self.assertEqual(settings.path.read_text(), original)

    def test_failed_write_retains_previous_preference_and_cleans_temp_file(self):
        with tempfile.TemporaryDirectory() as directory:
            settings = Settings(Path(directory) / "settings.json")
            settings.save_language("en")
            with patch("settings.os.replace", side_effect=PermissionError("read only")):
                with self.assertRaises(PermissionError):
                    settings.save_language("zh_CN")
            self.assertEqual(settings.language(), "en")
            self.assertEqual(list(Path(directory).iterdir()), [settings.path])


if __name__ == "__main__":
    unittest.main()
