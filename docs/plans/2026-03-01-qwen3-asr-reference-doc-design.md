# Qwen3-ASR 跨專案參考文件 — 設計

Date: 2026-03-01

## 目標

建立一份跨專案通用的 Qwen3-ASR 技術參考文件，供 Claude Code agent 在任何專案中使用。

## 設計決策

- **位置**：`~/.claude/memory/qwen3-asr-reference.md`（全域 memory）
- **讀者**：Claude Code agent
- **語言**：繁體中文為主，程式碼和 API 保留英文
- **不包含**：VerbatimFlow 專案特定內容（monkey-patch 實作、Swift 整合、venv 路徑）

## 章節結構

1. 模型一覽 — ASR + ForcedAligner 型號表
2. 語言支援 — MLX 11 語言 + 語言參數格式
3. 音訊輸入 — 格式、取樣率、時長限制
4. API 參考 — generate()、stream_transcribe()、ForcedAligner、generate_transcription()
5. 時間戳能力 — 兩層架構 + 字幕生成策略
6. 長音訊處理 — chunk 策略 + 影片場景建議
7. 繁體中文處理 — opencc s2t、語言判斷邏輯（獨立章節）
8. 已知限制與注意事項 — 通用性的限制，不含專案特定 workaround
9. 效能基準 — WER + 速度
10. 影片字幕工作流 — 端到端流程圖 + 可執行骨架
11. 依賴與參考連結

## 與現有文件的關係

- 取代：`~/.claude/projects/.../memory/qwen3-asr-reference.md`（刪除舊檔）
- 保留：VerbatimFlow 專案 MEMORY.md 中的專案特定細節不受影響
