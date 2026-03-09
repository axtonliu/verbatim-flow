#!/usr/bin/env python3
from __future__ import annotations

import argparse
from pathlib import Path
import sys


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Transcribe one audio file with mlx-whisper (Whisper Large V3)"
    )
    parser.add_argument("--audio", required=True, help="Path to the audio file")
    parser.add_argument(
        "--model",
        default="mlx-community/whisper-large-v3-mlx",
        help="HuggingFace model ID for mlx-whisper",
    )
    parser.add_argument("--language", default=None,
                        help="Language code (zh, en, zh-Hant, zh-Hans, ...)")
    parser.add_argument("--output-locale", default=None,
                        help="Locale hint for output script (e.g. zh-Hant for Traditional Chinese)")
    return parser.parse_args()


def normalize_language(value: str | None) -> str | None:
    if value is None:
        return None
    normalized = value.strip().lower()
    if not normalized or normalized in {"auto", "system"}:
        return None
    return normalized


def main() -> int:
    args = parse_args()
    script_path = Path(__file__).resolve()
    python_root = script_path.parents[1]
    sys.path.insert(0, str(python_root))

    audio_path = Path(args.audio).expanduser().resolve()
    if not audio_path.exists():
        print(f"[error] audio file not found: {audio_path}", file=sys.stderr)
        return 2

    from verbatim_flow.mlx_whisper_transcriber import MlxWhisperTranscriber

    transcriber = MlxWhisperTranscriber(model=args.model)
    result = transcriber.transcribe(
        str(audio_path),
        language=normalize_language(args.language),
        output_locale=args.output_locale,
    )
    text = result.text.strip()
    if text:
        sys.stdout.write(text)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
