# VerbatimFlow

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Status: Alpha](https://img.shields.io/badge/Status-Alpha-orange.svg)](#狀態)
[![Platform: macOS](https://img.shields.io/badge/Platform-macOS-blue.svg)](#)

一款快速、零改寫的 macOS 語音輸入工具 —— 你說的話，原封不動。

> **延伸閱讀：** 想自己建構 AI 工具？查看 [Agent Skills 資源庫](https://www.axtonliu.ai/agent-skills)（含投影片、PDF、診斷工具）

<p align="center">
  <img src="assets/bento-features.png" alt="VerbatimFlow 功能總覽" width="720">
</p>

## 為什麼自己做

我試了幾款 Mac 上主流的語音輸入工具，它們都有同樣的問題：

- **改你的原話。** 你說 A，它輸出 B。擅自潤色、改寫，讓你對自己的輸入失去信任。
- **按鍵卡住不釋放。** 你已經鬆手了，它還在錄。只能再按一次，或者重啟。
- **把你的話當問題回答。** AI 輸入法的通病：你在打字，它把你的話當成提問，直接生成一段回答塞進輸入框。
- **資料去了哪裡你不知道。** 閉源黑箱，音訊發給了誰、存在哪，完全不透明。

VerbatimFlow 的存在就是因為：我想要一個**能信任**的語音輸入工具 —— 說什麼打什麼、鬆手就停、不替你做主、程式碼全部透明。

## 它做什麼

VerbatimFlow 是一個 macOS 選單列語音輸入工具，轉寫語音後直接注入到目前活躍的應用程式中。

**核心原則：** 先忠實轉寫，整理可選、受控。

- **按住說話** — 按住快捷鍵錄音，鬆開即轉寫並注入文字
- **兩種模式** — `Standard`（忠實轉寫 + 基於規則的格式化：標點、空格、大小寫）和 `Clarify`（LLM 驅動的精簡改寫，主動選擇才生效）
- **多引擎支援** — Apple Speech、本機 Whisper、OpenAI 雲端、Qwen3 ASR（本機，Apple Silicon）
- **即時注入** — 透過 Accessibility API 直接在活躍 App 中插入文字
- **一鍵撤回** — 回滾上一次插入的轉寫結果
- **完全開源** — 每一行程式碼可讀；你的音訊，你做主

## 狀態

> **狀態：Alpha**
>
> - 這是一個我每天在用的可用原型，但仍有粗糙之處。
> - 我的主要目標是展示語音輸入如何在不過度編輯的前提下工作，而非長期維護此程式碼庫。
> - 如果遇到問題，請提交可重現的 case（輸入 + 輸出 + 重現步驟）。

## 功能特性

### 工程驗收標準（不是演示標準）

我們沒有追求「功能最多」，而是定義了「先可用再最佳化」的門檻：

| 驗收項 | 說明 |
|--------|------|
| **全域快捷鍵穩定** | 按住錄，鬆開轉寫，不卡狀態。雙訊號 watchdog + handshake 機制防「偽按下」 |
| **權限穩定** | 固定 bundle ID 簽名，重啟後不頻繁重新授權 |
| **插入穩定** | AX → Cmd+V → Unicode typing 三級回落，Terminal / Codex / 標準編輯器都能上屏 |
| **引擎可切換** | Apple Speech / Whisper (tiny–large-v3) / OpenAI Cloud (gpt-4o-mini-transcribe, whisper-1) / Qwen3 ASR (0.6B / 1.7B，Apple Silicon 本機) |
| **失敗可恢復** | 轉寫失敗自動儲存錄音，選單一鍵重試，不丟內容 |
| **設定可持久化** | 快捷鍵、模式、引擎、模型、語言等核心設定重啟保留 |

### 完整功能列表

- **選單列應用** — 以 V 形圖示駐留在 macOS 選單列，即時狀態徽標（● 錄音中、○ 處理中、— 已暫停）
- **雙快捷鍵** — 主快捷鍵使用目前模式；副快捷鍵（`Cmd+Shift+Space`）臨時強制 Clarify 模式，僅作用一次
- **快捷鍵預設切換** — 支援 `Ctrl+Shift+Space` / `Option+Space` / `Fn`，選單內切換無需重啟
- **多引擎即時切換** — Apple Speech / Whisper / OpenAI 雲端 / Qwen3 ASR，選單內一鍵切換
- **Whisper 模型選擇** — tiny / base / small / medium / large-v3
- **Clarify 整理** — 支援 OpenAI 和 OpenRouter 雙通道，獨立設定 provider、model、API key
- **術語詞典** — 自訂修正規則（詞彙修正 + `source => target` 替換）
- **中英混合增強** — 專門的混合語言後處理最佳化
- **語言選擇** — System Default / zh-Hans / zh-Hant / en-US
- **轉寫歷史** — 選單內查看最近轉寫，支援 Copy + 撤回上次插入
- **失敗錄音重試** — 轉寫失敗時音訊自動持久化，一鍵重試
- **權限診斷** — 內建權限快照報告、一鍵跳轉系統設定
- **執行時日誌** — 完整的可觀測日誌系統
- **確定性程式碼簽名** — 固定 bundle ID 防止每次建置後權限失效
- **DMG 安裝包** — 支援拖放安裝到 Applications

## 安裝

### 方式一：下載安裝包（推薦）

從 [GitHub Releases](https://github.com/axtonliu/verbatim-flow/releases) 下載最新的 `.dmg` 檔案，拖放安裝到 Applications。

### 方式二：從原始碼建置

**前置需求：**
- macOS 14+（推薦 Sonoma 及以上）
- Xcode 16+
- 麥克風和輔助使用權限
- Apple Silicon（M1/M2/M3/M4）或 Intel Mac（支援 Universal Binary）

```bash
git clone https://github.com/axtonliu/verbatim-flow.git
cd verbatim-flow

# 建置 .app
./scripts/build-native-app.sh
open "apps/mac-client/dist/VerbatimFlow.app"

# 或建置安裝 DMG
./scripts/build-installer-dmg.sh
open "apps/mac-client/dist/VerbatimFlow-installer.dmg"
```

## 使用方法

1. **啟動** — 雙擊 `VerbatimFlow.app` 或執行 `./scripts/run-native-mac-client.sh`
2. **授予權限** — 首次啟動會提示授權麥克風、輔助使用、語音辨識（也可透過選單手動請求）
3. **按住快捷鍵** — 預設 `Ctrl+Shift+Space` 錄音；鬆開後自動轉寫並注入
4. **切換模式** — 透過 Settings 選單在 Standard / Clarify 間切換
5. **臨時 Clarify** — 按 `Cmd+Shift+Space` 目前片段強制使用 Clarify 模式

## 設定

### OpenAI / OpenRouter 設定

雲端轉寫和 Clarify 整理透過 `~/Library/Application Support/VerbatimFlow/openai.env` 設定：

```bash
# OpenAI 轉寫
OPENAI_API_KEY=sk-...

# Clarify provider: openai 或 openrouter
VERBATIMFLOW_CLARIFY_PROVIDER=openai
VERBATIMFLOW_OPENAI_CLARIFY_MODEL=gpt-4o-mini

# OpenRouter 替代方案
# VERBATIMFLOW_CLARIFY_PROVIDER=openrouter
# OPENROUTER_API_KEY=...
# VERBATIMFLOW_OPENAI_CLARIFY_MODEL=openai/gpt-4o-mini
```

也可透過選單列直接編輯：**Settings → Open Cloud Settings**。

### 術語詞典

自訂修正規則位於 `~/Library/Application Support/VerbatimFlow/terminology.txt`：

```
# 術語修正
VerbatimFlow
macOS
OpenAI

# 替換規則（source => target）
verbal flow => VerbatimFlow
mac OS => macOS
```

### 執行日誌

```bash
~/Library/Logs/VerbatimFlow/runtime.log
```

## 專案結構

```
verbatim-flow/
├── apps/mac-client/
│   ├── Sources/VerbatimFlow/    # 原生 Swift 應用
│   │   ├── main.swift           # 入口
│   │   ├── MenuBarApp.swift     # 選單列 UI
│   │   ├── AppController.swift  # 核心編排
│   │   ├── HotkeyMonitor.swift  # 全域快捷鍵處理
│   │   ├── SpeechTranscriber.swift
│   │   ├── TextInjector.swift   # 基於 Accessibility 的文字注入
│   │   ├── TextGuard.swift      # Format-only diff 守衛
│   │   ├── ClarifyRewriter.swift
│   │   ├── TerminologyDictionary.swift
│   │   └── ...
│   ├── Tests/VerbatimFlowTests/ # 單元測試
│   ├── python/                  # Python ASR 腳本
│   │   ├── scripts/             # CLI 入口（transcribe_qwen.py）
│   │   └── verbatim_flow/       # Qwen3 ASR 轉寫模組
│   ├── Package.swift
│   └── dist/                    # 建置產物（.app, .dmg）
├── packages/                    # 共用套件預留
├── scripts/
│   ├── build-native-app.sh      # 建置 .app
│   ├── build-installer-dmg.sh   # 建置安裝 DMG
│   ├── restart-native-app.sh    # 終止行程 + 重啟
│   ├── collect-permission-diagnostics.sh
│   └── ...
├── docs/
│   └── ARCHITECTURE.md
├── LICENSE
├── README.md
└── README_CN.md
```

## 常見問題

### 權限問題

- **麥克風不工作：** 系統設定 → 隱私權與安全性 → 麥克風 → 確保 VerbatimFlow 已勾選。或使用選單：**Settings → Request Microphone Permission**。
- **文字不注入：** 系統設定 → 隱私權與安全性 → 輔助使用 → 加入 VerbatimFlow。應用程式使用固定 bundle ID（`com.verbatimflow.app`），權限在重新建置後仍然有效。
- **權限看起來授予了但仍然失敗：** 嘗試移除後重新加入。執行 `./scripts/collect-permission-diagnostics.sh 30` 取得詳細診斷。

### 快捷鍵問題

- **快捷鍵無回應：** 檢查是否有其他 App 佔用了相同快捷鍵。嘗試透過 Settings 選單切換到其他預設。
- **選單列圖示顯示暫停橫線：** 快捷鍵監聽已暫停，點選選單中的 **Resume Listening**。

### Clarify 模式

- **Clarify 傳回原文：** 檢查 `openai.env` 中的 API key。查看 `~/Library/Logs/VerbatimFlow/runtime.log` 中的錯誤訊息。
- **想用 OpenRouter：** 在 `openai.env` 中設定 `VERBATIMFLOW_CLARIFY_PROVIDER=openrouter` 並提供 `OPENROUTER_API_KEY`。

## 路線圖

- [x] 原生 Swift 路徑整合 Whisper 引擎
- [x] 中英混合辨識最佳化
- [x] Qwen3 ASR 本機引擎（0.6B / 1.7B，Apple Silicon）
- [x] 繁體中文（zh-Hant）語言選項
- [x] Universal Binary（Intel + Apple Silicon）
- [ ] 串流轉寫（邊說邊出字）
- [ ] 可設定的 text guard 靈敏度閾值
- [ ] 按應用程式自訂模式 profile

## 貢獻

歡迎貢獻（低維護專案）：

- 可重現的 bug 報告（輸入 + 輸出 + 步驟 + 環境）
- 文件改進
- 小型 PR（修復/文件）

> **注意：** 由於維護精力有限，功能請求可能不會被回應。

## 致謝

- [Apple Speech Framework](https://developer.apple.com/documentation/speech) — 裝置端語音辨識
- [OpenAI Whisper](https://openai.com/research/whisper) — 開源 ASR 模型
- [faster-whisper](https://github.com/SYSTRAN/faster-whisper) — 基於 CTranslate2 的 Whisper 推理（Python MVP）
- [Qwen3-ASR](https://github.com/QwenLM/Qwen3-ASR) — 阿里 Qwen 團隊的多語言 ASR 模型
- [mlx-audio](https://github.com/Blaizzy/mlx-audio) — Apple Silicon 最佳化的音訊 ML 框架
- [OpenCC](https://github.com/BYVoid/OpenCC) — 簡繁中文轉換

## 授權條款

MIT License — 詳見 [LICENSE](LICENSE)。

---

## 作者

**Axton Liu** — AI 教育者 & 創作者

- 網站：[axtonliu.ai](https://www.axtonliu.ai)
- YouTube：[@AxtonLiu](https://youtube.com/@AxtonLiu)
- Twitter/X：[@axtonliu](https://twitter.com/axtonliu)

### 了解更多

- [Agent Skills 資源庫](https://www.axtonliu.ai/agent-skills) — 投影片、PDF 指南、診斷工具
- [AI 精英週刊 Newsletter](https://www.axtonliu.ai/newsletters/ai-2) — 每週 AI 洞察
- [免費 AI 課程](https://www.axtonliu.ai/axton-free-course) — 開始你的 AI 之旅

---

© AXTONLIU™ & AI 精英學院™ 版權所有
