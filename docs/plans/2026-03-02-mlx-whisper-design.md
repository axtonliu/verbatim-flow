# MLX Whisper + Large V3 整合設計

日期：2026-03-02

## 目標

新增 mlx-whisper 搭配 Whisper Large V3 作為 VerbatimFlow 的第五個 ASR 引擎，定位為「最高準確度」的本地端選項。

## 背景

用戶在其他專案比較過 mlx-whisper + Large V3 vs Qwen3 ASR，結果顯示 mlx-whisper 的字詞準確度和時間軸準確度都更高。

## 設計決策

| 決策 | 選擇 | 理由 |
|------|------|------|
| 引擎定位 | 獨立第五引擎 | 保留所有現有引擎不動 |
| 模型選項 | 僅 Large V3 | 定位為最高準確度，不需小模型 |
| 繁體輸出 | opencc s2t 後處理 | mlx-whisper 不區分繁簡，opencc 穩定可靠 |
| 選單名稱 | MLX Whisper | 明確區分現有 Whisper (faster-whisper) |
| 架構方案 | 獨立 Python 腳本 | 跟 Qwen3 pattern 一致，好維護好測試 |

## Python 端

### MlxWhisperTranscriber class

檔案：`verbatim_flow/mlx_whisper_transcriber.py`

```python
class MlxWhisperTranscriber:
    def __init__(self, model="mlx-community/whisper-large-v3-mlx")
    def transcribe(self, audio_path, language=None, output_locale=None) -> TranscriptResult
```

核心流程：
1. `_ensure_model()` — 檢查 HF cache，未快取則自動下載
2. `mlx_whisper.transcribe(audio_path, path_or_hf_repo=model, language=language)`
3. 繁簡處理：依 `_resolve_language()` 決定是否 opencc s2t

### 語言對照

`_resolve_language(code)` 回傳 `(whisper_lang, should_convert_to_traditional)`：

| 選單選項 | `--language` | whisper `language` | opencc s2t |
|---------|-------------|-------------------|------------|
| System | (無) | `None` (auto) | 依 `--output-locale` |
| zh-Hans | `zh-Hans` | `"zh"` | No |
| zh-Hant | `zh-Hant` | `"zh"` | Yes |
| en-US | `en-US` | `"en"` | No |

### CLI entry point

檔案：`scripts/transcribe_mlx_whisper.py`

```
python transcribe_mlx_whisper.py --audio <path> --model <hf-id> [--language <code>] [--output-locale <locale>]
```

跟 `transcribe_qwen.py` 完全對稱的介面。

## Swift 端

### CLIConfig.swift

- `RecognitionEngine.mlxWhisper`，rawValue `"mlx-whisper"`，displayName `"MLX Whisper"`
- 不需要模型 enum（僅 Large V3）
- `parse()` 加 `--engine mlx-whisper`

### SpeechTranscriber.swift

- `startRecording()`: `.mlxWhisper` → `startFileRecording()`
- `stopRecording()`: 新增 `stopMlxWhisperRecording()` → `transcribeMlxWhisperAudioFile()`
- 語言參數：複用 Qwen3 的 `qwenLanguageParam()` 邏輯（zh-Hant → `"zh-Hant"`，auto → nil）
- 新增 `resolveMlxWhisperScriptURL()` 走 `resolveScript(named:)`

### AppController.swift

- 不需要新增 model 屬性
- `rebuildTranscriber()` 和 log 加上 `.mlxWhisper` case

### MenuBarApp.swift

- 新增 `engineMlxWhisperItem`，title `"MLX Whisper"`
- 不需要模型子選單
- `refreshEngineChecks()` 加上 `.mlxWhisper` 狀態

### AppPreferences.swift / FailedRecordingStore.swift

- 不需要新增欄位（引擎 rawValue 已足夠）

## 依賴

- `requirements.txt` 新增 `mlx-whisper`
- `opencc-python-reimplemented` 已存在（Qwen3 用的）
- 模型 `mlx-community/whisper-large-v3-mlx` 約 3GB，首次使用自動下載

## 模型下載策略

跟 Qwen3 一致的 `_ensure_model()` pattern：
- 檢查 HF cache → 未快取 → `HF_HUB_OFFLINE=0` → 自動下載
- Swift 端不管 `HF_HUB_OFFLINE`，Python 端自行管理
- 下載/載入失敗 → stderr → Swift 捕獲存入 FailedRecordingStore 供重試
