import XCTest
@testable import VerbatimFlow

final class OpenAIAutoRouterTests: XCTestCase {
    func testAnalyzePrimaryTranscriptTriggersRetryForChinesePhoneticMisses() {
        let config = OpenAIAutoRouteConfig(
            enabled: true,
            secondaryModel: "whisper-1",
            zhOnly: true,
            minRiskScore: 2,
            minPrimaryChars: 4
        )

        let analysis = OpenAIAutoRouter.analyzePrimaryTranscript(
            "这个工具可以连接 tanaa 项目",
            localeIdentifier: "zh-Hans",
            vocabularyHints: ["Tana", "Commit"],
            config: config
        )

        XCTAssertTrue(analysis.shouldRetry)
        XCTAssertGreaterThanOrEqual(analysis.riskScore, 2)
    }

    func testAnalyzePrimaryTranscriptSkipsRetryForPureChineseLowRisk() {
        let config = OpenAIAutoRouteConfig(
            enabled: true,
            secondaryModel: "whisper-1",
            zhOnly: true,
            minRiskScore: 2,
            minPrimaryChars: 4
        )

        let analysis = OpenAIAutoRouter.analyzePrimaryTranscript(
            "今天我们继续优化语音输入体验",
            localeIdentifier: "zh-Hans",
            vocabularyHints: ["Tana", "BROLL", "Commit"],
            config: config
        )

        XCTAssertFalse(analysis.shouldRetry)
        XCTAssertLessThan(analysis.riskScore, 2)
    }

    func testSelectPreferredTranscriptChoosesSecondaryWhenTermMatchesBetter() {
        let selection = OpenAIAutoRouter.selectPreferredTranscript(
            primaryText: "这个功能支持塔纳和逼肉",
            primaryModel: "gpt-4o-mini-transcribe",
            secondaryText: "这个功能支持 Tana 和 BROLL",
            secondaryModel: "whisper-1",
            localeIdentifier: "zh-Hans",
            vocabularyHints: ["Tana", "BROLL"]
        )

        XCTAssertEqual(selection.selectedModel, "whisper-1")
        XCTAssertEqual(selection.transcript, "这个功能支持 Tana 和 BROLL")
        XCTAssertGreaterThan(selection.secondaryScore, selection.primaryScore)
    }

    func testResolveConfigPrefersEnvironmentAndAppliesDefaults() {
        let env: [String: String] = [
            "VERBATIMFLOW_OPENAI_AUTO_ROUTE": "0",
            "VERBATIMFLOW_OPENAI_AUTO_SECONDARY_MODEL": "gpt-4o-transcribe",
            "VERBATIMFLOW_OPENAI_AUTO_ROUTE_ZH_ONLY": "false",
            "VERBATIMFLOW_OPENAI_AUTO_ROUTE_MIN_RISK_SCORE": "5",
            "VERBATIMFLOW_OPENAI_AUTO_ROUTE_MIN_PRIMARY_CHARS": "12"
        ]

        let config = OpenAIAutoRouter.resolveConfig(environment: env, fileValues: [:])
        XCTAssertFalse(config.enabled)
        XCTAssertEqual(config.secondaryModel, "gpt-4o-transcribe")
        XCTAssertFalse(config.zhOnly)
        XCTAssertEqual(config.minRiskScore, 5)
        XCTAssertEqual(config.minPrimaryChars, 12)
    }
}
