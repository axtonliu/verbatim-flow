# VerbatimFlow Regression Log

## 2026-02-19: Intermittent insertion failure in Codex input

- Symptom:
  - Hotkey flow completed and transcript was produced.
  - `Last event` could show inserted text, but text did not appear in Codex chat input consistently.
- Scope:
  - Observed mainly in `com.openai.codex` input box.
  - Terminal insertion path was unaffected.
- Root-cause hypothesis:
  - AX selected-text write (`kAXSelectedTextAttribute`) can return success on some custom editors while visual text state is not updated reliably.
- Fix:
  - Add app-specific insertion policy: for `com.openai.codex*`, skip AX selected-text path and use deterministic `Cmd+V` fallback.
  - Keep AX path as default for normal editors.
- Validation:
  - 2026-02-19 follow-up: forcing `Cmd+V` for Codex introduced a hard regression for some users.
  - Final policy changed to `AX first -> Cmd+V fallback` for all non-terminal apps.
  - Keep app-specific hardcoded insertion overrides disabled unless reproducible evidence exists.
  - 2026-02-19 second follow-up: Codex still had intermittent "AX success but no visible insertion".
  - Codex insertion path changed to Unicode event typing (same class as terminal path), bypassing AX/paste for Codex only.

## 2026-02-19: Cloud endpoint transport guard

- Risk:
  - Misconfigured `VERBATIMFLOW_OPENAI_BASE_URL` could accidentally use plain HTTP.
- Fix:
  - Enforce HTTPS by default for OpenAI transcription endpoint.
  - Add explicit development escape hatch: `VERBATIMFLOW_ALLOW_INSECURE_OPENAI_BASE_URL=1`.
  - TLS calls use curl HTTPS-only protocol constraint when endpoint is HTTPS.

## 2026-02-19: Modifier hotkey sometimes stuck in pressed state

- Symptom:
  - User released hotkey (`shift+option`), but app occasionally remained in recording state until extra key action.
- Root-cause hypothesis:
  - Watchdog release logic relied on modifier flags only.
  - In some sessions, flags could remain stale for a short period, so release was not triggered.
- Fix:
  - Keep event-driven release path unchanged.
  - Harden watchdog with dual-source state check:
    - `flags` state
    - physical key state (`CGEventSource.keyState`) for left/right modifier keys
  - Add mismatch threshold debounce before forced release to avoid false positives.
- Guardrail:
  - Do not rely on a single signal source for modifier-only hotkeys.
  - Any future hotkey refactor must preserve a watchdog fallback path independent from event callbacks.

## 2026-02-19: Failed-transcription recovery baseline

- Feature:
  - Persist last failed recording for retry without re-speaking.
- Storage:
  - `~/Library/Application Support/VerbatimFlow/FailedRecordings/last_failed_recording.m4a`
  - `~/Library/Application Support/VerbatimFlow/FailedRecordings/last_failed_recording.json`
- Recovery action:
  - Menu: `Recent transcripts -> Retry Last Failed Audio`
- Clear policy:
  - New failure overwrites previous failed recording.
  - Successful retry clears both audio and metadata.

## 2026-02-19: Extra press during processing caused pseudo pressed lifecycle

- Symptom:
  - User released hotkey, but occasionally appeared as "press not released" in menu state.
  - Repro logs showed an extra `flagsChanged pressed` while app state was `processing`.
- Evidence (runtime log):
  - `[hotkey-handler] ignored pressed because runtimeState=processing`
  - then later `[hotkey-handler] ignored released because isRecording=false`
- Root cause:
  - `HotkeyMonitor` accepted any press callback and flipped internal `isPressed=true` before app state gating.
  - When app rejected press at handler layer, monitor still owned a pressed lifecycle and consumed a later release.
- Fix:
  - Changed `HotkeyMonitor` press callback contract from `() -> Void` to `() -> Bool`.
  - `AppController` now performs a synchronous bridge gate (`stopped/ready/isRecording`) before accepting press.
  - If rejected, monitor does not enter pressed state and does not start watchdog.
- Guardrail:
  - Hotkey monitor must only transition to `pressed` after consumer explicitly accepts the press.

## Manual regression checklist (before release)

- Permissions:
  - Accessibility, Input Monitoring, Microphone are all granted for current app identity.
- Insertion:
  - Test insertion in Codex input (`com.openai.codex`) with hotkey press/release.
  - Test insertion in Terminal/iTerm to confirm terminal path still works.
  - Test one standard editor (TextEdit/Notes) to verify AX path remains valid.
- Engine:
  - Apple Speech, Whisper, OpenAI Cloud each run one full round-trip.
- Transport:
  - OpenAI Cloud works with default HTTPS endpoint.
  - Non-HTTPS base URL is rejected unless explicit insecure override is set.
