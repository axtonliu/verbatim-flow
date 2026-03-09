import unittest
from verbatim_flow.qwen_transcriber import _resolve_language, _contains_cjk, _convert_s2t, _model_cache_path


class TestResolveLanguage(unittest.TestCase):
    def test_zh_hant(self):
        self.assertEqual(_resolve_language("zh-Hant"), ("Chinese", True))

    def test_zh_hans(self):
        self.assertEqual(_resolve_language("zh-Hans"), ("Chinese", False))

    def test_zh_bare(self):
        self.assertEqual(_resolve_language("zh"), ("Chinese", True))

    def test_en(self):
        self.assertEqual(_resolve_language("en"), ("English", False))

    def test_en_us(self):
        self.assertEqual(_resolve_language("en-US"), ("English", False))

    def test_none(self):
        self.assertEqual(_resolve_language(None), (None, None))

    def test_yue(self):
        self.assertEqual(_resolve_language("yue"), ("Cantonese", True))

    def test_ja(self):
        self.assertEqual(_resolve_language("ja"), ("Japanese", False))


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
        path = _model_cache_path("mlx-community/Qwen3-ASR-0.6B-8bit")
        self.assertEqual(path.name, "models--mlx-community--Qwen3-ASR-0.6B-8bit")
        self.assertTrue(str(path).endswith("huggingface/hub/models--mlx-community--Qwen3-ASR-0.6B-8bit"))
