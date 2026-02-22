import Foundation

struct ClarifyRewriteResult: Sendable {
    let text: String
    let model: String
}

enum ClarifyRewriter {
    static func rewriteWithOpenAI(text: String, localeIdentifier: String) throws -> ClarifyRewriteResult {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ClarifyRewriteResult(text: "", model: "")
        }

        let env = ProcessInfo.processInfo.environment
        let fileValues = OpenAISettings.loadValues()

        let apiKey = resolvedSetting(
            key: "OPENAI_API_KEY",
            environment: env,
            fileValues: fileValues
        )
        guard let apiKey, !apiKey.isEmpty else {
            throw AppError.openAIAPIKeyMissing
        }

        let model = resolvedSetting(
            key: "VERBATIMFLOW_OPENAI_CLARIFY_MODEL",
            environment: env,
            fileValues: fileValues
        ) ?? "gpt-4o-mini"
        let endpoint = try resolvedChatCompletionsEndpoint(environment: env, fileValues: fileValues)
        let usesTLS = endpoint.lowercased().hasPrefix("https://")

        let systemPrompt = """
You are VerbatimFlow Clarify mode.
Rewrite spoken dictation into clear written text.
Rules:
- Keep original meaning, facts, numbers, proper nouns, and intent.
- Do not add new information.
- Remove filler words and obvious repetition.
- Keep the same language as the input (Chinese stays Chinese; mixed-language stays mixed).
- If Chinese or Chinese-dominant, use full-width Chinese punctuation (，。！？；：).
- Output plain text only. No markdown. No explanation.
"""

        let payload: [String: Any] = [
            "model": model,
            "temperature": 0.1,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": "locale=\(localeIdentifier)\n\n" + trimmed]
            ]
        ]
        let payloadData = try JSONSerialization.data(withJSONObject: payload, options: [])

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")

        var arguments: [String] = [
            "-sS",
            "--connect-timeout", "10",
            "--max-time", "60"
        ]
        if usesTLS {
            arguments.append(contentsOf: ["--proto", "=https", "--tlsv1.2"])
        }
        arguments.append(contentsOf: [
            "-X", "POST",
            endpoint,
            "-H", "Authorization: Bearer \(apiKey)",
            "-H", "Content-Type: application/json",
            "--data-binary", "@-"
        ])
        process.arguments = arguments

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        let inputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        process.standardInput = inputPipe

        try process.run()
        inputPipe.fileHandleForWriting.write(payloadData)
        inputPipe.fileHandleForWriting.closeFile()
        process.waitUntilExit()

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorText = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if process.terminationStatus != 0 {
            let details = errorText.isEmpty
                ? (String(data: outputData, encoding: .utf8) ?? "")
                : errorText
            throw AppError.openAIClarifyFailed(details)
        }

        guard
            let payload = try? JSONSerialization.jsonObject(with: outputData, options: []) as? [String: Any]
        else {
            let raw = String(data: outputData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw AppError.openAIClarifyFailed("Unexpected response: \(raw)")
        }

        if let errorPayload = payload["error"] as? [String: Any],
           let message = errorPayload["message"] as? String,
           !message.isEmpty {
            throw AppError.openAIClarifyFailed(message)
        }

        guard
            let choices = payload["choices"] as? [[String: Any]],
            let first = choices.first,
            let message = first["message"] as? [String: Any],
            let content = message["content"] as? String
        else {
            throw AppError.openAIClarifyFailed("Response has no choices.message.content field")
        }

        let rewritten = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if rewritten.isEmpty {
            throw AppError.openAIClarifyFailed("Clarify response is empty")
        }

        return ClarifyRewriteResult(text: rewritten, model: model)
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

    private static func parseBooleanSetting(_ rawValue: String?) -> Bool {
        guard let rawValue else {
            return false
        }

        switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true", "yes", "on":
            return true
        default:
            return false
        }
    }

    private static func resolvedChatCompletionsEndpoint(
        environment: [String: String],
        fileValues: [String: String]
    ) throws -> String {
        let rawBaseURL = resolvedSetting(
            key: "VERBATIMFLOW_OPENAI_BASE_URL",
            environment: environment,
            fileValues: fileValues
        ) ?? "https://api.openai.com/v1"
        guard let baseURL = URL(string: rawBaseURL), let scheme = baseURL.scheme?.lowercased(), !scheme.isEmpty else {
            throw AppError.openAIClarifyFailed("Invalid VERBATIMFLOW_OPENAI_BASE_URL: \(rawBaseURL)")
        }

        let allowInsecure = parseBooleanSetting(resolvedSetting(
            key: "VERBATIMFLOW_ALLOW_INSECURE_OPENAI_BASE_URL",
            environment: environment,
            fileValues: fileValues
        ))
        if scheme != "https" {
            guard allowInsecure else {
                throw AppError.openAIClarifyFailed(
                    "VERBATIMFLOW_OPENAI_BASE_URL must use https:// (set VERBATIMFLOW_ALLOW_INSECURE_OPENAI_BASE_URL=1 only for local dev)."
                )
            }
            RuntimeLogger.log("[openai] insecure base url enabled via VERBATIMFLOW_ALLOW_INSECURE_OPENAI_BASE_URL")
        }

        return baseURL
            .appendingPathComponent("chat")
            .appendingPathComponent("completions")
            .absoluteString
    }
}
