# MLX Whisper + Large V3 Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add mlx-whisper with Whisper Large V3 as the fifth ASR engine in VerbatimFlow.

**Architecture:** Independent Python transcriber class + CLI script (same pattern as Qwen3). Swift side adds a new `RecognitionEngine.mlxWhisper` case threaded through CLIConfig → AppController → SpeechTranscriber → MenuBarApp.

**Tech Stack:** mlx-whisper (Python), opencc (s2t), Swift 5.9+ (SPM), NSMenu

---

### Task 1: Python — MlxWhisperTranscriber class with tests

**Files:**
- Create: `apps/mac-client/python/verbatim_flow/mlx_whisper_transcriber.py`
- Create: `apps/mac-client/python/tests/test_mlx_whisper_transcriber.py`

**Step 1: Write the failing tests**

```python
# tests/test_mlx_whisper_transcriber.py
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
```

**Step 2: Run tests to verify they fail**

Run: `cd apps/mac-client/python && python -m pytest tests/test_mlx_whisper_transcriber.py -v`
Expected: FAIL with `ModuleNotFoundError: No module named 'verbatim_flow.mlx_whisper_transcriber'`

**Step 3: Write minimal implementation**

```python
# verbatim_flow/mlx_whisper_transcriber.py
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

        result = mlx_whisper.transcribe(
            audio_path,
            path_or_hf_repo=self.model_name,
            language=whisper_lang,
            word_timestamps=False,
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

        if convert_trad and detected_lang in _TRADITIONAL_CHINESE_CODES:
            text = _convert_s2t(text)

        return TranscriptResult(text=text)
```

**Step 4: Run tests to verify they pass**

Run: `cd apps/mac-client/python && python -m pytest tests/test_mlx_whisper_transcriber.py -v`
Expected: All 12 tests PASS

**Step 5: Commit**

```bash
git add apps/mac-client/python/verbatim_flow/mlx_whisper_transcriber.py apps/mac-client/python/tests/test_mlx_whisper_transcriber.py
git commit -m "feat(mlx-whisper): add MlxWhisperTranscriber class with tests"
```

---

### Task 2: Python — CLI entry point script

**Files:**
- Create: `apps/mac-client/python/scripts/transcribe_mlx_whisper.py`

**Step 1: Write the CLI entry point**

```python
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
```

**Step 2: Verify script is parseable**

Run: `cd apps/mac-client/python && python -c "import ast; ast.parse(open('scripts/transcribe_mlx_whisper.py').read()); print('OK')"`
Expected: `OK`

**Step 3: Commit**

```bash
git add apps/mac-client/python/scripts/transcribe_mlx_whisper.py
git commit -m "feat(mlx-whisper): add CLI entry point script"
```

---

### Task 3: Python — Add mlx-whisper to requirements.txt

**Files:**
- Modify: `apps/mac-client/python/requirements.txt`

**Step 1: Add dependency**

Add `mlx-whisper>=0.4.0` to requirements.txt (after the mlx-audio line).

**Step 2: Install dependency**

Run: `cd apps/mac-client/python && .venv/bin/pip install mlx-whisper`

**Step 3: Verify import works**

Run: `cd apps/mac-client/python && .venv/bin/python -c "import mlx_whisper; print('OK')"`
Expected: `OK`

**Step 4: Commit**

```bash
git add apps/mac-client/python/requirements.txt
git commit -m "feat(mlx-whisper): add mlx-whisper dependency"
```

---

### Task 4: Swift — CLIConfig + AppError

**Files:**
- Modify: `apps/mac-client/Sources/VerbatimFlow/CLIConfig.swift`
- Modify: `apps/mac-client/Sources/VerbatimFlow/AppError.swift`

**Step 1: Add `mlxWhisper` to RecognitionEngine enum**

In `CLIConfig.swift`, add case to enum (line ~14, after `case qwen`):

```swift
case mlxWhisper = "mlx-whisper"
```

Add to `displayName` switch (after `case .qwen:`):

```swift
case .mlxWhisper:
    return "MLX Whisper"
```

**Step 2: Update `parse()` error message**

Update the `--engine` guard message (line ~156) to include `mlx-whisper`:

```swift
throw ConfigError.invalidValue("--engine", "apple | whisper | openai | qwen | mlx-whisper")
```

**Step 3: Update `HelpPrinter`**

Update the Usage line (line ~235) to include `mlx-whisper` in the engine list.

**Step 4: Add AppError cases**

In `AppError.swift`, add (after `case qwenTranscriptionFailed`):

```swift
case mlxWhisperScriptNotFound
case mlxWhisperTranscriptionFailed(String)
```

Add description cases:

```swift
case .mlxWhisperScriptNotFound:
    return "MLX Whisper script not found. Expected apps/mac-client/python/scripts/transcribe_mlx_whisper.py or Contents/Resources/python/scripts/transcribe_mlx_whisper.py."
case .mlxWhisperTranscriptionFailed(let details):
    if details.isEmpty {
        return "MLX Whisper transcription failed"
    }
    return "MLX Whisper transcription failed: \(details)"
```

**Step 5: Verify build**

Run: `cd apps/mac-client && swift build 2>&1 | tail -5`
Expected: Build errors for exhaustive switch statements (expected — we fix those in next tasks)

**Step 6: Commit**

```bash
git add apps/mac-client/Sources/VerbatimFlow/CLIConfig.swift apps/mac-client/Sources/VerbatimFlow/AppError.swift
git commit -m "feat(mlx-whisper): add RecognitionEngine.mlxWhisper and AppError cases"
```

---

### Task 5: Swift — SpeechTranscriber

**Files:**
- Modify: `apps/mac-client/Sources/VerbatimFlow/SpeechTranscriber.swift`

**Step 1: Add `.mlxWhisper` to `startRecording()` switch**

In `startRecording()` (line ~71), change:

```swift
case .whisper, .openai, .qwen:
```

to:

```swift
case .whisper, .openai, .qwen, .mlxWhisper:
```

**Step 2: Add `.mlxWhisper` to `stopRecording()` switch**

Add case (after `case .qwen:`, line ~85):

```swift
case .mlxWhisper:
    return try await stopMlxWhisperRecording()
```

**Step 3: Add `stopMlxWhisperRecording()` method**

Add after `stopQwenRecording()` (after line ~393). Pattern mirrors `stopQwenRecording()`:

```swift
private func stopMlxWhisperRecording() async throws -> String {
    guard let recorder = audioRecorder, let recordingURL = recordedAudioURL else {
        return ""
    }

    let durationSec = recorder.currentTime
    recorder.stop()

    audioRecorder = nil
    recordedAudioURL = nil

    if durationSec < 0.18 {
        try? FileManager.default.removeItem(at: recordingURL)
        return ""
    }

    let languageCode = Self.mlxWhisperLanguageParam(from: localeIdentifier, isAutoDetect: languageIsAutoDetect)
    let outputLocale: String? = (languageCode == nil) ? localeIdentifier : nil

    do {
        let transcript = try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let text = try Self.transcribeMlxWhisperAudioFile(
                        audioURL: recordingURL,
                        languageCode: languageCode,
                        outputLocale: outputLocale
                    )
                    continuation.resume(returning: text)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
        try? FileManager.default.removeItem(at: recordingURL)
        return transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    } catch {
        persistFailedRecording(audioURL: recordingURL, durationSec: durationSec)
        throw error
    }
}
```

**Step 4: Add `transcribeMlxWhisperAudioFile()` static method**

Add after `transcribeQwenAudioFile()`. Pattern mirrors it but uses `transcribe_mlx_whisper.py` and hard-coded model:

```swift
private nonisolated static func transcribeMlxWhisperAudioFile(
    audioURL: URL,
    languageCode: String?,
    outputLocale: String? = nil
) throws -> String {
    guard let scriptURL = resolveMlxWhisperScriptURL() else {
        throw AppError.mlxWhisperScriptNotFound
    }

    let process = Process()
    let outputPipe = Pipe()
    let errorPipe = Pipe()

    if let pythonURL = resolvePythonExecutable(scriptURL: scriptURL) {
        process.executableURL = pythonURL
        process.arguments = [
            scriptURL.path,
            "--audio",
            audioURL.path,
        ]
    } else {
        throw AppError.pythonRuntimeNotFound
    }

    if let languageCode, !languageCode.isEmpty {
        process.arguments?.append(contentsOf: ["--language", languageCode])
    }
    if let outputLocale, !outputLocale.isEmpty {
        process.arguments?.append(contentsOf: ["--output-locale", outputLocale])
    }

    // Ensure Homebrew tools (ffmpeg) are reachable for audio decoding.
    var env = ProcessInfo.processInfo.environment
    let currentPath = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
    let homebrewPaths = ["/opt/homebrew/bin", "/usr/local/bin"]
    let missingPaths = homebrewPaths.filter { !currentPath.contains($0) }
    if !missingPaths.isEmpty {
        env["PATH"] = (missingPaths + [currentPath]).joined(separator: ":")
    }
    process.environment = env

    process.standardOutput = outputPipe
    process.standardError = errorPipe

    let (outputText, errorText) = try runSubprocess(process, outputPipe: outputPipe, errorPipe: errorPipe)

    if process.terminationStatus != 0 {
        let details = errorText.isEmpty ? outputText : errorText
        throw AppError.mlxWhisperTranscriptionFailed(details)
    }

    return outputText
}
```

**Step 5: Add `resolveMlxWhisperScriptURL()`**

```swift
private nonisolated static func resolveMlxWhisperScriptURL() -> URL? {
    resolveScript(named: "transcribe_mlx_whisper.py")
}
```

**Step 6: Add `mlxWhisperLanguageParam()` helper**

Reuses same logic as `qwenLanguageParam()`:

```swift
private nonisolated static func mlxWhisperLanguageParam(
    from localeIdentifier: String,
    isAutoDetect: Bool
) -> String? {
    if isAutoDetect { return nil }
    let lowercased = localeIdentifier.lowercased()
    if lowercased.isEmpty { return nil }
    // Pass full locale for zh variants so Python can distinguish Hant/Hans.
    if lowercased.hasPrefix("zh") {
        return localeIdentifier
    }
    // For non-Chinese locales, pass just the language prefix.
    return Locale(identifier: localeIdentifier).language.languageCode?.identifier
}
```

**Step 7: Add `.mlxWhisper` to `retryLastFailedRecording()` switch**

Add case (after `case .qwen:`, around line ~161):

```swift
case .mlxWhisper:
    let languageCode = Self.mlxWhisperLanguageParam(from: entry.localeIdentifier, isAutoDetect: languageIsAutoDetect)
    let outputLocale: String? = (languageCode == nil) ? entry.localeIdentifier : nil
    transcript = try await withCheckedThrowingContinuation { continuation in
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let text = try Self.transcribeMlxWhisperAudioFile(
                    audioURL: entry.audioFileURL,
                    languageCode: languageCode,
                    outputLocale: outputLocale
                )
                continuation.resume(returning: text)
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
```

**Step 8: Add `.mlxWhisper` to `ensurePermissions()` speech check**

In `ensurePermissions()` (line ~60), change:

```swift
let speechAuthorized = recognitionEngine == .apple ? await resolveSpeechAuthorization() : true
```

No change needed — `.mlxWhisper` is already covered by the `else` clause. Just verify.

**Step 9: Commit**

```bash
git add apps/mac-client/Sources/VerbatimFlow/SpeechTranscriber.swift
git commit -m "feat(mlx-whisper): add SpeechTranscriber mlxWhisper routing and subprocess"
```

---

### Task 6: Swift — AppController

**Files:**
- Modify: `apps/mac-client/Sources/VerbatimFlow/AppController.swift`

**Step 1: Update `start()` log line**

No structural change needed — the log line (line ~144) already uses `recognitionEngine.rawValue` which will naturally include `mlx-whisper`. Just verify it compiles.

**Step 2: Verify build compiles**

Run: `cd apps/mac-client && swift build 2>&1 | tail -5`
Expected: May still have errors in MenuBarApp.swift (next task)

**Step 3: Commit (if changes needed)**

If no changes are needed, skip this commit.

---

### Task 7: Swift — MenuBarApp

**Files:**
- Modify: `apps/mac-client/Sources/VerbatimFlow/MenuBarApp.swift`

**Step 1: Add engine menu item declaration**

After `engineQwenItem` (line ~70), add:

```swift
private lazy var engineMlxWhisperItem = NSMenuItem(
    title: "MLX Whisper",
    action: #selector(setEngineMlxWhisper),
    keyEquivalent: ""
)
```

**Step 2: Add menu item to engine submenu**

In the menu assembly section (after line ~348 `engineSubmenu.addItem(engineQwenItem)`), add:

```swift
engineSubmenu.addItem(engineMlxWhisperItem)
```

**Step 3: Add `@objc` setter**

After `setEngineQwen()` (line ~752):

```swift
@objc
private func setEngineMlxWhisper() {
    setRecognitionEngine(.mlxWhisper)
}
```

**Step 4: Update `refreshEngineChecks()`**

Add state check (after `engineQwenItem.state`, line ~603):

```swift
engineMlxWhisperItem.state = currentEngine == .mlxWhisper ? .on : .off
```

**Step 5: Verify full build**

Run: `cd apps/mac-client && swift build 2>&1 | tail -5`
Expected: Build succeeded

**Step 6: Commit**

```bash
git add apps/mac-client/Sources/VerbatimFlow/MenuBarApp.swift
git commit -m "feat(mlx-whisper): add MLX Whisper engine menu item"
```

---

### Task 8: Build verification and smoke test

**Step 1: Run full build**

Run: `cd apps/mac-client && swift build 2>&1 | tail -10`
Expected: Build succeeded

**Step 2: Run Python tests**

Run: `cd apps/mac-client/python && python -m pytest tests/test_mlx_whisper_transcriber.py tests/test_qwen_transcriber.py -v`
Expected: All tests pass (both mlx-whisper and qwen — ensure no regressions)

**Step 3: Verify CLI script help**

Run: `cd apps/mac-client/python && .venv/bin/python scripts/transcribe_mlx_whisper.py --help`
Expected: Shows usage with `--audio`, `--model`, `--language`, `--output-locale`

**Step 4: Final commit (if any fixups needed)**

Only commit if build/test fixes were required.
