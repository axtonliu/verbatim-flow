import Foundation

enum OpenAISettings {
    private static let applicationSupportDirectory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true).appendingPathComponent("Library/Application Support", isDirectory: true)
        return base.appendingPathComponent("VerbatimFlow", isDirectory: true)
    }()

    static let fileURL: URL = applicationSupportDirectory.appendingPathComponent("openai.env")

    private static let defaultTemplate: String = """
# VerbatimFlow OpenAI Cloud settings
# Fill OPENAI_API_KEY to enable cloud transcription.
# You can keep default model for speed, or switch to a larger one.
OPENAI_API_KEY=
VERBATIMFLOW_OPENAI_MODEL=gpt-4o-mini-transcribe
# Clarify rewrite model (used by clarify mode when engine is OpenAI Cloud).
VERBATIMFLOW_OPENAI_CLARIFY_MODEL=gpt-4o-mini
# For security, only https:// base URLs are allowed by default.
# For localhost debugging only, set VERBATIMFLOW_ALLOW_INSECURE_OPENAI_BASE_URL=1.
VERBATIMFLOW_OPENAI_BASE_URL=https://api.openai.com/v1
# VERBATIMFLOW_ALLOW_INSECURE_OPENAI_BASE_URL=0
"""

    static func ensureConfigFileExists() {
        do {
            try FileManager.default.createDirectory(at: applicationSupportDirectory, withIntermediateDirectories: true)
            guard !FileManager.default.fileExists(atPath: fileURL.path) else {
                return
            }
            try defaultTemplate.write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            RuntimeLogger.log("[openai-settings] failed to ensure config file: \(error)")
        }
    }

    static func loadValues() -> [String: String] {
        ensureConfigFileExists()
        guard let raw = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return [:]
        }

        var values: [String: String] = [:]
        for line in raw.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else {
                continue
            }

            let parts = trimmed.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else {
                continue
            }

            let key = String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines)
            var value = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
                value.removeFirst()
                value.removeLast()
            }
            if key.isEmpty {
                continue
            }
            values[key] = value
        }

        return values
    }
}
