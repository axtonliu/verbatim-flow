import XCTest
@testable import VerbatimFlow

final class MixedLanguageEnhancerTests: XCTestCase {
    func testApplyJoinsSplitTechnicalTerms() {
        let result = MixedLanguageEnhancer.apply(
            text: "这个功能会发到 open ai 和 you tube 上",
            localeIdentifier: "zh-CN",
            vocabularyHints: ["OpenAI", "YouTube"]
        )

        XCTAssertEqual(result.text, "这个功能会发到 OpenAI 和 YouTube 上")
        XCTAssertEqual(result.appliedRules, ["open ai -> OpenAI", "you tube -> YouTube"])
    }

    func testApplyJoinsHyphenatedAndNumericTerms() {
        let result = MixedLanguageEnhancer.apply(
            text: "我想测试 b roll 和 gpt 5 还有 i term 2",
            localeIdentifier: "zh-CN",
            vocabularyHints: ["B-roll", "GPT-5", "iTerm2"]
        )

        XCTAssertEqual(result.text, "我想测试 B-roll 和 GPT-5 还有 iTerm2")
        XCTAssertEqual(result.appliedRules, ["b roll -> B-roll", "gpt 5 -> GPT-5", "i term 2 -> iTerm2"])
    }

    func testContextualTermDoesNotOverCorrectWithoutContext() {
        let result = MixedLanguageEnhancer.apply(
            text: "这个 ta na 说的其实没错",
            localeIdentifier: "zh-CN",
            vocabularyHints: ["Tana"]
        )

        XCTAssertEqual(result.text, "这个 ta na 说的其实没错")
        XCTAssertEqual(result.appliedRules, [])
    }

    func testContextualTermCorrectsWhenKnowledgeContextExists() {
        let result = MixedLanguageEnhancer.apply(
            text: "我把 ta na 里的笔记同步过来了",
            localeIdentifier: "zh-CN",
            vocabularyHints: ["Tana"]
        )

        XCTAssertEqual(result.text, "我把 Tana 里的笔记同步过来了")
        XCTAssertEqual(result.appliedRules, ["ta na -> Tana"])
    }

    func testExactCaseNormalizationForBrandTerms() {
        let result = MixedLanguageEnhancer.apply(
            text: "我现在用 claude 和 gpt 测试 openai",
            localeIdentifier: "zh-CN",
            vocabularyHints: ["Claude", "GPT", "OpenAI"]
        )

        XCTAssertEqual(result.text, "我现在用 Claude 和 GPT 测试 OpenAI")
        XCTAssertEqual(result.appliedRules, ["claude -> Claude", "gpt -> GPT", "openai -> OpenAI"])
    }

    func testAIContextCorrectsGeminiAlias() {
        let result = MixedLanguageEnhancer.apply(
            text: "Claude 和 GPT 都更理性，而金版呢会偏销售风格",
            localeIdentifier: "zh-CN",
            vocabularyHints: ["Claude", "GPT", "Gemini"]
        )

        XCTAssertEqual(result.text, "Claude 和 GPT 都更理性，而 Gemini 呢会偏销售风格")
        XCTAssertEqual(result.appliedRules, ["金版 -> Gemini"])
    }

    func testAIContextCorrectsGITToGPT() {
        let result = MixedLanguageEnhancer.apply(
            text: "这个 GIT 模型更像理工男",
            localeIdentifier: "zh-CN",
            vocabularyHints: ["GPT", "Git"]
        )

        XCTAssertEqual(result.text, "这个 GPT 模型更像理工男")
        XCTAssertEqual(result.appliedRules, ["GIT -> GPT"])
    }

    func testGitStaysGitOutsideAIContext() {
        let result = MixedLanguageEnhancer.apply(
            text: "这个 Git 仓库我已经 push 到 GitHub 了",
            localeIdentifier: "zh-CN",
            vocabularyHints: ["Git", "GitHub", "GPT"]
        )

        // "Git" should remain unchanged here because the GPT alias rule is contextual
        // and this sentence lacks AI-specific nearby keywords.
        XCTAssertEqual(result.text, "这个 Git 仓库我已经 push 到 GitHub 了")
        XCTAssertEqual(result.appliedRules, [])
    }
}
