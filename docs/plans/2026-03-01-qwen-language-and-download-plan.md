# Qwen3 ASR Language & Download Redesign — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Restore user language settings for Qwen engine, add zh-Hant menu option, and enable automatic model download for new users.

**Architecture:** Python side owns language→model mapping, s2t conversion logic, and HF cache/download decisions. Swift side passes user's locale selection through to Python CLI args. Menu bar adds zh-Hant as a fourth language option.

**Tech Stack:** Swift 5.9 (SPM), Python 3.14, mlx-audio, opencc-python-reimplemented, huggingface_hub

---

### Task 1: Python — Refactor `_resolve_language()` to return conversion flag

**Files:**
- Modify: `apps/mac-client/python/verbatim_flow/qwen_transcriber.py`
- Create: `apps/mac-client/python/tests/test_qwen_transcriber.py`

**Step 1: Write failing tests**

Create `apps/mac-client/python/tests/test_qwen_transcriber.py`:

```python
import unittest
from verbatim_flow.qwen_transcriber import _resolve_language, _contains_cjk, _convert_s2t


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
```

**Step 2: Run tests to verify they fail**

Run: `cd apps/mac-client/python && .venv/bin/python -m unittest tests/test_qwen_transcriber.py -v`
Expected: FAIL — `_resolve_language` currently returns `str | None`, not a tuple.

**Step 3: Implement the refactored `_resolve_language()`**

In `qwen_transcriber.py`, replace the existing `_resolve_language` function and update `_CHINESE_LANGUAGES`:

```python
# Languages whose output should be converted to Traditional Chinese.
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
    # Determine Traditional Chinese conversion.
    if model_lang in _TRADITIONAL_CHINESE_LANGUAGES:
        # zh-Hant → True, zh-Hans → False, zh (bare) → True (default)
        has_traditional_suffix = any(p in _TRADITIONAL_SUFFIXES for p in parts[1:])
        has_simplified_suffix = any(p in {"hans", "cn"} for p in parts[1:])
        convert = has_traditional_suffix or (not has_simplified_suffix)
        return (model_lang, convert)
    return (model_lang, False)
```

**Step 4: Update `transcribe()` to use new return format**

Replace the transcribe method body:

```python
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
        # Use output_locale hint if provided, else default to Traditional.
        if output_locale:
            _, convert_trad = _resolve_language(output_locale)
        else:
            convert_trad = True

    if convert_trad and model_lang in _TRADITIONAL_CHINESE_LANGUAGES:
        text = _convert_s2t(text)

    return TranscriptResult(text=text)
```

Also remove the old `_CHINESE_LANGUAGES` set.

**Step 5: Run tests to verify they pass**

Run: `cd apps/mac-client/python && .venv/bin/python -m unittest tests/test_qwen_transcriber.py -v`
Expected: All PASS

**Step 6: Commit**

```bash
git add apps/mac-client/python/verbatim_flow/qwen_transcriber.py apps/mac-client/python/tests/test_qwen_transcriber.py
git commit -m "refactor(qwen): _resolve_language returns (model_lang, convert_traditional) tuple"
```

---

### Task 2: Python — Add `--output-locale` to CLI script

**Files:**
- Modify: `apps/mac-client/python/scripts/transcribe_qwen.py`

**Step 1: Add `--output-locale` argument and pass to transcriber**

In `transcribe_qwen.py`, add to `parse_args()`:

```python
parser.add_argument("--output-locale", default=None,
                    help="Locale hint for output script (e.g. zh-Hant for Traditional Chinese)")
```

In `main()`, change the transcribe call:

```python
result = transcriber.transcribe(
    str(audio_path),
    language=normalize_language(args.language),
    output_locale=args.output_locale,
)
```

**Step 2: Verify CLI works**

Run: `cd apps/mac-client/python && .venv/bin/python scripts/transcribe_qwen.py --help`
Expected: Shows `--output-locale` in help output.

**Step 3: Commit**

```bash
git add apps/mac-client/python/scripts/transcribe_qwen.py
git commit -m "feat(qwen): add --output-locale CLI arg for Traditional/Simplified control"
```

---

### Task 3: Python — Auto-download model on first use

**Files:**
- Modify: `apps/mac-client/python/verbatim_flow/qwen_transcriber.py`
- Modify: `apps/mac-client/python/tests/test_qwen_transcriber.py`

**Step 1: Write failing test**

Add to `test_qwen_transcriber.py`:

```python
class TestModelCachePath(unittest.TestCase):
    def test_cache_path_format(self):
        from verbatim_flow.qwen_transcriber import _model_cache_path
        path = _model_cache_path("mlx-community/Qwen3-ASR-0.6B-8bit")
        self.assertTrue(path.name == "models--mlx-community--Qwen3-ASR-0.6B-8bit")
        self.assertTrue(str(path).endswith("huggingface/hub/models--mlx-community--Qwen3-ASR-0.6B-8bit"))
```

**Step 2: Run test to verify it fails**

Run: `cd apps/mac-client/python && .venv/bin/python -m unittest tests/test_qwen_transcriber.py::TestModelCachePath -v`
Expected: FAIL — `_model_cache_path` not defined.

**Step 3: Implement cache check and auto-download in `_ensure_model()`**

Add helper function and update `_ensure_model()`:

```python
from pathlib import Path

def _model_cache_path(model_id: str) -> Path:
    """Return expected HuggingFace cache directory for a model."""
    org_model = model_id.replace("/", "--")
    return Path.home() / ".cache" / "huggingface" / "hub" / f"models--{org_model}"


# In QwenTranscriber class:
def _ensure_model(self):
    if self._model is None:
        import os, sys
        from mlx_audio.stt import load

        cached = _model_cache_path(self.model_name).exists()
        if not cached:
            os.environ["HF_HUB_OFFLINE"] = "0"
            print(f"[info] Downloading model {self.model_name}...", file=sys.stderr)

        self._model = load(self.model_name)
        _patch_auto_detect(self._model)

        if not cached:
            os.environ["HF_HUB_OFFLINE"] = "1"
```

**Step 4: Run tests**

Run: `cd apps/mac-client/python && .venv/bin/python -m unittest tests/test_qwen_transcriber.py -v`
Expected: All PASS

**Step 5: Commit**

```bash
git add apps/mac-client/python/verbatim_flow/qwen_transcriber.py apps/mac-client/python/tests/test_qwen_transcriber.py
git commit -m "feat(qwen): auto-download model on first use, cache for offline"
```

---

### Task 4: Swift — Restore language passing and remove HF_HUB_OFFLINE

**Files:**
- Modify: `apps/mac-client/Sources/VerbatimFlow/SpeechTranscriber.swift`

**Step 1: Add `qwenLanguageParam()` function**

Add after `whisperLanguageCode()` (around line 865):

```swift
private nonisolated static func qwenLanguageParam(from localeIdentifier: String) -> String? {
    let lowercased = localeIdentifier.lowercased()
    if lowercased == "system" || lowercased.isEmpty {
        return nil
    }
    // Pass full locale for zh variants so Python can distinguish Hant/Hans.
    if lowercased.hasPrefix("zh") {
        return localeIdentifier
    }
    // For non-Chinese locales, pass just the language prefix.
    return Locale(identifier: localeIdentifier).language.languageCode?.identifier
}
```

**Step 2: Update `stopQwenRecording()` to pass language**

Change `languageCode: nil` to use the new function (around line 358-367):

```swift
let modelId = qwenModel.rawValue
let languageCode = Self.qwenLanguageParam(from: localeIdentifier)
let outputLocale: String? = (languageCode == nil) ? localeIdentifier : nil
```

And update the call:

```swift
let text = try Self.transcribeQwenAudioFile(
    audioURL: recordingURL,
    model: modelId,
    languageCode: languageCode,
    outputLocale: outputLocale
)
```

**Step 3: Update retry path**

In `retryLastFailedRecording()` Qwen branch (around line 137):

```swift
case .qwen:
    let qwenModelId = entry.qwenModelRawValue ?? QwenModel.small.rawValue
    let languageCode = Self.qwenLanguageParam(from: entry.localeIdentifier)
    let outputLocale: String? = (languageCode == nil) ? entry.localeIdentifier : nil
    transcript = try await withCheckedThrowingContinuation { continuation in
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let text = try Self.transcribeQwenAudioFile(
                    audioURL: entry.audioFileURL,
                    model: qwenModelId,
                    languageCode: languageCode,
                    outputLocale: outputLocale
                )
```

**Step 4: Update `transcribeQwenAudioFile()` signature and body**

Add `outputLocale` parameter. Remove `env["HF_HUB_OFFLINE"] = "1"`. Remove debug diagnostics. Pass `--output-locale` arg:

```swift
private nonisolated static func transcribeQwenAudioFile(
    audioURL: URL,
    model: String,
    languageCode: String?,
    outputLocale: String? = nil
) throws -> String {
```

In the arguments section, after the existing `--language` block, add:

```swift
if let outputLocale, !outputLocale.isEmpty {
    process.arguments?.append(contentsOf: ["--output-locale", outputLocale])
}
```

Remove these lines:
```swift
env["HF_HUB_OFFLINE"] = "1"  // DELETE THIS LINE
```

Remove the entire debug diagnostics block (lines 730-744 `let diag = """...`).

**Step 5: Build to verify compilation**

Run: `cd /Users/fredchu/dev/verbatim-flow && bash scripts/build-native-app.sh`
Expected: Build succeeded

**Step 6: Commit**

```bash
git add apps/mac-client/Sources/VerbatimFlow/SpeechTranscriber.swift
git commit -m "feat(qwen): restore language passing, remove HF_HUB_OFFLINE, add outputLocale"
```

---

### Task 5: Swift — Add zh-Hant menu item

**Files:**
- Modify: `apps/mac-client/Sources/VerbatimFlow/MenuBarApp.swift`

**Step 1: Add `languageZhHantItem` declaration**

After `languageZhHansItem` declaration (around line 155):

```swift
private lazy var languageZhHantItem = NSMenuItem(
    title: "Traditional Chinese (zh-Hant)",
    action: #selector(setLanguageZhHant),
    keyEquivalent: ""
)
```

**Step 2: Add target and menu item**

In menu setup (around line 380-388), add:

```swift
languageZhHantItem.target = self
```

And in the submenu, add after `languageZhHansItem`:

```swift
languageSubmenu.addItem(languageZhHantItem)
```

**Step 3: Add `setLanguageZhHant()` method**

After `setLanguageZhHans()` (around line 847):

```swift
@objc
private func setLanguageZhHant() {
    setLanguageSelection("zh-Hant")
}
```

**Step 4: Update `refreshLanguageChecks()`**

Add zh-Hant check (around line 633):

```swift
languageZhHantItem.state = languageSelection == "zh-Hant" ? .on : .off
```

**Step 5: Build to verify**

Run: `cd /Users/fredchu/dev/verbatim-flow && bash scripts/build-native-app.sh`
Expected: Build succeeded

**Step 6: Commit**

```bash
git add apps/mac-client/Sources/VerbatimFlow/MenuBarApp.swift
git commit -m "feat(menu): add Traditional Chinese (zh-Hant) language option"
```

---

### Task 6: Integration — Build, install, and verify all scenarios

**Step 1: Run Python tests**

Run: `cd apps/mac-client/python && .venv/bin/python -m unittest discover -s tests -v`
Expected: All tests PASS

**Step 2: Run Swift tests**

Run: `cd apps/mac-client && swift test`
Expected: All tests PASS

**Step 3: Build and install**

Run: `cd /Users/fredchu/dev/verbatim-flow && bash scripts/build-native-app.sh && rm -rf /Applications/VerbatimFlow.app && cp -R apps/mac-client/dist/VerbatimFlow.app /Applications/ && open /Applications/VerbatimFlow.app`

**Step 4: Manual verification matrix**

| Test | Language Setting | Model | Expected Output |
|------|-----------------|-------|-----------------|
| 1 | zh-Hant | 0.6B | Traditional Chinese |
| 2 | zh-Hant | 1.7B | Traditional Chinese |
| 3 | zh-Hans | 0.6B | Simplified Chinese |
| 4 | en-US | 0.6B | English |
| 5 | System (English input method) | 0.6B | Auto-detect, Traditional if Chinese |

**Step 5: Final commit**

```bash
git add -A
git commit -m "test(qwen): add integration verification for language and download redesign"
git push
```
