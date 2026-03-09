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

    func testSaveAndLoadClarifyHotkey() throws {
        let defaults = makeIsolatedDefaults()
        let preferences = AppPreferences(defaults: defaults)
        let expected = try HotkeyParser.parse(combo: "ctrl+shift+space")

        preferences.saveClarifyHotkey(expected)
        let loaded = preferences.loadClarifyHotkey()

        XCTAssertEqual(loaded?.keyCode, expected.keyCode)
        XCTAssertEqual(loaded?.display.lowercased(), "ctrl+shift+space")
        XCTAssertTrue(loaded?.modifiers.contains(.control) == true)
        XCTAssertTrue(loaded?.modifiers.contains(.shift) == true)
    }

    func testSaveAndLoadLanguageSelection() {
        let defaults = makeIsolatedDefaults()
        let preferences = AppPreferences(defaults: defaults)

        preferences.saveLanguageSelection(AppPreferences.systemLanguageToken)
        XCTAssertEqual(preferences.loadLanguageSelection(), AppPreferences.systemLanguageToken)
    }

    func testSaveAndLoadRecognitionEngine() {
        let defaults = makeIsolatedDefaults()
        let preferences = AppPreferences(defaults: defaults)

        preferences.saveRecognitionEngine(.whisper)
        XCTAssertEqual(preferences.loadRecognitionEngine(), .whisper)
    }

    func testSaveAndLoadWhisperModel() {
        let defaults = makeIsolatedDefaults()
        let preferences = AppPreferences(defaults: defaults)

        preferences.saveWhisperModel(.medium)
        XCTAssertEqual(preferences.loadWhisperModel(), .medium)
    }

    func testSaveAndLoadOpenAIModel() {
        let defaults = makeIsolatedDefaults()
        let preferences = AppPreferences(defaults: defaults)

        preferences.saveOpenAIModel(.whisper1)
        XCTAssertEqual(preferences.loadOpenAIModel(), .whisper1)
    }

    func testSaveAndLoadQwenModel() {
        let defaults = makeIsolatedDefaults()
        let preferences = AppPreferences(defaults: defaults)

        preferences.saveQwenModel(.large)
        XCTAssertEqual(preferences.loadQwenModel(), .large)
    }

    func testSaveAndLoadQwenRecognitionEngine() {
        let defaults = makeIsolatedDefaults()
        let preferences = AppPreferences(defaults: defaults)

        preferences.saveRecognitionEngine(.qwen)
        XCTAssertEqual(preferences.loadRecognitionEngine(), .qwen)
    }

    private func makeIsolatedDefaults() -> UserDefaults {
        let suiteName = "verbatimflow.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
