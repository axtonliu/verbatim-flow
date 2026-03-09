# VerbatimFlow

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Status: Alpha](https://img.shields.io/badge/Status-Alpha-orange.svg)](#status)
[![Platform: macOS](https://img.shields.io/badge/Platform-macOS-blue.svg)](#)

**[简体中文](README_CN.md)** | **[繁體中文](README_zh-TW.md)**

A fast, zero-rewrite dictation app for macOS — your words, exactly as spoken.

> **Next Step:** Want to build your own AI-powered tools? Check out the [Agent Skills Resource Library](https://www.axtonliu.ai/agent-skills) (includes slides, PDF, diagnostics)

<p align="center">
  <img src="assets/bento-features.png" alt="VerbatimFlow Feature Overview" width="720">
</p>

## Why I Built This

I tried several popular dictation apps on macOS. They all share the same problems:

- **They rewrite your words.** You say one thing, and the tool "helpfully" rephrases it. You lose trust in your own input.
- **The hotkey gets stuck.** You release the key, but the app keeps recording. You have to press again — or restart.
- **They answer instead of typing.** AI-powered dictation tools sometimes treat your speech as a question and respond to it, instead of just typing what you said.
- **Your audio goes through a black box.** Closed-source, no visibility into what's sent where.

VerbatimFlow exists because I wanted a dictation tool I could actually trust: one that types what I say, releases when I release, never "helps" without asking, and runs on code I can read.

## What It Does

VerbatimFlow is a menu bar dictation utility that transcribes speech and injects text directly into any focused app.

**Core Principle:** Raw transcription first. Cleanup is opt-in and constrained.

- **Push-to-talk** — hold a hotkey to record, release to transcribe and inject
- **Two modes** — `Standard` (verbatim output with rule-based formatting: punctuation, spacing, capitalization) and `Clarify` (LLM-powered concise rewrite, opt-in)
- **Multiple engines** — Apple Speech, local Whisper, OpenAI Cloud, Qwen3 ASR (local, Apple Silicon)
- **Instant injection** — text appears in your active app via Accessibility API
- **Undo support** — one-click rollback of the last inserted transcript
- **Open source** — every line of code is readable; your audio, your control

## Status

> **Status: Alpha**
>
> - This is a working prototype that I use daily, but it has rough edges.
> - My primary focus is demonstrating how voice input can work without over-editing, not maintaining this codebase.
> - If you encounter issues, please submit a reproducible case (input + output + steps to reproduce).

## Features

- **Menu bar app** — lives in the macOS menu bar as a V-mark icon with real-time state badges (● recording, ○ processing, — paused)
- **Dual hotkey** — primary hotkey uses current mode; secondary hotkey (`Cmd+Shift+Space`) forces Clarify for one segment
- **Engine switching** — Apple Speech / Whisper (tiny–large-v3) / OpenAI Cloud (gpt-4o-mini-transcribe, whisper-1) / Qwen3 ASR (0.6B / 1.7B, local on Apple Silicon via mlx-audio)
- **Clarify via OpenAI or OpenRouter** — configurable provider, model, and API keys
- **Terminology dictionary** — custom term corrections and source→target substitution rules
- **Language selection** — System Default / zh-Hans / zh-Hant / en-US
- **Transcript history** — recent transcripts viewable in menu, with Copy + Undo Last Insert
- **Permission diagnostics** — built-in permission snapshot and one-click system settings access
- **Persistent preferences** — mode, engine, model, hotkey, and language survive restarts
- **Deterministic code signing** — stable bundle ID prevents permission invalidation across rebuilds

## Installation

### Prerequisites

- macOS 14+ (Sonoma or later recommended)
- Xcode 16+ (for building from source)
- Microphone and Accessibility permissions
- Apple Silicon (M1/M2/M3/M4) or Intel Mac (universal binary supported)

### Build the App

```bash
git clone https://github.com/axtonliu/verbatim-flow.git
cd verbatim-flow

# Build .app bundle
./scripts/build-native-app.sh
open "apps/mac-client/dist/VerbatimFlow.app"
```

### Build Installer DMG

```bash
./scripts/build-installer-dmg.sh
open "apps/mac-client/dist/VerbatimFlow-installer.dmg"
```

The DMG provides drag-and-drop installation to `/Applications`.

## Usage

1. **Launch** — double-click `VerbatimFlow.app` or run `./scripts/run-native-mac-client.sh`
2. **Grant permissions** — Microphone, Accessibility, and Speech Recognition (prompted on first launch, or use menu shortcuts)
3. **Hold hotkey** — default `Ctrl+Shift+Space` to record; release to transcribe and inject
4. **Switch modes** — use the Settings menu to toggle between Standard and Clarify
5. **Force Clarify** — press `Cmd+Shift+Space` to use Clarify mode for one segment regardless of default

### Hotkey Presets

Switch hotkey presets from the Settings menu without restarting:

| Preset | Hotkey |
|--------|--------|
| Default | `Ctrl+Shift+Space` |
| Option+Space | `Option+Space` |
| Fn | `Fn` |

## Configuration

### OpenAI / OpenRouter Settings

Cloud transcription and Clarify rewrite are configured via `~/Library/Application Support/VerbatimFlow/openai.env`:

```bash
# OpenAI transcription
OPENAI_API_KEY=sk-...
VERBATIMFLOW_OPENAI_MODEL=gpt-4o-mini-transcribe

# Auto route (fast first pass, then high-accuracy fallback for risky mixed-language terms)
VERBATIMFLOW_OPENAI_AUTO_ROUTE=1
VERBATIMFLOW_OPENAI_AUTO_SECONDARY_MODEL=whisper-1
# Optional tuning:
# VERBATIMFLOW_OPENAI_AUTO_ROUTE_ZH_ONLY=1
# VERBATIMFLOW_OPENAI_LANGUAGE_HINT_MODE=auto
# VERBATIMFLOW_OPENAI_AUTO_ROUTE_MIN_RISK_SCORE=2
# VERBATIMFLOW_OPENAI_AUTO_ROUTE_MIN_PRIMARY_CHARS=8

# Clarify provider: openai or openrouter
VERBATIMFLOW_CLARIFY_PROVIDER=openai
VERBATIMFLOW_OPENAI_CLARIFY_MODEL=gpt-4o-mini

# OpenRouter alternative
# VERBATIMFLOW_CLARIFY_PROVIDER=openrouter
# OPENROUTER_API_KEY=...
# VERBATIMFLOW_OPENAI_CLARIFY_MODEL=openai/gpt-4o-mini
```

Edit this file directly or via the menu bar: **Settings → Open Cloud Settings**.

### Terminology Dictionary

Custom term corrections at `~/Library/Application Support/VerbatimFlow/terminology.txt`:

```
# Simple term corrections
VerbatimFlow
macOS
OpenAI

# Substitution rules (source => target)
verbal flow => VerbatimFlow
mac OS => macOS
```

### Runtime Logs

```bash
~/Library/Logs/VerbatimFlow/runtime.log
```

## File Structure

```
verbatim-flow/
├── apps/mac-client/
│   ├── Sources/VerbatimFlow/    # Native Swift app
│   │   ├── main.swift           # Entry point
│   │   ├── MenuBarApp.swift     # Menu bar UI
│   │   ├── AppController.swift  # Core orchestration
│   │   ├── HotkeyMonitor.swift  # Global hotkey handling
│   │   ├── SpeechTranscriber.swift
│   │   ├── TextInjector.swift   # Accessibility-based injection
│   │   ├── TextGuard.swift      # Format-only diff guard
│   │   ├── ClarifyRewriter.swift
│   │   ├── TerminologyDictionary.swift
│   │   └── ...
│   ├── Tests/VerbatimFlowTests/ # Unit tests
│   ├── python/                  # Python ASR scripts
│   │   ├── scripts/             # CLI entry points (transcribe_qwen.py)
│   │   └── verbatim_flow/       # Qwen3 ASR transcriber module
│   ├── Package.swift
│   └── dist/                    # Build output (.app, .dmg)
├── packages/                    # Shared package stubs
│   ├── asr-pipeline/
│   ├── text-guard/
│   ├── text-injector/
│   └── shared/
├── scripts/
│   ├── build-native-app.sh      # Build .app bundle
│   ├── build-installer-dmg.sh   # Build installer DMG
│   ├── restart-native-app.sh    # Kill + relaunch
│   ├── collect-permission-diagnostics.sh
│   ├── run-mac-client.sh        # Run Python MVP
│   └── run-native-mac-client.sh # Run native Swift
├── docs/
│   └── ARCHITECTURE.md
├── package.json
├── pnpm-workspace.yaml
├── LICENSE
└── README.md
```

## Troubleshooting

### Permissions

- **Microphone not working:** System Settings → Privacy & Security → Microphone → ensure VerbatimFlow is checked. Use menu: **Settings → Request Microphone Permission**.
- **Text not injecting:** System Settings → Privacy & Security → Accessibility → add VerbatimFlow. The app uses a stable bundle ID (`com.verbatimflow.app`) so permissions persist across rebuilds.
- **Permission appears granted but still fails:** Try removing and re-adding the app in System Settings. Run `./scripts/collect-permission-diagnostics.sh 30` for detailed diagnostics.

### Hotkey

- **Hotkey not responding:** Check that no other app is capturing the same shortcut. Try switching to a different preset via the Settings menu.
- **Menu bar icon shows a pause dash:** Hotkey listener is paused. Click **Resume Listening** in the menu.

### Clarify Mode

- **Clarify returns original text:** Verify your API key in `openai.env`. Check `~/Library/Logs/VerbatimFlow/runtime.log` for errors.
- **Want to use OpenRouter instead:** Set `VERBATIMFLOW_CLARIFY_PROVIDER=openrouter` and provide `OPENROUTER_API_KEY` in `openai.env`.

## Roadmap

- [x] Whisper engine integration in native Swift path
- [x] Improved mixed-language (CJK + English) handling
- [x] Qwen3 ASR local engine (0.6B / 1.7B on Apple Silicon)
- [x] Traditional Chinese (zh-Hant) language option
- [x] Universal binary (Intel + Apple Silicon)
- [ ] Streaming transcription (word-by-word injection as you speak)
- [ ] Configurable text guard sensitivity threshold
- [ ] Per-app mode profiles
- [ ] Clarify structural formatting (e.g., detect action items and render as bullet lists while preserving meaning)

## Contributing

Contributions welcome (low-maintenance project):

- Reproducible bug reports (input + output + steps + environment)
- Documentation improvements
- Small PRs (fixes/docs)

> **Note:** Feature requests may not be acted on due to limited maintenance capacity.

## Acknowledgments

- [Apple Speech Framework](https://developer.apple.com/documentation/speech) — on-device speech recognition
- [OpenAI Whisper](https://openai.com/research/whisper) — open-source ASR model
- [faster-whisper](https://github.com/SYSTRAN/faster-whisper) — CTranslate2-based Whisper inference (Python MVP)
- [Qwen3-ASR](https://github.com/QwenLM/Qwen3-ASR) — multilingual ASR model by Alibaba Qwen team
- [mlx-audio](https://github.com/Blaizzy/mlx-audio) — Apple Silicon-optimized audio ML framework
- [OpenCC](https://github.com/BYVoid/OpenCC) — Simplified/Traditional Chinese conversion

## License

MIT License — see [LICENSE](LICENSE) for details.

---

## Author

**Axton Liu** — AI Educator & Creator

- Website: [axtonliu.ai](https://www.axtonliu.ai)
- YouTube: [@AxtonLiu](https://youtube.com/@AxtonLiu)
- Twitter/X: [@axtonliu](https://twitter.com/axtonliu)

### Learn More

- [Agent Skills Resource Library](https://www.axtonliu.ai/agent-skills) — slides, PDF guides, diagnostics tools
- [AI Elite Weekly Newsletter](https://www.axtonliu.ai/newsletters/ai-2) — Weekly AI insights
- [Free AI Course](https://www.axtonliu.ai/axton-free-course) — Get started with AI

---

© AXTONLIU™ & AI 精英学院™ 版权所有
