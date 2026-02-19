# verbatim-flow

A fast dictation input app prototype for macOS.

## Product intent
- Keep latency low enough for everyday writing.
- Preserve original wording by default (no unsolicited rewriting).
- Allow optional formatting-only cleanup (punctuation, spacing, case).
- Provide optional `Clarify` mode for concise, cleaner paragraph output.

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
- switching `Raw` / `Format-only` / `Clarify` mode
- switching recognition engine (`Apple Speech` / `Whisper` / `OpenAI Cloud`)
- switching Whisper model (`tiny` / `base` / `small` / `medium` / `large-v3`)
- switching language (`System Default` / `zh-Hans` / `en-US`)
- requesting microphone/speech permission
- changing hotkey preset in-app
- viewing recent transcript history
- one-click `Copy + Undo Last Insert` rollback
- opening/editing terminology dictionary (`term` and `source => target` rules)
- opening/editing OpenAI cloud settings (`openai.env`)
- opening permission settings
- opening local runtime logs

`Mode`, `Recognition Engine`, `Whisper Model`, `Hotkey`, and `Language` selections persist across restarts.

Build double-clickable app bundle:
```bash
cd "/Users/axton/Documents/DailyWork🌴/Project Files/Code Projects/verbatim-flow"
./scripts/build-native-app.sh
open "/Users/axton/Documents/DailyWork🌴/Project Files/Code Projects/verbatim-flow/apps/mac-client/dist/VerbatimFlow.app"
```

The build script signs with a stable designated requirement (`identifier "com.axtonliu.verbatimflow"`), so Accessibility/Input Monitoring permissions do not invalidate on each rebuild.

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

Terminology dictionary file:
```bash
~/Library/Application\ Support/VerbatimFlow/terminology.txt
```

OpenAI cloud settings file:
```bash
~/Library/Application\ Support/VerbatimFlow/openai.env
```
