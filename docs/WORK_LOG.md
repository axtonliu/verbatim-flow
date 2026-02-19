# VerbatimFlow Work Log

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
- Hotkey watchdog:
  - Keep event callback flow unchanged.
  - Add dual-source release verification:
    - modifier flags state
    - physical key state for left/right modifier keys
  - Add mismatch debounce threshold before forced release.

### Implementation details
- Restored insertion baseline in:
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
