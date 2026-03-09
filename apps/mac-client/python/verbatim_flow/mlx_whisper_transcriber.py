from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import sys


@dataclass(frozen=True)
class TranscriptResult:
    text: str


# Whisper uses ISO 639-1 codes directly (not language names like Qwen/mlx-audio).
_LANGUAGE_MAP: dict[str, str] = {
    "zh": "zh",
    "en": "en",
    "de": "de",
    "es": "es",
    "fr": "fr",
    "it": "it",
    "pt": "pt",
    "ru": "ru",
    "ko": "ko",
    "ja": "ja",
    "yue": "yue",
}

# Languages whose model output may need Simplified → Traditional conversion.
_TRADITIONAL_CHINESE_CODES = {"zh", "yue"}

# Locale suffixes that indicate Traditional Chinese.
_TRADITIONAL_SUFFIXES = {"hant", "tw", "hk", "mo"}


def _resolve_language(code: str | None) -> tuple[str | None, bool | None]:
    """Resolve locale code to (whisper_language_code, should_convert_to_traditional).

    Returns (None, None) when code is None (auto-detect mode).
    """
    if code is None:
        return (None, None)
    parts = code.replace("_", "-").lower().split("-")
    prefix = parts[0]
    whisper_lang = _LANGUAGE_MAP.get(prefix)
    if whisper_lang is None:
        return (None, False)
    if whisper_lang in _TRADITIONAL_CHINESE_CODES:
        has_traditional_suffix = any(p in _TRADITIONAL_SUFFIXES for p in parts[1:])
        has_simplified_suffix = any(p in {"hans", "cn"} for p in parts[1:])
        convert = has_traditional_suffix or (not has_simplified_suffix)
        return (whisper_lang, convert)
    return (whisper_lang, False)


def _contains_cjk(text: str) -> bool:
    """Return True if *text* contains CJK Unified Ideograph characters."""
    return any("\u4e00" <= ch <= "\u9fff" for ch in text)


_HW_TO_FW: dict[str, str] = {
    ",": "，",
    ".": "。",
    "?": "？",
    "!": "！",
    ":": "：",
    ";": "；",
}


def _normalize_cjk_punctuation(text: str) -> str:
    """Replace half-width punctuation with full-width equivalents in CJK text.

    Handles punctuation followed by space, no space, multiple spaces, or at
    end-of-string.  Decimal/thousands patterns (e.g. 3.5, 3,000) are preserved
    via negative look-behind/ahead for digits.
    """
    if not _contains_cjk(text):
        return text
    import re
    for hw, fw in _HW_TO_FW.items():
        escaped = re.escape(hw)
        if hw in (".", ","):
            # Protect digit-punct-digit patterns (decimals, thousands).
            text = re.sub(rf"(?<!\d){escaped}(?!\d)\s*", fw, text)
        else:
            text = re.sub(rf"{escaped}\s*", fw, text)
    return text


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


class MlxWhisperTranscriber:
    DEFAULT_MODEL = "mlx-community/whisper-large-v3-mlx"

    def __init__(self, model: str = DEFAULT_MODEL) -> None:
        self.model_name = model

    def _ensure_model(self) -> None:
        import os
        cached = _model_cache_path(self.model_name).exists()
        if not cached:
            os.environ["HF_HUB_OFFLINE"] = "0"
            print(f"[info] Downloading model {self.model_name}...", file=sys.stderr)

    def transcribe(self, audio_path: str, language: str | None = None,
                   output_locale: str | None = None) -> TranscriptResult:
        self._ensure_model()
        import mlx_whisper

        whisper_lang, convert_trad = _resolve_language(language)

        prompt = None
        if whisper_lang in _TRADITIONAL_CHINESE_CODES:
            prompt = "以下是普通話的句子，請使用全形標點符號。"

        result = mlx_whisper.transcribe(
            audio_path,
            path_or_hf_repo=self.model_name,
            language=whisper_lang,
            word_timestamps=False,
            initial_prompt=prompt,
        )
        text = result.get("text", "").strip()

        # Auto-detect mode: infer language from output.
        detected_lang = whisper_lang
        if detected_lang is None:
            info = result.get("language")
            if info and info in ("zh", "chinese", "yue", "cantonese"):
                detected_lang = "zh"

        # Fallback: CJK character heuristic.
        if detected_lang is None and _contains_cjk(text):
            detected_lang = "zh"

        # Decide s2t conversion in auto-detect mode.
        if convert_trad is None and detected_lang in _TRADITIONAL_CHINESE_CODES:
            if output_locale:
                _, convert_trad = _resolve_language(output_locale)
            else:
                convert_trad = True

        if detected_lang in _TRADITIONAL_CHINESE_CODES:
            text = _normalize_cjk_punctuation(text)

        if convert_trad and detected_lang in _TRADITIONAL_CHINESE_CODES:
            text = _convert_s2t(text)

        return TranscriptResult(text=text)
