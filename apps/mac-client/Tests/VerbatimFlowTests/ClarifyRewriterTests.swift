import XCTest
@testable import VerbatimFlow

final class ClarifyRewriterTests: XCTestCase {
    func testBuildSystemPromptIncludesStructureAndTerms() {
        let prompt = ClarifyRewriter.buildSystemPrompt(
            localeIdentifier: "zh-CN",
            terminologyHints: ["Tana", "OpenAI", "B-roll"]
        )

        XCTAssertTrue(prompt.contains("bullet list"))
        XCTAssertTrue(prompt.contains("Preferred terms: Tana, OpenAI, B-roll"))
        XCTAssertTrue(prompt.contains("full-width Chinese punctuation"))
    }

    func testNormalizeOutputConvertsNumberedListToBullets() {
        let normalized = ClarifyRewriter.normalizeOutput("""
        1. 第一项
        2. 第二项

        3. 第三项
        """)

        XCTAssertEqual(normalized, """
        - 第一项
        - 第二项

        - 第三项
        """)
    }
}
