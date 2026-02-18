from __future__ import annotations

from dataclasses import dataclass
from typing import Callable, Set

from pynput import keyboard


@dataclass(frozen=True)
class HotkeySpec:
    modifiers: frozenset[str]
    key: str


_MODIFIER_ALIASES = {
    "cmd": "cmd",
    "command": "cmd",
    "⌘": "cmd",
    "opt": "opt",
    "option": "opt",
    "alt": "opt",
    "⌥": "opt",
    "ctrl": "ctrl",
    "control": "ctrl",
    "⌃": "ctrl",
    "shift": "shift",
    "⇧": "shift",
}

_KEY_ALIASES = {
    "spacebar": "space",
}


def parse_hotkey(combo: str) -> HotkeySpec:
    parts = [p.strip().lower() for p in combo.split("+") if p.strip()]
    if len(parts) < 2:
        raise ValueError("hotkey must include modifiers and a key, e.g. ctrl+shift+space")

    key = _KEY_ALIASES.get(parts[-1], parts[-1])
    modifiers: set[str] = set()
    unsupported: list[str] = []
    for mod in parts[:-1]:
        canonical = _MODIFIER_ALIASES.get(mod)
        if canonical is None:
            unsupported.append(mod)
            continue
        modifiers.add(canonical)

    if unsupported:
        bad = ", ".join(sorted(unsupported))
        raise ValueError(f"unsupported modifiers: {bad}")

    return HotkeySpec(modifiers=frozenset(modifiers), key=key)


def _normalize_key(key_obj: keyboard.Key | keyboard.KeyCode) -> str | None:
    if isinstance(key_obj, keyboard.KeyCode):
        if key_obj.char:
            return key_obj.char.lower()
        return None

    mapping = {
        keyboard.Key.space: "space",
        keyboard.Key.shift: "shift",
        keyboard.Key.shift_l: "shift",
        keyboard.Key.shift_r: "shift",
        keyboard.Key.alt: "opt",
        keyboard.Key.alt_l: "opt",
        keyboard.Key.alt_r: "opt",
        keyboard.Key.ctrl: "ctrl",
        keyboard.Key.ctrl_l: "ctrl",
        keyboard.Key.ctrl_r: "ctrl",
        keyboard.Key.cmd: "cmd",
        keyboard.Key.cmd_l: "cmd",
        keyboard.Key.cmd_r: "cmd",
    }
    return mapping.get(key_obj)


class HoldToTalkHotkeyMonitor:
    def __init__(
        self,
        combo: str,
        on_press: Callable[[], None],
        on_release: Callable[[], None],
    ) -> None:
        self.spec = parse_hotkey(combo)
        self.on_press = on_press
        self.on_release = on_release
        self._pressed: Set[str] = set()
        self._active = False
        self._listener: keyboard.Listener | None = None

    def start(self) -> None:
        self._listener = keyboard.Listener(on_press=self._handle_press, on_release=self._handle_release)
        self._listener.daemon = True
        self._listener.start()

    def join(self) -> None:
        if self._listener:
            self._listener.join()

    def _match_combo(self) -> bool:
        return self.spec.key in self._pressed and self.spec.modifiers.issubset(self._pressed)

    def _handle_press(self, key_obj: keyboard.Key | keyboard.KeyCode) -> None:
        normalized = _normalize_key(key_obj)
        if not normalized:
            return
        self._pressed.add(normalized)
        if not self._active and self._match_combo():
            self._active = True
            self.on_press()

    def _handle_release(self, key_obj: keyboard.Key | keyboard.KeyCode) -> None:
        normalized = _normalize_key(key_obj)
        if not normalized:
            return

        was_trigger_key = normalized == self.spec.key
        if self._active and was_trigger_key:
            self._active = False
            self.on_release()

        if normalized in self._pressed:
            self._pressed.remove(normalized)
