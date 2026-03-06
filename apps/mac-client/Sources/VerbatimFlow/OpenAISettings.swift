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
# Auto route for mixed-language/terminology recovery:
# 1=enabled, 0=disabled
VERBATIMFLOW_OPENAI_AUTO_ROUTE=1
# Secondary model used only when risk is high.
VERBATIMFLOW_OPENAI_AUTO_SECONDARY_MODEL=whisper-1
# Restrict auto reroute to Chinese/mixed Chinese scenarios.
VERBATIMFLOW_OPENAI_AUTO_ROUTE_ZH_ONLY=1
# Language hint strategy for OpenAI transcription:
# auto  -> do not force zh hint in Chinese locale (better mixed zh/en terms)
# force -> always pass locale-based language hint
# off   -> never pass language hint
VERBATIMFLOW_OPENAI_LANGUAGE_HINT_MODE=auto
# Optional tuning:
# VERBATIMFLOW_OPENAI_AUTO_ROUTE_MIN_RISK_SCORE=2
# VERBATIMFLOW_OPENAI_AUTO_ROUTE_MIN_PRIMARY_CHARS=8
# Clarify rewrite mode:
# provider=openai (default) or provider=openrouter
VERBATIMFLOW_CLARIFY_PROVIDER=openai
# Optional dedicated key/base-url for clarify only.
# If VERBATIMFLOW_CLARIFY_API_KEY is empty:
# - provider=openai    -> fallback OPENAI_API_KEY
# - provider=openrouter -> fallback OPENROUTER_API_KEY
VERBATIMFLOW_CLARIFY_API_KEY=
# Optional override, must be OpenAI-compatible /chat/completions base URL.
# VERBATIMFLOW_CLARIFY_BASE_URL=https://api.openai.com/v1
# Clarify rewrite model.
VERBATIMFLOW_OPENAI_CLARIFY_MODEL=gpt-4o-mini
# OpenRouter key (only needed when provider=openrouter and no clarify key override).
OPENROUTER_API_KEY=
# Optional OpenRouter attribution headers.
VERBATIMFLOW_OPENROUTER_SITE_URL=
VERBATIMFLOW_OPENROUTER_APP_NAME=VerbatimFlow
# Optional OpenRouter routing preference for clarify: price | latency | throughput
# VERBATIMFLOW_OPENROUTER_PROVIDER_SORT=latency
# For security, only https:// base URLs are allowed by default.
# For localhost debugging only, set VERBATIMFLOW_ALLOW_INSECURE_OPENAI_BASE_URL=1.
VERBATIMFLOW_OPENAI_BASE_URL=https://api.openai.com/v1
# VERBATIMFLOW_ALLOW_INSECURE_OPENAI_BASE_URL=0
# Optional safety timeouts (seconds, range 15..600)
# VERBATIMFLOW_OPENAI_TRANSCRIPTION_TIMEOUT_SECONDS=45
# VERBATIMFLOW_OPENAI_SECONDARY_TRANSCRIPTION_TIMEOUT_SECONDS=20
# VERBATIMFLOW_WHISPER_PROCESS_TIMEOUT_SECONDS=120
# VERBATIMFLOW_PROCESSING_WATCHDOG_SECONDS=120
"""

    static func ensureConfigFileExists() {
        do {
            try FileManager.default.createDirectory(
                at: applicationSupportDirectory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            if !FileManager.default.fileExists(atPath: fileURL.path) {
                let created = FileManager.default.createFile(
                    atPath: fileURL.path,
                    contents: Data(defaultTemplate.utf8),
                    attributes: [.posixPermissions: 0o600]
                )
                if !created {
                    RuntimeLogger.log("[openai-settings] failed to create config file at \(fileURL.path)")
                }
            }
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
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
