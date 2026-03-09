import Foundation

enum DictationVocabulary {
    enum CorrectionPolicy: Equatable {
        case always
        case contextual(keywords: [String])
    }

    private struct TermProfile {
        let term: String
        let includeInASRHints: Bool
        let correctionPolicy: CorrectionPolicy
    }

    struct AliasProfile: Equatable {
        let source: String
        let target: String
        let correctionPolicy: CorrectionPolicy
    }

    private static let aiContextKeywords: [String] = [
        "ai", "llm", "模型", "大模型", "语音", "转写", "识别", "术语", "工具", "应用", "app",
        "claude", "gpt", "openai", "anthropic", "gemini", "prompt"
    ]

    private static let exactCaseTerms: [String] = [
        "Claude", "GPT", "GPT-5", "OpenAI", "Anthropic", "Gemini", "YouTube", "iTerm2",
        "GitHub", "Whisper", "VerbatimFlow", "Raycast", "Wispr", "Tabless", "Typeless", "Mac"
    ]

    private static let aliasProfiles: [AliasProfile] = [
        AliasProfile(source: "claude", target: "Claude", correctionPolicy: .always),
        AliasProfile(source: "gpt", target: "GPT", correctionPolicy: .always),
        AliasProfile(source: "openai", target: "OpenAI", correctionPolicy: .always),
        AliasProfile(source: "anthropic", target: "Anthropic", correctionPolicy: .always),
        AliasProfile(source: "gemini", target: "Gemini", correctionPolicy: .always),
        AliasProfile(source: "youtube", target: "YouTube", correctionPolicy: .always),
        AliasProfile(source: "iterm2", target: "iTerm2", correctionPolicy: .always),
        AliasProfile(source: "克劳德", target: "Claude", correctionPolicy: .contextual(keywords: aiContextKeywords)),
        AliasProfile(source: "扣劳德", target: "Claude", correctionPolicy: .contextual(keywords: aiContextKeywords)),
        AliasProfile(source: "鸡皮替", target: "GPT", correctionPolicy: .contextual(keywords: aiContextKeywords)),
        AliasProfile(source: "机皮替", target: "GPT", correctionPolicy: .contextual(keywords: aiContextKeywords)),
        AliasProfile(source: "吉米尼", target: "Gemini", correctionPolicy: .contextual(keywords: aiContextKeywords)),
        AliasProfile(source: "杰米尼", target: "Gemini", correctionPolicy: .contextual(keywords: aiContextKeywords)),
        AliasProfile(source: "机迷你", target: "Gemini", correctionPolicy: .contextual(keywords: aiContextKeywords)),
        AliasProfile(source: "金版", target: "Gemini", correctionPolicy: .contextual(keywords: aiContextKeywords)),
        AliasProfile(source: "GIT", target: "GPT", correctionPolicy: .contextual(keywords: aiContextKeywords))
    ]

    private static let termProfiles: [TermProfile] = [
        TermProfile(term: "Commit", includeInASRHints: true, correctionPolicy: .always),
        TermProfile(term: "Branch", includeInASRHints: true, correctionPolicy: .always),
        TermProfile(term: "Repository", includeInASRHints: true, correctionPolicy: .always),
        TermProfile(term: "Pull Request", includeInASRHints: true, correctionPolicy: .always),
        TermProfile(term: "PR", includeInASRHints: true, correctionPolicy: .always),
        TermProfile(term: "Release", includeInASRHints: true, correctionPolicy: .always),
        TermProfile(term: "Token", includeInASRHints: true, correctionPolicy: .always),
        TermProfile(term: "Context", includeInASRHints: true, correctionPolicy: .always),
        TermProfile(term: "Prompt", includeInASRHints: true, correctionPolicy: .always),
        TermProfile(term: "Workflow", includeInASRHints: true, correctionPolicy: .always),
        TermProfile(term: "BROLL", includeInASRHints: true, correctionPolicy: .always),
        TermProfile(term: "B-roll", includeInASRHints: true, correctionPolicy: .always),
        TermProfile(term: "iTerm2", includeInASRHints: true, correctionPolicy: .always),
        TermProfile(term: "Terminal", includeInASRHints: true, correctionPolicy: .always),
        TermProfile(term: "Git", includeInASRHints: true, correctionPolicy: .always),
        TermProfile(term: "GitHub", includeInASRHints: true, correctionPolicy: .always),
        TermProfile(term: "Mac", includeInASRHints: true, correctionPolicy: .always),
        TermProfile(term: "Whisper", includeInASRHints: true, correctionPolicy: .always),
        TermProfile(term: "VerbatimFlow", includeInASRHints: true, correctionPolicy: .always),
        TermProfile(term: "Raycast", includeInASRHints: true, correctionPolicy: .always),
        TermProfile(term: "Wispr", includeInASRHints: true, correctionPolicy: .always),
        TermProfile(term: "Tabless", includeInASRHints: true, correctionPolicy: .always),
        TermProfile(term: "Typeless", includeInASRHints: true, correctionPolicy: .always),
        TermProfile(term: "Claude", includeInASRHints: true, correctionPolicy: .always),
        TermProfile(term: "GPT", includeInASRHints: true, correctionPolicy: .always),
        TermProfile(term: "GPT-5", includeInASRHints: true, correctionPolicy: .always),
        TermProfile(term: "OpenAI", includeInASRHints: true, correctionPolicy: .always),
        TermProfile(term: "Anthropic", includeInASRHints: true, correctionPolicy: .always),
        TermProfile(term: "Gemini", includeInASRHints: true, correctionPolicy: .always),
        TermProfile(term: "YouTube", includeInASRHints: true, correctionPolicy: .always),
        TermProfile(
            term: "Tana",
            includeInASRHints: false,
            correctionPolicy: .contextual(
                keywords: ["笔记", "知识", "项目", "标签", "节点", "工作区", "数据库", "app", "软件", "工具", "obsidian", "notion", "readwise", "workspace", "node", "tag"]
            )
        )
    ]

    static let chineseAssistTerms: [String] = [
        "中文",
        "英文",
        "中英文混合",
        "识别准确率",
        "剪贴板",
        "文本框",
        "插入",
        "提交",
        "分支",
        "仓库",
        "拉取请求"
    ]

    static func contextualHints(localeIdentifier: String, customHints: [String]) -> [String] {
        let baseHints = transcriptionPromptTerms(customHints: customHints)
        if localeIdentifier.lowercased().hasPrefix("zh") {
            return deduplicated(baseHints + chineseAssistTerms)
        }
        return baseHints
    }

    static func transcriptionPromptTerms(customHints: [String]) -> [String] {
        deduplicated(termProfiles.filter(\.includeInASRHints).map(\.term) + customHints)
    }

    static func fuzzyCorrectionTerms(customHints: [String]) -> [String] {
        deduplicated(termProfiles.map(\.term) + customHints)
    }

    static func correctionPolicy(for term: String) -> CorrectionPolicy {
        let key = normalizedTermKey(term)
        for profile in termProfiles {
            if normalizedTermKey(profile.term) == key {
                return profile.correctionPolicy
            }
        }
        return .always
    }

    static func exactCaseTarget(for token: String) -> String? {
        let key = normalizedTermKey(token)
        for term in exactCaseTerms {
            if normalizedTermKey(term) == key {
                return term
            }
        }
        return nil
    }

    static func aliasMatch(for token: String) -> AliasProfile? {
        let key = normalizedTokenKey(token)
        for alias in aliasProfiles {
            if normalizedTokenKey(alias.source) == key {
                return alias
            }
        }
        return nil
    }

    static func substringAliases() -> [AliasProfile] {
        aliasProfiles.filter { containsHan($0.source) }
    }

    // Canonical key for built-in English brand/term matching.
    // This intentionally strips everything except ASCII letters/digits so
    // "GPT-5", "gpt 5", and "GPT5" resolve to the same vocabulary term.
    private static func normalizedTermKey(_ term: String) -> String {
        term
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]", with: "", options: .regularExpression)
    }

    // Canonical key for alias/source matching.
    // Unlike normalizedTermKey, this preserves Han characters and only
    // removes whitespace so aliases like "金版" or "克劳德" still match.
    private static func normalizedTokenKey(_ token: String) -> String {
        token
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
    }

    private static func containsHan(_ text: String) -> Bool {
        text.range(of: "\\p{Han}", options: .regularExpression) != nil
    }

    private static func deduplicated(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var output: [String] = []
        output.reserveCapacity(values.count)

        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            output.append(trimmed)
        }

        return output
    }
}
