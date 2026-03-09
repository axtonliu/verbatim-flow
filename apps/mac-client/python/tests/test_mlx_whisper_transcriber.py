import unittest
from verbatim_flow.mlx_whisper_transcriber import (
    _resolve_language, _contains_cjk, _convert_s2t, _model_cache_path,
)


class TestResolveLanguage(unittest.TestCase):
    def test_zh_hant(self):
        self.assertEqual(_resolve_language("zh-Hant"), ("zh", True))

    def test_zh_hans(self):
        self.assertEqual(_resolve_language("zh-Hans"), ("zh", False))

    def test_zh_bare(self):
        self.assertEqual(_resolve_language("zh"), ("zh", True))

    def test_en(self):
        self.assertEqual(_resolve_language("en"), ("en", False))

    def test_en_us(self):
        self.assertEqual(_resolve_language("en-US"), ("en", False))

    def test_none(self):
        self.assertEqual(_resolve_language(None), (None, None))

    def test_ja(self):
        self.assertEqual(_resolve_language("ja"), ("ja", False))

    def test_unknown_language(self):
        self.assertEqual(_resolve_language("xx"), (None, False))


class TestContainsCjk(unittest.TestCase):
    def test_chinese_text(self):
        self.assertTrue(_contains_cjk("你好世界"))

    def test_english_text(self):
        self.assertFalse(_contains_cjk("hello world"))

    def test_mixed(self):
        self.assertTrue(_contains_cjk("hello 你好"))


class TestConvertS2T(unittest.TestCase):
    def test_simplified_to_traditional(self):
        result = _convert_s2t("简体中文")
        self.assertEqual(result, "簡體中文")

    def test_english_unchanged(self):
        self.assertEqual(_convert_s2t("hello"), "hello")


class TestModelCachePath(unittest.TestCase):
    def test_cache_path_format(self):
        path = _model_cache_path("mlx-community/whisper-large-v3-mlx")
        self.assertEqual(path.name, "models--mlx-community--whisper-large-v3-mlx")
        self.assertTrue(str(path).endswith(
            "huggingface/hub/models--mlx-community--whisper-large-v3-mlx"
        ))
