# mac-client

macOS desktop shell for microphone control, hotkeys, and pipeline orchestration.

## Run Native AppCore
```bash
cd "/Users/axton/Documents/DailyWork🌴/Project Files/Code Projects/verbatim-flow/apps/mac-client"
swift run verbatim-flow --mode raw --hotkey ctrl+shift+space
```

## Build and test
```bash
swift build
swift test
```

## Flags
- `--mode raw|format-only`
- `--hotkey ctrl+shift+space` (supports aliases like `shift+option+space`)
- `--locale zh-Hans`
- `--require-on-device`
- `--dry-run`
