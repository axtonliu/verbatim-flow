from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
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

# Languages whose model output may need Simplified → Traditional conversion.
_TRADITIONAL_CHINESE_LANGUAGES = {"Chinese", "Cantonese"}

# Locale suffixes that indicate Traditional Chinese.
_TRADITIONAL_SUFFIXES = {"hant", "tw", "hk", "mo"}


def _resolve_language(code: str | None) -> tuple[str | None, bool | None]:
    """Resolve locale code to (model_language, should_convert_to_traditional).

    Returns (None, None) when code is None (auto-detect mode).
    """
    if code is None:
        return (None, None)
    parts = code.replace("_", "-").lower().split("-")
    prefix = parts[0]
    model_lang = _LANGUAGE_MAP.get(prefix)
    if model_lang is None:
        return (model_lang, False)
    if model_lang in _TRADITIONAL_CHINESE_LANGUAGES:
        has_traditional_suffix = any(p in _TRADITIONAL_SUFFIXES for p in parts[1:])
        has_simplified_suffix = any(p in {"hans", "cn"} for p in parts[1:])
        convert = has_traditional_suffix or (not has_simplified_suffix)
        return (model_lang, convert)
    return (model_lang, False)


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


def _model_cache_path(model_id: str) -> Path:
    """Return expected HuggingFace cache directory for a model."""
    org_model = model_id.replace("/", "--")
    return Path.home() / ".cache" / "huggingface" / "hub" / f"models--{org_model}"


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
            import os
            from mlx_audio.stt import load

            cached = _model_cache_path(self.model_name).exists()
            if not cached:
                os.environ["HF_HUB_OFFLINE"] = "0"
                print(f"[info] Downloading model {self.model_name}...", file=sys.stderr)

            self._model = load(self.model_name)
            _patch_auto_detect(self._model)

            if not cached:
                os.environ["HF_HUB_OFFLINE"] = "1"

    def transcribe(self, audio_path: str, language: str | None = None,
                   output_locale: str | None = None) -> TranscriptResult:
        self._ensure_model()
        model_lang, convert_trad = _resolve_language(language)

        effective_lang = model_lang if model_lang is not None else "__auto__"

        result = self._model.generate(audio_path, language=effective_lang)
        text = result.text.strip() if hasattr(result, "text") else str(result).strip()

        # Auto-detect mode: model may prefix "language Chinese\n" before text.
        if effective_lang == "__auto__":
            for known_lang in ("Chinese", "English", "Cantonese", "Japanese", "Korean"):
                prefix = f"language {known_lang}\n"
                if text.startswith(prefix):
                    model_lang = known_lang
                    text = text[len(prefix):]
                    break

        # Fallback: infer from CJK character presence.
        if model_lang is None and _contains_cjk(text):
            model_lang = "Chinese"

        # Decide s2t conversion in auto-detect mode.
        if convert_trad is None and model_lang in _TRADITIONAL_CHINESE_LANGUAGES:
            if output_locale:
                _, convert_trad = _resolve_language(output_locale)
            else:
                convert_trad = True

        if convert_trad and model_lang in _TRADITIONAL_CHINESE_LANGUAGES:
            text = _convert_s2t(text)

        return TranscriptResult(text=text)
