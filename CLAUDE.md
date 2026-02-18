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

## Next implementation target
- Implement a minimal vertical slice:
  - push-to-talk hotkey
  - streaming ASR
  - format-only guard
  - text injection into focused app
