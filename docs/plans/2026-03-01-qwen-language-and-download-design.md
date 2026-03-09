# Qwen3 ASR: Language Setting & Model Download Redesign

Date: 2026-03-01

## Problem

Three issues with the current Qwen3 ASR integration:

1. **Language setting ignored**: Qwen engine passes `languageCode: nil`, ignoring user's menu bar language selection entirely.
2. **No zh-Hant option**: Menu only has System / zh-Hans / en-US. Traditional Chinese users have no explicit option. Simplified-to-Traditional conversion is unconditionally applied to all Chinese output.
3. **New users blocked**: `HF_HUB_OFFLINE=1` is hardcoded. Users without pre-cached models cannot use Qwen engine at all.

## Design

### 1. Language Setting Restoration

**Swift side (`SpeechTranscriber.swift`):**
- `stopQwenRecording()` and retry path: restore passing `languageCode` to `transcribeQwenAudioFile()`.
- New function `qwenLanguageParam(from localeIdentifier:)`:
  - Returns `nil` for system locale (triggers auto-detect)
  - Returns `"zh-Hant"` / `"zh-Hans"` / `"en"` / raw code for explicit selections
- Remove `HF_HUB_OFFLINE` environment variable setting (delegated to Python).

**Python side (`qwen_transcriber.py`):**
- `_resolve_language()` returns `(model_language, should_convert_to_traditional)`:
  - `"zh-Hant"` -> `("Chinese", True)`
  - `"zh-Hans"` -> `("Chinese", False)`
  - `"zh"` -> `("Chinese", True)` (default to Traditional for backward compat)
  - `"en"` -> `("English", False)`
  - `None` -> `(None, None)` (auto-detect; Traditional/Simplified decided by CJK detection + system locale)
- Auto-detect CJK fallback preserved; when detected, check `--output-locale` or default to Traditional.

**Python side (`transcribe_qwen.py`):**
- New optional `--output-locale` arg: used in auto-detect mode to decide Traditional/Simplified conversion. Swift passes system locale when user selects "System" language.

### 2. Menu Bar zh-Hant Option

**`MenuBarApp.swift`:**
- Add `languageZhHantItem`: "Traditional Chinese (zh-Hant)"
- Add `setLanguageZhHant()` -> `setLanguageSelection("zh-Hant")`
- Update `refreshLanguageChecks()` to include zh-Hant check state.
- `mappedLocaleIdentifier()` already handles `zh-Hant`.

### 3. Model Auto-Download

**Python side (`qwen_transcriber.py`):**
- `_ensure_model()` checks cache path `~/.cache/huggingface/hub/models--{org}--{name}`:
  - Not exists: set `HF_HUB_OFFLINE=0`, print `[info] Downloading model {name}...` to stderr, load model (downloads automatically), set back to `HF_HUB_OFFLINE=1`.
  - Exists: keep offline, load from cache.

**Swift side (`SpeechTranscriber.swift`):**
- Remove `env["HF_HUB_OFFLINE"] = "1"` from `transcribeQwenAudioFile()`. Python controls this now.

**Error handling:**
- Download failure (no network) -> Python raises error -> Swift shows in menu bar "Model download failed: ..."

## Files to Modify

| File | Changes |
|------|---------|
| `SpeechTranscriber.swift` | Restore language passing, add `qwenLanguageParam()`, remove `HF_HUB_OFFLINE` |
| `MenuBarApp.swift` | Add zh-Hant menu item |
| `qwen_transcriber.py` | Refactor `_resolve_language()`, add cache-check download logic |
| `transcribe_qwen.py` | Add `--output-locale` argument |

## Data Flow Summary

```
User selects "zh-Hant" in menu
  -> Swift: --language zh-Hant
  -> Python: _resolve_language("zh-Hant") -> ("Chinese", True)
  -> mlx-audio: generate(language="Chinese")
  -> opencc: s2t conversion
  -> Output: Traditional Chinese

User selects "System" in menu
  -> Swift: no --language, --output-locale zh-Hant (if system is TW)
  -> Python: auto-detect mode (__auto__)
  -> Model outputs text
  -> CJK detected -> check output-locale -> s2t if zh-Hant
  -> Output: depends on system locale
```
