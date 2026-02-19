# verbatim-flow - project rules

## Scope
Build a controllable dictation stack that can rival tools like Typeless/Wispr in practical writing speed while preserving user intent.

## Working rules
- Prioritize end-to-end latency and text fidelity over feature breadth.
- Default output mode must be `Raw` (no paraphrasing).
- Any `Format-only` mode must be guarded by token-level diff checks.
- Keep provider-agnostic interfaces (local and cloud ASR both supported).

## Key decisions

### [Speed first, not offline-first] (2026-02-18)
**Decision**: Optimize for low latency regardless of local/cloud deployment. Offline is optional.
**Reason**: User priority is responsiveness, not strict offline requirement.

### [Never rewrite by default] (2026-02-18)
**Decision**: The default text path is raw transcription. Formatting is opt-in and constrained.
**Reason**: Existing tools over-edit original text and reduce trust.

### [Python MVP as active path] (2026-02-18)
**Decision**: Use `apps/mac-client/python` as the active implementation path for now.
**Reason**: Native Swift build is blocked on this machine by SDK/compiler mismatch; Python path delivers a runnable end-to-end client immediately.

### [Compute type auto-fallback] (2026-02-18)
**Decision**: If requested compute type (e.g. `int8_float16`) is unsupported by local backend, automatically fall back to `int8`.
**Reason**: Keep dictation flow available without manual restarts or flag changes when hardware/backend constraints vary.

### [Native Swift path re-enabled] (2026-02-18)
**Decision**: Continue native AppCore development under `apps/mac-client` in parallel with Python MVP.
**Reason**: After installing full Xcode, AppKit compilation and Swift package build/test are now working again.

### [Menu bar AppCore baseline] (2026-02-18)
**Decision**: Native app now runs as a menu bar utility (`VF`) with pause/resume, mode switching, and permission shortcuts.
**Reason**: This provides a practical native control surface without blocking on full GUI settings windows.

### [Native .app bundle build path] (2026-02-18)
**Decision**: Build a standalone app bundle via `scripts/build-native-app.sh` from the Swift package release binary.
**Reason**: Enables double-click launch and sharing without requiring terminal `swift run`.

### [Permission request + hotkey presets in menu bar] (2026-02-18)
**Decision**: Add in-app menu actions for requesting speech/microphone permission and switching hotkey presets at runtime.
**Reason**: macOS microphone permissions cannot always be manually inserted before first request, and hotkey changes should not require relaunch with CLI flags.

### [Persisted controls + transcript rollback] (2026-02-18)
**Decision**: Persist `mode`, `hotkey`, and `language` with `UserDefaults`; add status bar recent transcript history and a one-click `Copy + Undo Last Insert` action.
**Reason**: Users need stable preferences across restarts and a fast recovery path when a transcript should be reverted.

### [Runtime feedback + permission diagnostics] (2026-02-18)
**Decision**: Add visible menu bar runtime indicator (`VF`, `VF●`, `VF…`, `VF⏸`), explicit hotkey press/release logs, and permission snapshot reporting with in-app alert on request.
**Reason**: Users need immediate confirmation that hotkeys are firing and clear diagnostics when permissions block recording.

### [Deterministic app signing for permission stability] (2026-02-18)
**Decision**: Re-sign packaged `.app` with fixed identifier `com.axtonliu.verbatimflow` in `build-native-app.sh`.
**Reason**: Unsafely wrapped binaries can appear granted in settings but still fail runtime permission checks due unstable process identity.

### [Permission request hardening] (2026-02-18)
**Decision**: Permission requests now temporarily foreground the app, use timeout-safe callbacks, and prefer `AVAudioApplication` microphone APIs on macOS 14+.
**Reason**: Some systems failed to surface mic/speech prompts from menu-bar-only flow, causing indefinite `Not Determined` state.

## Next implementation target
- Implement a minimal vertical slice:
  - push-to-talk hotkey
  - streaming ASR
  - format-only guard
  - text injection into focused app
