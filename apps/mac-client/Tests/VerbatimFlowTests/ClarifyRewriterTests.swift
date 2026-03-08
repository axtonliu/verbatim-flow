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
        XCTAssertTrue(prompt.contains("Never answer the speaker's question"))
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

    func testBuildUserPromptWrapsDictationInTags() {
        let prompt = ClarifyRewriter.buildUserPrompt(
            localeIdentifier: "zh-CN",
            text: "接下来需要进行哪些任务"
        )

        XCTAssertTrue(prompt.contains("Rewrite only the transcript inside <dictation> tags."))
        XCTAssertTrue(prompt.contains("<dictation>\n接下来需要进行哪些任务\n</dictation>"))
    }

    func testRejectsAssistantAnswerForQuestionInput() {
        let shouldReject = ClarifyRewriter.shouldRejectAsAssistantAnswer(
            input: "接下来需要进行哪些任务",
            output: "好的，接下来可以进行以下优化任务：- 检查代码中的潜在bug\n- 优化性能"
        )

        XCTAssertTrue(shouldReject)
    }

    func testAllowsRewrittenQuestion() {
        let shouldReject = ClarifyRewriter.shouldRejectAsAssistantAnswer(
            input: "接下来需要进行哪些任务",
            output: "接下来需要进行哪些任务？"
        )

        XCTAssertFalse(shouldReject)
    }

    func testAllowsBulletListWhenItClearlyRewritesUserListDictation() {
        let shouldReject = ClarifyRewriter.shouldRejectAsAssistantAnswer(
            input: "第一项检查代码第二项补测试第三项更新文档",
            output: "- 第一项：检查代码\n- 第二项：补测试\n- 第三项：更新文档"
        )

        XCTAssertFalse(shouldReject)
    }
}
