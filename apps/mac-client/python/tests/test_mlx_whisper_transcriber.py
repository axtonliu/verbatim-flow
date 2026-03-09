import unittest
from verbatim_flow.mlx_whisper_transcriber import (
    _resolve_language, _contains_cjk, _convert_s2t, _model_cache_path,
    _normalize_cjk_punctuation,
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


class TestNormalizeCjkPunctuation(unittest.TestCase):
    def test_comma_space(self):
        self.assertEqual(_normalize_cjk_punctuation("你好, 世界"), "你好，世界")

    def test_period_space(self):
        self.assertEqual(_normalize_cjk_punctuation("你好. 世界"), "你好。世界")

    def test_question_mark_space(self):
        self.assertEqual(_normalize_cjk_punctuation("你好? 世界"), "你好？世界")

    def test_exclamation_space(self):
        self.assertEqual(_normalize_cjk_punctuation("你好! 世界"), "你好！世界")

    def test_colon_space(self):
        self.assertEqual(_normalize_cjk_punctuation("標題: 內容"), "標題：內容")

    def test_semicolon_space(self):
        self.assertEqual(_normalize_cjk_punctuation("前句; 後句"), "前句；後句")

    def test_trailing_comma(self):
        self.assertEqual(_normalize_cjk_punctuation("你好,"), "你好，")

    def test_trailing_period(self):
        self.assertEqual(_normalize_cjk_punctuation("你好."), "你好。")

    def test_trailing_question(self):
        self.assertEqual(_normalize_cjk_punctuation("你好?"), "你好？")

    def test_trailing_exclamation(self):
        self.assertEqual(_normalize_cjk_punctuation("你好!"), "你好！")

    def test_decimal_preserved(self):
        self.assertEqual(_normalize_cjk_punctuation("溫度是3.5度"), "溫度是3.5度")

    def test_number_comma_preserved(self):
        self.assertEqual(_normalize_cjk_punctuation("共3,000人"), "共3,000人")

    def test_mixed_sentence(self):
        self.assertEqual(
            _normalize_cjk_punctuation("今天天氣很好, 我們去公園. 你覺得呢?"),
            "今天天氣很好，我們去公園。你覺得呢？"
        )

    def test_english_unchanged(self):
        self.assertEqual(
            _normalize_cjk_punctuation("Hello, world. How are you?"),
            "Hello, world. How are you?"
        )

    def test_comma_no_space(self):
        self.assertEqual(_normalize_cjk_punctuation("你好,世界"), "你好，世界")

    def test_question_no_space(self):
        self.assertEqual(_normalize_cjk_punctuation("你好?世界"), "你好？世界")

    def test_period_no_space(self):
        self.assertEqual(_normalize_cjk_punctuation("你好.世界"), "你好。世界")

    def test_exclamation_no_space(self):
        self.assertEqual(_normalize_cjk_punctuation("你好!世界"), "你好！世界")

    def test_comma_multiple_spaces(self):
        self.assertEqual(_normalize_cjk_punctuation("你好,  世界"), "你好，世界")

    def test_multiple_commas_no_space(self):
        self.assertEqual(
            _normalize_cjk_punctuation("我说,你听,他看"),
            "我说，你听，他看"
        )

    def test_all_no_space(self):
        self.assertEqual(
            _normalize_cjk_punctuation("你好,世界.今天天气很好,我们去公园?好!"),
            "你好，世界。今天天气很好，我们去公园？好！"
        )

    def test_already_fullwidth(self):
        self.assertEqual(
            _normalize_cjk_punctuation("你好，世界。"),
            "你好，世界。"
        )

    def test_empty(self):
        self.assertEqual(_normalize_cjk_punctuation(""), "")


class TestModelCachePath(unittest.TestCase):
    def test_cache_path_format(self):
        path = _model_cache_path("mlx-community/whisper-large-v3-mlx")
        self.assertEqual(path.name, "models--mlx-community--whisper-large-v3-mlx")
        self.assertTrue(str(path).endswith(
            "huggingface/hub/models--mlx-community--whisper-large-v3-mlx"
        ))
