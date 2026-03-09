import XCTest
@testable import VerbatimFlow

final class DictationVocabularyTests: XCTestCase {
    func testTranscriptionPromptTermsExcludeContextualBuiltIns() {
        let terms = DictationVocabulary.transcriptionPromptTerms(customHints: [])

        XCTAssertTrue(terms.contains("Claude"))
        XCTAssertTrue(terms.contains("Gemini"))
        XCTAssertFalse(terms.contains("Tana"))
    }

    func testFuzzyCorrectionTermsStillIncludeContextualBuiltIns() {
        let terms = DictationVocabulary.fuzzyCorrectionTerms(customHints: [])

        XCTAssertTrue(terms.contains("Tana"))
    }

    func testCorrectionPolicyForTanaIsContextual() {
        let policy = DictationVocabulary.correctionPolicy(for: "Tana")

        switch policy {
        case .contextual(let keywords):
            XCTAssertTrue(keywords.contains("笔记"))
        case .always:
            XCTFail("Expected contextual policy for Tana")
        }
    }

    func testExactCaseTargetSupportsBrandNormalization() {
        XCTAssertEqual(DictationVocabulary.exactCaseTarget(for: "claude"), "Claude")
        XCTAssertEqual(DictationVocabulary.exactCaseTarget(for: "youtube"), "YouTube")
        XCTAssertNil(DictationVocabulary.exactCaseTarget(for: "workflow"))
    }

    func testAliasMatchSupportsContextualOverrides() {
        let alias = DictationVocabulary.aliasMatch(for: "GIT")

        XCTAssertEqual(alias?.target, "GPT")
        XCTAssertNotNil(alias)
    }
}
