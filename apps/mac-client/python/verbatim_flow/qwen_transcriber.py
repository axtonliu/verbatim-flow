from __future__ import annotations

from dataclasses import dataclass
import sys


@dataclass(frozen=True)
class TranscriptResult:
    text: str


# Mapping from ISO 639-1 / locale prefix to mlx-audio language name.
_LANGUAGE_MAP: dict[str, str] = {
    "zh": "Chinese",
    "yue": "Cantonese",
    "en": "English",
    "de": "German",
    "es": "Spanish",
    "fr": "French",
    "it": "Italian",
    "pt": "Portuguese",
    "ru": "Russian",
    "ko": "Korean",
    "ja": "Japanese",
}

# Languages whose output should be converted to Traditional Chinese.
_CHINESE_LANGUAGES = {"Chinese", "Cantonese"}


def _resolve_language(code: str | None) -> str | None:
    if code is None:
        return None
    prefix = code.split("-")[0].split("_")[0].lower()
    return _LANGUAGE_MAP.get(prefix)


def _contains_cjk(text: str) -> bool:
    """Return True if *text* contains CJK Unified Ideograph characters."""
    return any("\u4e00" <= ch <= "\u9fff" for ch in text)


def _convert_s2t(text: str) -> str:
    """Convert Simplified Chinese to Traditional Chinese via opencc."""
    try:
        from opencc import OpenCC

        return OpenCC("s2t").convert(text)
    except ImportError:
        return text


def _patch_auto_detect(model) -> None:
    """Monkey-patch _build_prompt to support language=None (auto-detect).

    The upstream mlx-audio always injects ``language <name><asr_text>`` into
    the assistant turn, forcing the model to output in a specific language.
    Qwen3-ASR supports auto-detection by omitting this prefix (the model
    predicts the language token itself).  When *language* is the sentinel
    ``"__auto__"`` we emit a prompt without the language directive.
    """
    import mlx.core as mx

    original_build = model._build_prompt.__func__  # unbound method

    def _patched_build(self, num_audio_tokens: int, language: str = "English") -> mx.array:
        if language == "__auto__":
            prompt = (
                f"<|im_start|>system\n<|im_end|>\n"
                f"<|im_start|>user\n<|audio_start|>{'<|audio_pad|>' * num_audio_tokens}<|audio_end|><|im_end|>\n"
                f"<|im_start|>assistant\n"
            )
            input_ids = self._tokenizer.encode(prompt, return_tensors="np")
            return mx.array(input_ids)
        return original_build(self, num_audio_tokens, language)

    import types
    model._build_prompt = types.MethodType(_patched_build, model)


class QwenTranscriber:
    def __init__(self, model: str = "mlx-community/Qwen3-ASR-0.6B-8bit") -> None:
        self.model_name = model
        self._model = None

    def _ensure_model(self):
        if self._model is None:
            from mlx_audio.stt import load

            self._model = load(self.model_name)
            _patch_auto_detect(self._model)

    def transcribe(self, audio_path: str, language: str | None = None) -> TranscriptResult:
        self._ensure_model()
        lang = _resolve_language(language)

        # Pass "__auto__" sentinel so our patched _build_prompt omits the
        # language directive, enabling Qwen3-ASR auto-detection.
        effective_lang = lang if lang is not None else "__auto__"

        result = self._model.generate(audio_path, language=effective_lang)
        text = result.text.strip() if hasattr(result, "text") else str(result).strip()

        # Auto-detect mode: model may prefix "language Chinese\n" before text.
        # Strip the language line if present.
        if effective_lang == "__auto__":
            for known_lang in ("Chinese", "English", "Cantonese", "Japanese", "Korean"):
                prefix = f"language {known_lang}\n"
                if text.startswith(prefix):
                    lang = known_lang
                    text = text[len(prefix):]
                    break

        # Fallback: if auto-detect didn't yield a language tag (some models
        # skip the prefix), infer from CJK character presence.
        if lang is None and _contains_cjk(text):
            lang = "Chinese"

        # Convert Simplified → Traditional Chinese when appropriate.
        if lang in _CHINESE_LANGUAGES:
            text = _convert_s2t(text)

        return TranscriptResult(text=text)
