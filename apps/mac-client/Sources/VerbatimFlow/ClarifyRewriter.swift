import Foundation

struct ClarifyRewriteResult: Sendable {
    let text: String
    let model: String
    let provider: String
}

enum ClarifyRewriter {
    private struct ClarifyTransportConfig: Sendable {
        let provider: String
        let model: String
        let endpoint: String
        let apiKey: String
        let extraHeaders: [String]
    }

    static func rewrite(text: String, localeIdentifier: String) throws -> ClarifyRewriteResult {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ClarifyRewriteResult(text: "", model: "", provider: "")
        }

        let env = ProcessInfo.processInfo.environment
        let fileValues = OpenAISettings.loadValues()
        let transport = try resolvedClarifyTransport(environment: env, fileValues: fileValues)
        let usesTLS = transport.endpoint.lowercased().hasPrefix("https://")

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
            "model": transport.model,
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
            transport.endpoint
        ])

        let headers = [
            "Authorization: Bearer \(transport.apiKey)",
            "Content-Type: application/json"
        ] + transport.extraHeaders
        for header in headers {
            arguments.append(contentsOf: ["-H", header])
        }

        arguments.append(contentsOf: ["--data-binary", "@-"])
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

        return ClarifyRewriteResult(
            text: rewritten,
            model: transport.model,
            provider: transport.provider
        )
    }

    private static func resolvedClarifyTransport(
        environment: [String: String],
        fileValues: [String: String]
    ) throws -> ClarifyTransportConfig {
        let providerRaw = (resolvedSetting(
            key: "VERBATIMFLOW_CLARIFY_PROVIDER",
            environment: environment,
            fileValues: fileValues
        ) ?? "openai").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        let configuredModel = resolvedSetting(
            key: "VERBATIMFLOW_OPENAI_CLARIFY_MODEL",
            environment: environment,
            fileValues: fileValues
        )

        let allowInsecure = parseBooleanSetting(resolvedSetting(
            key: "VERBATIMFLOW_ALLOW_INSECURE_OPENAI_BASE_URL",
            environment: environment,
            fileValues: fileValues
        ))

        switch providerRaw {
        case "openai":
            let apiKey = resolvedSetting(
                key: "VERBATIMFLOW_CLARIFY_API_KEY",
                environment: environment,
                fileValues: fileValues
            ) ?? resolvedSetting(
                key: "OPENAI_API_KEY",
                environment: environment,
                fileValues: fileValues
            )
            guard let apiKey, !apiKey.isEmpty else {
                throw AppError.openAIAPIKeyMissing
            }

            let rawBaseURL = resolvedSetting(
                key: "VERBATIMFLOW_CLARIFY_BASE_URL",
                environment: environment,
                fileValues: fileValues
            ) ?? resolvedSetting(
                key: "VERBATIMFLOW_OPENAI_BASE_URL",
                environment: environment,
                fileValues: fileValues
            ) ?? "https://api.openai.com/v1"

            return ClarifyTransportConfig(
                provider: "openai",
                model: configuredModel ?? "gpt-4o-mini",
                endpoint: try resolvedChatCompletionsEndpoint(rawBaseURL: rawBaseURL, allowInsecure: allowInsecure),
                apiKey: apiKey,
                extraHeaders: []
            )

        case "openrouter":
            let apiKey = resolvedSetting(
                key: "VERBATIMFLOW_CLARIFY_API_KEY",
                environment: environment,
                fileValues: fileValues
            ) ?? resolvedSetting(
                key: "OPENROUTER_API_KEY",
                environment: environment,
                fileValues: fileValues
            )
            guard let apiKey, !apiKey.isEmpty else {
                throw AppError.openAIClarifyFailed(
                    "OPENROUTER_API_KEY is missing. Set OPENROUTER_API_KEY or VERBATIMFLOW_CLARIFY_API_KEY."
                )
            }

            let rawBaseURL = resolvedSetting(
                key: "VERBATIMFLOW_CLARIFY_BASE_URL",
                environment: environment,
                fileValues: fileValues
            ) ?? "https://openrouter.ai/api/v1"

            var extraHeaders: [String] = []
            if let siteURL = resolvedSetting(
                key: "VERBATIMFLOW_OPENROUTER_SITE_URL",
                environment: environment,
                fileValues: fileValues
            ), !siteURL.isEmpty {
                extraHeaders.append("HTTP-Referer: \(siteURL)")
            }
            if let appName = resolvedSetting(
                key: "VERBATIMFLOW_OPENROUTER_APP_NAME",
                environment: environment,
                fileValues: fileValues
            ), !appName.isEmpty {
                extraHeaders.append("X-Title: \(appName)")
            } else {
                extraHeaders.append("X-Title: VerbatimFlow")
            }

            return ClarifyTransportConfig(
                provider: "openrouter",
                model: configuredModel ?? "openai/gpt-4o-mini",
                endpoint: try resolvedChatCompletionsEndpoint(rawBaseURL: rawBaseURL, allowInsecure: allowInsecure),
                apiKey: apiKey,
                extraHeaders: extraHeaders
            )

        default:
            throw AppError.openAIClarifyFailed(
                "Unsupported VERBATIMFLOW_CLARIFY_PROVIDER=\(providerRaw). Use openai or openrouter."
            )
        }
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

    private static func resolvedChatCompletionsEndpoint(rawBaseURL: String, allowInsecure: Bool) throws -> String {
        guard let baseURL = URL(string: rawBaseURL), let scheme = baseURL.scheme?.lowercased(), !scheme.isEmpty else {
            throw AppError.openAIClarifyFailed("Invalid clarify base URL: \(rawBaseURL)")
        }

        if scheme != "https" {
            guard allowInsecure else {
                throw AppError.openAIClarifyFailed(
                    "Clarify base URL must use https:// (set VERBATIMFLOW_ALLOW_INSECURE_OPENAI_BASE_URL=1 only for local dev)."
                )
            }
            RuntimeLogger.log("[clarify] insecure base url enabled via VERBATIMFLOW_ALLOW_INSECURE_OPENAI_BASE_URL")
        }

        return baseURL
            .appendingPathComponent("chat")
            .appendingPathComponent("completions")
            .absoluteString
    }
}
