import XCTest
@testable import VerbatimFlow

final class TextGuardTests: XCTestCase {
    func testRawModeReturnsOriginal() {
        let guardEngine = TextGuard(mode: .raw)
        let result = guardEngine.apply(raw: "  hello   world  ")
        XCTAssertEqual(result.text, "hello   world")
        XCTAssertFalse(result.fellBackToRaw)
    }

    func testFormatOnlyKeepsSemantics() {
        let guardEngine = TextGuard(mode: .formatOnly)
        let result = guardEngine.apply(raw: "Hello ,world !")
        XCTAssertEqual(result.text, "Hello, world!")
        XCTAssertFalse(result.fellBackToRaw)
    }

    func testFormatOnlyUsesFullWidthChinesePunctuation() {
        let guardEngine = TextGuard(mode: .formatOnly)
        let result = guardEngine.apply(raw: "你好, 世界! 这个叫 commit.")
        XCTAssertEqual(result.text, "你好，世界！这个叫 commit。")
        XCTAssertFalse(result.fellBackToRaw)
    }

    func testFormatOnlyKeepsAsciiPunctuationInsideURLs() {
        let guardEngine = TextGuard(mode: .formatOnly)
        let result = guardEngine.apply(raw: "访问 https://axtonliu.ai/test, 谢谢.")
        XCTAssertEqual(result.text, "访问 https://axtonliu.ai/test，谢谢。")
        XCTAssertFalse(result.fellBackToRaw)
    }

    func testFormatOnlyAddsLightweightChinesePunctuationWhenMissing() {
        let guardEngine = TextGuard(mode: .formatOnly)
        let result = guardEngine.apply(raw: "你看现在这个头的标点又没有了")
        XCTAssertEqual(result.text, "你看，现在这个头的标点又没有了。")
        XCTAssertFalse(result.fellBackToRaw)
    }

    func testFormatOnlyDoesNotForcePeriodOnShortChineseFragment() {
        let guardEngine = TextGuard(mode: .formatOnly)
        let result = guardEngine.apply(raw: "计划今天要发的")
        XCTAssertEqual(result.text, "计划今天要发的")
        XCTAssertFalse(result.fellBackToRaw)
    }

    func testFormatOnlyAddsLightweightParagraphsForLongChineseDictation() {
        let guardEngine = TextGuard(mode: .formatOnly)
        let result = guardEngine.apply(
            raw: "好，我已经把这篇文章存到项目目录里了。然后这个对比结果我已经做了截图保留。其实这也很好地体现了我的一个观点，就是 Claude 比较均衡客观，而且文字功底更好。GPT 更像理工男，更注重严谨的逻辑。"
        )

        XCTAssertEqual(
            result.text,
            "好，我已经把这篇文章存到项目目录里了。然后这个对比结果我已经做了截图保留。\n\n其实这也很好地体现了我的一个观点，就是 Claude 比较均衡客观，而且文字功底更好。GPT 更像理工男，更注重严谨的逻辑。"
        )
        XCTAssertFalse(result.fellBackToRaw)
    }

    func testFormatOnlyKeepsShortChineseTwoSentenceTextInSingleParagraph() {
        let guardEngine = TextGuard(mode: .formatOnly)
        let result = guardEngine.apply(raw: "我已经提交了。请你看一下。")

        XCTAssertEqual(result.text, "我已经提交了。请你看一下。")
        XCTAssertFalse(result.fellBackToRaw)
    }

    func testClarifyPreprocessingDoesNotInsertParagraphBreaks() {
        let guardEngine = TextGuard(mode: .clarify)
        let result = guardEngine.apply(
            raw: "好，我已经把这篇文章存到项目目录里了。然后这个对比结果我已经做了截图保留。其实这也很好地体现了我的一个观点。"
        )

        XCTAssertFalse(result.text.contains("\n\n"))
        XCTAssertFalse(result.fellBackToRaw)
    }

    func testFormatOnlyDoesNotSplitParagraphOnSemicolonsAlone() {
        let guardEngine = TextGuard(mode: .formatOnly)
        let result = guardEngine.apply(
            raw: "第一点是把文档补齐；第二点是补测试；第三点是再做一次回归。最后再准备发布说明。"
        )

        XCTAssertEqual(
            result.text,
            "第一点是把文档补齐；第二点是补测试；第三点是再做一次回归。最后再准备发布说明。"
        )
        XCTAssertFalse(result.text.contains("\n\n"))
        XCTAssertFalse(result.fellBackToRaw)
    }
}
