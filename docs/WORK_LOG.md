# VerbatimFlow Work Log

## 2026-02-19 - Hotkey "press accepted" handshake fix

### User report
- Around 8:13, user saw another "press not released" incident.
- Runtime logs showed:
  - extra `flagsChanged pressed` while app was `processing`
  - app correctly rejected it (`runtimeState=processing`)
  - but monitor still treated it as active press lifecycle

### Diagnosis
- State gating existed only in `handleHotkeyPressed()`.
- `HotkeyMonitor` had already set internal `isPressed = true` before app-side rejection.
- This created a pseudo pressed lifecycle that later consumed release unexpectedly.

### Fix implemented
- `HotkeyMonitor`:
  - `onPressed` callback changed to `() -> Bool`.
  - only enters `pressed` state when callback returns `true`.
  - logs `pressed ignored by consumer` when rejected.
- `AppController`:
  - added synchronous gate `shouldAcceptHotkeyPress()` in bridge callback.
  - rejects press when state is not `ready` or when already recording.
  - keeps async handler for actual recording start.

### Validation
- `swift test` passed after change.
- Build confirms updated files compile:
  - `HotkeyMonitor.swift`
  - `AppController.swift`

### Regression prevention rule
- For hotkey lifecycle code, do not let monitor state transition precede consumer acceptance.
- Keep this as a hard constraint for future menu/engine refactors.

## 2026-02-19 - Stability hardening after menu/HTTPS refactor

### Context
- User reported two regressions after recent changes:
  - Codex chat input insertion stopped working.
  - Hotkey release occasionally remained stuck (hold-to-talk did not end on release).

### What happened
1. Initial insertion hardening introduced a Codex-specific forced paste path.
2. That override fixed one scenario but broke another scenario in the same Codex input.
3. Hotkey stuck release still happened intermittently on modifier-only combo (`shift+option`).

### Root-cause notes
- Insertion:
  - Codex input behavior was not stable enough for a hardcoded single insertion strategy.
  - App-specific force override is risky without runtime toggle and broader validation.
- Hotkey:
  - Watchdog used one signal source (`flags`) and could miss stale-state edge cases.
  - Modifier-only hotkeys are more sensitive to event loss / state skew.

### Final decisions
- Insertion strategy:
  - Reverted to robust baseline: `AX selected-text first -> Cmd+V fallback`.
  - Avoid app-specific hard override unless reproducible across environments.
  - For Codex specifically (after repeated evidence of AX false-positive), switch to Unicode event typing path.
- Hotkey watchdog:
  - Keep event callback flow unchanged.
  - Add dual-source release verification:
    - modifier flags state
    - physical key state for left/right modifier keys
  - Add mismatch debounce threshold before forced release.

### Implementation details
- Restored insertion baseline in:
  - `apps/mac-client/Sources/VerbatimFlow/TextInjector.swift`
- Added Codex Unicode typing path in:
  - `apps/mac-client/Sources/VerbatimFlow/TextInjector.swift`
- Hardened hotkey release watchdog in:
  - `apps/mac-client/Sources/VerbatimFlow/HotkeyMonitor.swift`
  - Added mismatch counter and physical modifier key checks.
- Updated incident documentation:
  - `docs/REGRESSION_LOG.md`

### Validation run
- `swift test` passed after each fix round.
- App rebuilt and relaunched from:
  - `./scripts/build-native-app.sh`
  - `open apps/mac-client/dist/VerbatimFlow.app`

### Commits
- `2b300bc` fix: harden codex insertion and enforce https for openai cloud
- `709ab68` fix: restore ax-first insertion strategy for codex compatibility
- (current) hotkey watchdog stabilization + work-log updates

### Lessons / rules for future changes
- Never ship app-specific insertion forcing without:
  - runtime toggle, and
  - at least one manual pass in Codex + Terminal + one standard editor.
- For global hotkeys, always keep:
  - event-driven path, and
  - independent watchdog fallback with at least two state sources.
- Any regression fix must be documented the same day in:
  - `docs/REGRESSION_LOG.md`
  - `docs/WORK_LOG.md`

## 2026-02-19 - Next optimization backlog (user-prioritized)

### P1 - Fault tolerance for long dictation
- Goal:
  - If transcription fails after a long recording, user must be able to retry without re-speaking.
- Planned baseline:
  - Keep the recorded audio file until transcription succeeds or user discards it.
  - Add "Retry last audio" action (menu command) to re-run transcription with same audio.
  - Add "Save failed audio" fallback location for manual recovery.

### P1 - Simple voice command layer
- Goal:
  - Keep default mode as `raw`, but allow one-shot command such as "整理成书面语" for the current utterance.
- Planned baseline:
  - Parse a small command prefix set in recognized text.
  - Command modifies post-processing mode for the current segment only.
  - Do not change global mode unless explicitly requested.

### P2 - Readability post-processing
- Goal:
  - Improve line breaks and Chinese punctuation quality.
- Planned baseline:
  - Optional punctuation normalization (`English comma/period` -> `Chinese punctuation`) when locale is Chinese.
  - Optional lightweight paragraph split by pause/length heuristics.
  - Keep disabled by default until quality validated.

## 2026-02-19 - Execution Todo (Locked Order)

### Current plan
- [x] Todo 1 (P1): Long dictation fault tolerance
  - Keep last recording for retry when transcription fails.
  - Add `Retry last audio` action.
  - Add failed-audio persistence path and clear policy.
- [ ] Todo 2 (P1): One-shot voice commands
  - Support command phrases like "把以上内容整理成书面语" for current utterance only.
  - Keep global mode unchanged unless explicitly switched.
- [ ] Todo 3 (P2): Readability polish
  - Chinese punctuation normalization (optional).
  - Auto paragraph split (optional, conservative default).

### Regression gate (must pass before moving to next todo)
- Automated:
  - `swift test` must pass.
- Manual smoke:
  - Codex input insertion works (unicode typing path).
  - Terminal/iTerm insertion works.
  - One standard editor insertion works (AX or paste fallback).
  - Hotkey hold/release loop test (at least 20 rounds, including long hold) has no stuck recording.
  - Permissions status remains healthy after rebuild/relaunch.
- Rule:
  - Do not start next todo until current todo passes this gate and is logged in `docs/REGRESSION_LOG.md`.

### Todo 1 implementation note
- Added failed-recording persistence:
  - Path: `~/Library/Application Support/VerbatimFlow/FailedRecordings/last_failed_recording.m4a`
  - Metadata: `~/Library/Application Support/VerbatimFlow/FailedRecordings/last_failed_recording.json`
- Added menu action:
  - `Recent transcripts -> Retry Last Failed Audio`
- Clear policy:
  - Overwrite previous failed audio when a new failure happens.
  - Automatically clear failed audio + metadata after successful retry.
- Verification:
  - Automated gate passed (`swift test`).
  - Manual smoke pending user-side interactive validation.
