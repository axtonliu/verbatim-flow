# mac-client

macOS desktop shell for microphone control, hotkeys, and pipeline orchestration.

## Run Native AppCore
```bash
cd "/Users/axton/Documents/DailyWork🌴/Project Files/Code Projects/verbatim-flow/apps/mac-client"
swift run verbatim-flow --mode raw --hotkey ctrl+shift+space
```

The app runs as a menu bar item (`VF`). Use the menu to:
- Pause/resume hotkey listener
- Switch `Raw`, `Format-only`, and `Clarify` modes
- Switch recognition engine (`Apple Speech`, `Whisper`, `OpenAI Cloud`)
- Switch Whisper model (`tiny`, `base`, `small`, `medium`, `large-v3`)
- Switch language (`System Default`, `zh-Hans`, `en-US`)
- Trigger microphone/speech permission request
- See permission status summary (`Mic/Speech/Accessibility`)
- Change hotkey presets in-app
- Access recent transcript history
- Use `Copy + Undo Last Insert` for one-click rollback
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
`Mode`, `Recognition Engine`, `Whisper Model`, `Hotkey`, and `Language` are persisted with `UserDefaults` and restored on restart.
CLI flags still override saved values for the current run.

## Build and test
```bash
swift build
swift test
```

## Build app bundle
```bash
cd "/Users/axton/Documents/DailyWork🌴/Project Files/Code Projects/verbatim-flow"
./scripts/build-native-app.sh
open "/Users/axton/Documents/DailyWork🌴/Project Files/Code Projects/verbatim-flow/apps/mac-client/dist/VerbatimFlow.app"
```

`build-native-app.sh` now applies a fixed ad-hoc signature (`com.axtonliu.verbatimflow`) after packaging to keep macOS permission identity consistent.

## Flags
- `--mode raw|format-only|clarify`
- `--engine apple|whisper|openai`
- `--whisper-model tiny|base|small|medium|large-v3`
- `--whisper-compute-type int8|int8_float16|float16|float32`
- `--hotkey ctrl+shift+space` (also supports modifier-only combos like `shift+option`, and aliases like `shift+alt`)
- `--locale zh-Hans`
- `--require-on-device`
- `--dry-run`

## OpenAI Cloud engine
When `Recognition Engine` is set to `OpenAI Cloud`, set:
- `OPENAI_API_KEY` (required)
- `VERBATIMFLOW_OPENAI_MODEL` (optional, default: `gpt-4o-mini-transcribe`)
- `VERBATIMFLOW_OPENAI_BASE_URL` (optional, default: `https://api.openai.com/v1`)

If app environment variables are unavailable in GUI launch mode, edit:
`~/Library/Application Support/VerbatimFlow/openai.env`
