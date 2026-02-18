import XCTest
@testable import VerbatimFlow

final class AppPreferencesTests: XCTestCase {
    func testSaveAndLoadMode() {
        let defaults = makeIsolatedDefaults()
        let preferences = AppPreferences(defaults: defaults)

        preferences.saveMode(.formatOnly)
        XCTAssertEqual(preferences.loadMode(), .formatOnly)
    }

    func testSaveAndLoadHotkey() throws {
        let defaults = makeIsolatedDefaults()
        let preferences = AppPreferences(defaults: defaults)
        let expected = try HotkeyParser.parse(combo: "shift+option+space")

        preferences.saveHotkey(expected)
        let loaded = preferences.loadHotkey()

        XCTAssertEqual(loaded?.keyCode, expected.keyCode)
        XCTAssertEqual(loaded?.display.lowercased(), "shift+option+space")
        XCTAssertTrue(loaded?.modifiers.contains(.shift) == true)
        XCTAssertTrue(loaded?.modifiers.contains(.option) == true)
    }

    func testSaveAndLoadLanguageSelection() {
        let defaults = makeIsolatedDefaults()
        let preferences = AppPreferences(defaults: defaults)

        preferences.saveLanguageSelection(AppPreferences.systemLanguageToken)
        XCTAssertEqual(preferences.loadLanguageSelection(), AppPreferences.systemLanguageToken)
    }

    private func makeIsolatedDefaults() -> UserDefaults {
        let suiteName = "verbatimflow.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
