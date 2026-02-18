import unittest

from verbatim_flow.hotkey import parse_hotkey


class HotkeyParserTests(unittest.TestCase):
    def test_accepts_option_alias(self) -> None:
        spec = parse_hotkey("shift+option+space")
        self.assertEqual(spec.modifiers, frozenset({"shift", "opt"}))
        self.assertEqual(spec.key, "space")

    def test_accepts_command_alias(self) -> None:
        spec = parse_hotkey("command+shift+space")
        self.assertEqual(spec.modifiers, frozenset({"cmd", "shift"}))
        self.assertEqual(spec.key, "space")

    def test_rejects_unsupported_modifier(self) -> None:
        with self.assertRaises(ValueError):
            parse_hotkey("meta+space")


if __name__ == "__main__":
    unittest.main()
