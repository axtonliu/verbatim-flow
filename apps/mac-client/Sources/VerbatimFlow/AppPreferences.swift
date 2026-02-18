import Foundation

final class AppPreferences {
    static let systemLanguageToken = "system"

    private enum Key {
        static let mode = "verbatimflow.mode"
        static let hotkey = "verbatimflow.hotkey"
        static let languageSelection = "verbatimflow.languageSelection"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadMode() -> OutputMode? {
        guard let rawValue = defaults.string(forKey: Key.mode) else {
            return nil
        }
        return OutputMode(rawValue: rawValue)
    }

    func saveMode(_ mode: OutputMode) {
        defaults.set(mode.rawValue, forKey: Key.mode)
    }

    func loadHotkey() -> Hotkey? {
        guard let combo = defaults.string(forKey: Key.hotkey) else {
            return nil
        }
        return try? HotkeyParser.parse(combo: combo)
    }

    func saveHotkey(_ hotkey: Hotkey) {
        defaults.set(hotkey.display.lowercased(), forKey: Key.hotkey)
    }

    func loadLanguageSelection() -> String? {
        defaults.string(forKey: Key.languageSelection)
    }

    func saveLanguageSelection(_ value: String) {
        defaults.set(value, forKey: Key.languageSelection)
    }
}
