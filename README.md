# verbatim-flow

A fast dictation input app prototype for macOS.

## Product intent
- Keep latency low enough for everyday writing.
- Preserve original wording by default (no unsolicited rewriting).
- Allow optional formatting-only cleanup (punctuation, spacing, case).

## Monorepo layout
- `apps/mac-client/python`: runnable Python MVP (hotkey, recording, transcription, guard, inject).
- `apps/mac-client`: native macOS AppCore (Swift).
- `packages/asr-pipeline`: streaming ASR + VAD orchestration.
- `packages/text-guard`: format-only diff guard.
- `packages/text-injector`: global text injection abstraction.
- `packages/shared`: shared types and utilities.
- `docs`: architecture and technical decisions.

## Current runnable path
```bash
cd "/Users/axton/Documents/DailyWork🌴/Project Files/Code Projects/verbatim-flow/apps/mac-client/python"
./scripts/setup_env.sh
./scripts/run.sh --mode raw --model small
```

See `/Users/axton/Documents/DailyWork🌴/Project Files/Code Projects/verbatim-flow/apps/mac-client/python/README.md` for permissions and troubleshooting.

Or run from project root:
```bash
cd "/Users/axton/Documents/DailyWork🌴/Project Files/Code Projects/verbatim-flow"
./scripts/run-mac-client.sh --mode raw --model small
```

Native AppCore run:
```bash
cd "/Users/axton/Documents/DailyWork🌴/Project Files/Code Projects/verbatim-flow"
./scripts/run-native-mac-client.sh --mode raw --hotkey ctrl+shift+space
```

Native app launches as a menu bar item (`VF`) with controls for:
- pause/resume hotkey listener
- switching `Raw` / `Format-only` mode
- switching language (`System Default` / `zh-Hans` / `en-US`)
- requesting microphone/speech permission
- changing hotkey preset in-app
- viewing recent transcript history
- one-click `Copy + Undo Last Insert` rollback
- opening permission settings
- opening local runtime logs

`Mode`, `Hotkey`, and `Language` selections persist across restarts.

Build double-clickable app bundle:
```bash
cd "/Users/axton/Documents/DailyWork🌴/Project Files/Code Projects/verbatim-flow"
./scripts/build-native-app.sh
open "/Users/axton/Documents/DailyWork🌴/Project Files/Code Projects/verbatim-flow/apps/mac-client/dist/VerbatimFlow.app"
```

The build script applies a fixed ad-hoc signature (`com.axtonliu.verbatimflow`) so permissions are tied to a stable app identity.

Restart native app (kills stale processes first):
```bash
cd "/Users/axton/Documents/DailyWork🌴/Project Files/Code Projects/verbatim-flow"
./scripts/restart-native-app.sh
```

Collect permission diagnostics (tccd + signature + app runtime log):
```bash
cd "/Users/axton/Documents/DailyWork🌴/Project Files/Code Projects/verbatim-flow"
./scripts/collect-permission-diagnostics.sh 30
```

Runtime log file:
```bash
~/Library/Logs/VerbatimFlow/runtime.log
```
