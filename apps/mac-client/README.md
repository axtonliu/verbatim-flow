# mac-client

macOS desktop shell for microphone control, hotkeys, and pipeline orchestration.

## Run Native AppCore
```bash
cd apps/mac-client
swift run verbatim-flow --mode raw --hotkey ctrl+shift+space
```

The app runs as a menu bar item (`VF`). Most controls are grouped under a unified `Settings` submenu:
- Pause/resume hotkey listener
- Switch `Raw`, `Format-only`, and `Clarify` modes
- Switch recognition engine (`Apple Speech`, `Whisper`, `OpenAI Cloud`, `Qwen3 ASR`, `MLX Whisper`)
- Switch Whisper model (`tiny`, `base`, `small`, `medium`, `large-v3`)
- Switch Qwen3 model (`0.6B-8bit`, `1.7B-8bit`)
- Switch OpenAI cloud model (`gpt-4o-mini-transcribe`, `whisper-1`)
- Switch language (`System Default`, `zh-Hans`, `zh-Hant`, `en-US`)
- Trigger microphone/speech permission request
- See permission status summary (`Mic/Speech/Accessibility`)
- Change hotkey presets in-app
- Access recent transcript history
- Use `Copy + Undo Last Insert` for one-click rollback
- Retry the last failed audio transcription without re-speaking
- Open Accessibility and Microphone permission pages
- Open OpenAI cloud settings file

Status indicator in menu bar:
- `VF` = ready
- `VF●` = recording
- `VF…` = processing
- `VF⏸` = paused

Permission request behavior:
- On request, the app is temporarily activated to foreground to improve macOS prompt reliability.
- Permission requests use timeout fallback, so the UI reports status even if macOS callbacks stall.

### Persistent settings
`Mode`, `Recognition Engine`, `Whisper Model`, `OpenAI Model`, `Hotkey`, and `Language` are persisted with `UserDefaults` and restored on restart.
CLI flags still override saved values for the current run.

## Build and test
```bash
swift build
swift test
```

## Build app bundle
```bash
./scripts/build-native-app.sh
open "apps/mac-client/dist/VerbatimFlow.app"
```

`build-native-app.sh` applies a fixed ad-hoc signature (`$VERBATIMFLOW_BUNDLE_ID`, default `com.verbatimflow.app`) after packaging to keep macOS permission identity consistent.

## Flags
- `--mode raw|format-only|clarify`
- `--engine apple|whisper|openai|qwen|mlx-whisper`
- `--whisper-model tiny|base|small|medium|large-v3`
- `--whisper-compute-type int8|int8_float16|float16|float32`
- `--openai-model gpt-4o-mini-transcribe|whisper-1`
- `--hotkey ctrl+shift+space` (also supports modifier-only combos like `shift+option`, and aliases like `shift+alt`)
- `--locale zh-Hans`
- `--require-on-device`
- `--dry-run`

## OpenAI Cloud engine
When `Recognition Engine` is set to `OpenAI Cloud`, set:
- `OPENAI_API_KEY` (required)
- `VERBATIMFLOW_OPENAI_MODEL` (optional, default: `gpt-4o-mini-transcribe`)
- `VERBATIMFLOW_OPENAI_BASE_URL` (optional, default: `https://api.openai.com/v1`)
- `VERBATIMFLOW_ALLOW_INSECURE_OPENAI_BASE_URL` (optional, default: off; set `1` only for local dev HTTP endpoints)

If app environment variables are unavailable in GUI launch mode, edit:
`~/Library/Application Support/VerbatimFlow/openai.env`

Security defaults:
- Cloud requests are sent over HTTPS by default.
- Non-HTTPS `VERBATIMFLOW_OPENAI_BASE_URL` is rejected unless explicit dev override is enabled.
