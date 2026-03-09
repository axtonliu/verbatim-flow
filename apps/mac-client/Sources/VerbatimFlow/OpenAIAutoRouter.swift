import Foundation

struct OpenAIAutoRouteConfig: Equatable {
    let enabled: Bool
    let secondaryModel: String
    let zhOnly: Bool
    let minRiskScore: Int
    let minPrimaryChars: Int
}

struct OpenAIAutoRouteAnalysis: Equatable {
    let shouldRetry: Bool
    let riskScore: Int
    let reasons: [String]
}

struct OpenAIAutoRouteSelection: Equatable {
    let transcript: String
    let selectedModel: String
    let primaryScore: Int
    let secondaryScore: Int
    let reason: String
}

enum OpenAIAutoRouter {
    private static let defaultSecondaryModel = "whisper-1"
    private static let defaultConfig = OpenAIAutoRouteConfig(
        enabled: true,
        secondaryModel: defaultSecondaryModel,
        zhOnly: true,
        minRiskScore: 2,
        minPrimaryChars: 8
    )
    private static let latinRegex = try? NSRegularExpression(pattern: "[A-Za-z]", options: [])
    private static let hanRegex = try? NSRegularExpression(pattern: "\\p{Han}", options: [])

    static func resolveConfig(
        environment: [String: String],
        fileValues: [String: String]
    ) -> OpenAIAutoRouteConfig {
        let enabled = parseBoolean(
            resolvedSetting(
                key: "VERBATIMFLOW_OPENAI_AUTO_ROUTE",
                environment: environment,
                fileValues: fileValues
            ),
            defaultValue: defaultConfig.enabled
        )

        let secondaryModelRaw = resolvedSetting(
            key: "VERBATIMFLOW_OPENAI_AUTO_SECONDARY_MODEL",
            environment: environment,
            fileValues: fileValues
        )?.trimmingCharacters(in: .whitespacesAndNewlines)
        let secondaryModel = secondaryModelRaw?.isEmpty == false
            ? secondaryModelRaw!
            : defaultConfig.secondaryModel

        let zhOnly = parseBoolean(
            resolvedSetting(
                key: "VERBATIMFLOW_OPENAI_AUTO_ROUTE_ZH_ONLY",
                environment: environment,
                fileValues: fileValues
            ),
            defaultValue: defaultConfig.zhOnly
        )

        let minRiskScore = parseInteger(
            resolvedSetting(
                key: "VERBATIMFLOW_OPENAI_AUTO_ROUTE_MIN_RISK_SCORE",
                environment: environment,
                fileValues: fileValues
            ),
            defaultValue: defaultConfig.minRiskScore,
            min: 1,
            max: 8
        )

        let minPrimaryChars = parseInteger(
            resolvedSetting(
                key: "VERBATIMFLOW_OPENAI_AUTO_ROUTE_MIN_PRIMARY_CHARS",
                environment: environment,
                fileValues: fileValues
            ),
            defaultValue: defaultConfig.minPrimaryChars,
            min: 1,
            max: 128
        )

        return OpenAIAutoRouteConfig(
            enabled: enabled,
            secondaryModel: secondaryModel,
            zhOnly: zhOnly,
            minRiskScore: minRiskScore,
            minPrimaryChars: minPrimaryChars
        )
    }

    static func analyzePrimaryTranscript(
        _ primaryTranscript: String,
        localeIdentifier: String,
        vocabularyHints: [String],
        config: OpenAIAutoRouteConfig
    ) -> OpenAIAutoRouteAnalysis {
        let text = primaryTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return OpenAIAutoRouteAnalysis(shouldRetry: false, riskScore: 0, reasons: ["empty"])
        }

        guard text.count >= config.minPrimaryChars else {
            return OpenAIAutoRouteAnalysis(shouldRetry: false, riskScore: 0, reasons: ["too-short"])
        }

        let containsHan = containsRegexMatch(text, regex: hanRegex)
        let containsLatin = containsRegexMatch(text, regex: latinRegex)

        if config.zhOnly {
            guard localeIdentifier.lowercased().hasPrefix("zh") || containsHan else {
                return OpenAIAutoRouteAnalysis(shouldRetry: false, riskScore: 0, reasons: ["non-zh"])
            }
        }

        let mixedEnhancement = MixedLanguageEnhancer.apply(
            text: text,
            localeIdentifier: localeIdentifier,
            vocabularyHints: vocabularyHints
        )
        let correctionCount = mixedEnhancement.appliedRules.count

        var riskScore = 0
        var reasons: [String] = []

        if containsHan && containsLatin {
            riskScore += 1
            reasons.append("han+latin")
        }

        if correctionCount > 0 {
            riskScore += min(3, correctionCount + 1)
            reasons.append("mixed-corrections=\(correctionCount)")
        }

        if containsHan && !containsLatin && correctionCount > 0 {
            riskScore += 1
            reasons.append("han-only-with-corrections")
        }

        let shouldRetry = riskScore >= config.minRiskScore
        if !shouldRetry, reasons.isEmpty {
            reasons.append("low-risk")
        }

        return OpenAIAutoRouteAnalysis(
            shouldRetry: shouldRetry,
            riskScore: riskScore,
            reasons: reasons
        )
    }

    static func selectPreferredTranscript(
        primaryText: String,
        primaryModel: String,
        secondaryText: String,
        secondaryModel: String,
        localeIdentifier: String,
        vocabularyHints: [String]
    ) -> OpenAIAutoRouteSelection {
        let normalizedPrimary = primaryText.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedSecondary = secondaryText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalizedSecondary.isEmpty else {
            let primaryScore = qualityScore(
                text: normalizedPrimary,
                localeIdentifier: localeIdentifier,
                vocabularyHints: vocabularyHints
            )
            return OpenAIAutoRouteSelection(
                transcript: normalizedPrimary,
                selectedModel: primaryModel,
                primaryScore: primaryScore,
                secondaryScore: Int.min,
                reason: "secondary-empty"
            )
        }

        let primaryScore = qualityScore(
            text: normalizedPrimary,
            localeIdentifier: localeIdentifier,
            vocabularyHints: vocabularyHints
        )
        let secondaryScore = qualityScore(
            text: normalizedSecondary,
            localeIdentifier: localeIdentifier,
            vocabularyHints: vocabularyHints
        )

        if secondaryScore > primaryScore {
            return OpenAIAutoRouteSelection(
                transcript: normalizedSecondary,
                selectedModel: secondaryModel,
                primaryScore: primaryScore,
                secondaryScore: secondaryScore,
                reason: "secondary-better"
            )
        }

        return OpenAIAutoRouteSelection(
            transcript: normalizedPrimary,
            selectedModel: primaryModel,
            primaryScore: primaryScore,
            secondaryScore: secondaryScore,
            reason: "primary-kept"
        )
    }

    private static func qualityScore(
        text: String,
        localeIdentifier: String,
        vocabularyHints: [String]
    ) -> Int {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return Int.min / 4
        }

        let containsHan = containsRegexMatch(normalized, regex: hanRegex)
        let containsLatin = containsRegexMatch(normalized, regex: latinRegex)

        let mixedEnhancement = MixedLanguageEnhancer.apply(
            text: normalized,
            localeIdentifier: localeIdentifier,
            vocabularyHints: vocabularyHints
        )
        let correctionPenalty = mixedEnhancement.appliedRules.count * 2

        let hintMatches = matchedHintCount(in: normalized, hints: vocabularyHints)

        var score = normalized.count / 24
        score += hintMatches * 3
        if containsHan && containsLatin {
            score += 2
        }
        if localeIdentifier.lowercased().hasPrefix("zh") && containsHan {
            score += 1
        }
        score -= correctionPenalty
        return score
    }

    private static func matchedHintCount(in text: String, hints: [String]) -> Int {
        guard !text.isEmpty, !hints.isEmpty else {
            return 0
        }

        let loweredText = text.lowercased()
        var matched = 0
        var seen: Set<String> = []

        for rawHint in hints {
            let hint = rawHint
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            guard hint.count >= 3 else {
                continue
            }
            guard hint.rangeOfCharacter(from: CharacterSet.letters) != nil else {
                continue
            }
            guard !seen.contains(hint) else {
                continue
            }

            if loweredText.contains(hint) {
                matched += 1
                seen.insert(hint)
            }
        }

        return matched
    }

    private static func containsRegexMatch(_ text: String, regex: NSRegularExpression?) -> Bool {
        guard let regex else { return false }
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        return regex.firstMatch(in: text, options: [], range: range) != nil
    }

    private static func resolvedSetting(
        key: String,
        environment: [String: String],
        fileValues: [String: String]
    ) -> String? {
        if let envValue = environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !envValue.isEmpty {
            return envValue
        }
        if let fileValue = fileValues[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !fileValue.isEmpty {
            return fileValue
        }
        return nil
    }

    private static func parseBoolean(_ rawValue: String?, defaultValue: Bool) -> Bool {
        guard let rawValue else {
            return defaultValue
        }

        switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true", "yes", "on":
            return true
        case "0", "false", "no", "off":
            return false
        default:
            return defaultValue
        }
    }

    private static func parseInteger(_ rawValue: String?, defaultValue: Int, min: Int, max: Int) -> Int {
        guard let rawValue, let parsed = Int(rawValue.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return defaultValue
        }
        return Swift.max(min, Swift.min(max, parsed))
    }
}
