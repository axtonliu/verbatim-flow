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
