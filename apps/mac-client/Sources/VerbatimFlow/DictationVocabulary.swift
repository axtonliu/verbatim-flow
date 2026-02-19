import Foundation

enum DictationVocabulary {
    static let technicalTerms: [String] = [
        "Commit",
        "Branch",
        "Repository",
        "Pull Request",
        "PR",
        "Release",
        "Token",
        "Context",
        "Prompt",
        "Workflow",
        "Git",
        "Mac",
        "Whisper",
        "VerbatimFlow",
        "Raycast",
        "Wispr",
        "Tabless",
        "Typeless"
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
        if localeIdentifier.lowercased().hasPrefix("zh") {
            return technicalTerms + customHints + chineseAssistTerms
        }
        return technicalTerms + customHints
    }

    static func fuzzyCorrectionTerms(customHints: [String]) -> [String] {
        technicalTerms + customHints
    }
}
