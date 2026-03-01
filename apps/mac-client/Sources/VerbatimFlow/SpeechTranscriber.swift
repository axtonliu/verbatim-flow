import AVFoundation
import Foundation
import Speech

@MainActor
final class SpeechTranscriber {
    private let permissionRequestTimeout: TimeInterval = 5

    private let localeIdentifier: String
    private let requireOnDeviceRecognition: Bool
    private let recognitionEngine: RecognitionEngine
    private let whisperModel: WhisperModel
    private let openAIModel: OpenAITranscriptionModel
    private let qwenModel: QwenModel
    private let whisperComputeType: String

    private let audioEngine = AVAudioEngine()
    private var recognitionTask: SFSpeechRecognitionTask?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var speechRecognizer: SFSpeechRecognizer?

    private var latestTranscript: String = ""
    private var stopContinuation: CheckedContinuation<String, Never>?

    private var audioRecorder: AVAudioRecorder?
    private var recordedAudioURL: URL?
    private var failedRecordingEntry: FailedRecordingStore.Entry?

    init(
        localeIdentifier: String,
        requireOnDeviceRecognition: Bool,
        recognitionEngine: RecognitionEngine,
        whisperModel: WhisperModel,
        openAIModel: OpenAITranscriptionModel,
        qwenModel: QwenModel,
        whisperComputeType: String
    ) {
        self.localeIdentifier = localeIdentifier
        self.requireOnDeviceRecognition = requireOnDeviceRecognition
        self.recognitionEngine = recognitionEngine
        self.whisperModel = whisperModel
        self.openAIModel = openAIModel
        self.qwenModel = qwenModel
        self.whisperComputeType = whisperComputeType
        self.failedRecordingEntry = FailedRecordingStore.load()
    }

    var hasFailedRecordingForRetry: Bool {
        failedRecordingEntry != nil
    }

    func ensurePermissions() async -> Bool {
        RuntimeLogger.log(
            "[permissions] ensure start engine=\(recognitionEngine.rawValue) speech=\(Self.speechStatusDescription(SFSpeechRecognizer.authorizationStatus())) mic=\(Self.microphoneStatusDescription())"
        )
        let micAuthorized = await resolveMicrophoneAuthorization()
        let speechAuthorized = recognitionEngine == .apple ? await resolveSpeechAuthorization() : true
        RuntimeLogger.log(
            "[permissions] ensure done engine=\(recognitionEngine.rawValue) speechAuthorized=\(speechAuthorized) micAuthorized=\(micAuthorized)"
        )
        return speechAuthorized && micAuthorized
    }

    func startRecording() throws {
        switch recognitionEngine {
        case .apple:
            try startAppleSpeechRecording()
        case .whisper, .openai, .qwen:
            try startFileRecording()
        }
    }

    func stopRecording() async throws -> String {
        switch recognitionEngine {
        case .apple:
            return await stopAppleSpeechRecording()
        case .whisper:
            return try await stopWhisperRecording()
        case .openai:
            return try await stopOpenAIRecording()
        case .qwen:
            return try await stopQwenRecording()
        }
    }

    func retryLastFailedRecording() async throws -> String {
        guard let entry = failedRecordingEntry else {
            throw AppError.retryAudioUnavailable
        }

        guard let engine = entry.recognitionEngine else {
            FailedRecordingStore.clear()
            failedRecordingEntry = nil
            throw AppError.retryAudioUnavailable
        }

        let transcript: String
        switch engine {
        case .apple:
            throw AppError.retryAudioUnsupportedEngine(engine.rawValue)
        case .whisper:
            let model = entry.whisperModel ?? .small
            let computeType = entry.whisperComputeType
            let languageCode = Self.whisperLanguageCode(from: entry.localeIdentifier)
            transcript = try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        let text = try Self.transcribeWhisperAudioFile(
                            audioURL: entry.audioFileURL,
                            model: model.rawValue,
                            computeType: computeType,
                            languageCode: languageCode
                        )
                        continuation.resume(returning: text)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        case .openai:
            let model = entry.openAIModel?.rawValue
            let languageCode = Self.whisperLanguageCode(from: entry.localeIdentifier)
            transcript = try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        let text = try Self.transcribeOpenAIAudioFile(
                            audioURL: entry.audioFileURL,
                            languageCode: languageCode,
                            modelOverride: model
                        )
                        continuation.resume(returning: text)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        case .qwen:
            let qwenModelId = entry.qwenModelRawValue ?? QwenModel.small.rawValue
            transcript = try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        let text = try Self.transcribeQwenAudioFile(
                            audioURL: entry.audioFileURL,
                            model: qwenModelId,
                            languageCode: nil
                        )
                        continuation.resume(returning: text)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }

        FailedRecordingStore.clear()
        failedRecordingEntry = nil
        RuntimeLogger.log("[retry-audio] retry succeeded and failed recording was cleared")
        return transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func startAppleSpeechRecording() throws {
        latestTranscript = ""
        recognitionTask?.cancel()
        recognitionTask = nil

        let locale = Locale(identifier: localeIdentifier)
        guard let recognizer = SFSpeechRecognizer(locale: locale) else {
            throw AppError.speechRecognizerUnavailable(localeIdentifier)
        }
        speechRecognizer = recognizer

        guard recognizer.isAvailable else {
            throw AppError.speechServiceUnavailable
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = requireOnDeviceRecognition
        if #available(macOS 13.0, *) {
            request.addsPunctuation = true
        }
        request.taskHint = .dictation
        request.contextualStrings = contextualHints(for: localeIdentifier)
        recognitionRequest = request

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let result {
                self.latestTranscript = result.bestTranscription.formattedString
                if result.isFinal {
                    self.finishStopIfNeeded()
                }
            }
            if error != nil {
                self.finishStopIfNeeded()
            }
        }

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()
    }

    private func stopAppleSpeechRecording() async -> String {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()

        return await withCheckedContinuation { continuation in
            stopContinuation = continuation
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                self?.finishStopIfNeeded()
            }
        }
    }

    private func finishStopIfNeeded() {
        guard let continuation = stopContinuation else {
            return
        }
        stopContinuation = nil

        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil

        continuation.resume(returning: latestTranscript.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func startFileRecording() throws {
        let recordingURL = Self.makeRecordedAudioURL()
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        let recorder = try AVAudioRecorder(url: recordingURL, settings: settings)
        recorder.isMeteringEnabled = false
        guard recorder.prepareToRecord(), recorder.record() else {
            throw AppError.audioRecorderStartFailed
        }

        audioRecorder = recorder
        recordedAudioURL = recordingURL
    }

    private func stopWhisperRecording() async throws -> String {
        guard let recorder = audioRecorder, let recordingURL = recordedAudioURL else {
            return ""
        }

        let durationSec = recorder.currentTime
        recorder.stop()

        audioRecorder = nil
        recordedAudioURL = nil

        if durationSec < 0.18 {
            try? FileManager.default.removeItem(at: recordingURL)
            return ""
        }

        let model = whisperModel.rawValue
        let computeType = whisperComputeType
        let languageCode = Self.whisperLanguageCode(from: localeIdentifier)

        do {
            let transcript = try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        let text = try Self.transcribeWhisperAudioFile(
                            audioURL: recordingURL,
                            model: model,
                            computeType: computeType,
                            languageCode: languageCode
                        )
                        continuation.resume(returning: text)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
            try? FileManager.default.removeItem(at: recordingURL)
            return transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            persistFailedRecording(audioURL: recordingURL, durationSec: durationSec)
            throw error
        }
    }

    private func stopOpenAIRecording() async throws -> String {
        guard let recorder = audioRecorder, let recordingURL = recordedAudioURL else {
            return ""
        }

        let durationSec = recorder.currentTime
        recorder.stop()

        audioRecorder = nil
        recordedAudioURL = nil

        if durationSec < 0.18 {
            try? FileManager.default.removeItem(at: recordingURL)
            return ""
        }

        let languageCode = Self.whisperLanguageCode(from: localeIdentifier)
        let selectedModel = openAIModel.rawValue
        do {
            let transcript = try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        let text = try Self.transcribeOpenAIAudioFile(
                            audioURL: recordingURL,
                            languageCode: languageCode,
                            modelOverride: selectedModel
                        )
                        continuation.resume(returning: text)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
            try? FileManager.default.removeItem(at: recordingURL)
            return transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            persistFailedRecording(audioURL: recordingURL, durationSec: durationSec)
            throw error
        }
    }

    private func stopQwenRecording() async throws -> String {
        guard let recorder = audioRecorder, let recordingURL = recordedAudioURL else {
            return ""
        }

        let durationSec = recorder.currentTime
        recorder.stop()

        audioRecorder = nil
        recordedAudioURL = nil

        if durationSec < 0.18 {
            try? FileManager.default.removeItem(at: recordingURL)
            return ""
        }

        let modelId = qwenModel.rawValue

        do {
            let transcript = try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        let text = try Self.transcribeQwenAudioFile(
                            audioURL: recordingURL,
                            model: modelId,
                            languageCode: nil
                        )
                        continuation.resume(returning: text)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
            try? FileManager.default.removeItem(at: recordingURL)
            return transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            persistFailedRecording(audioURL: recordingURL, durationSec: durationSec)
            throw error
        }
    }

    private func persistFailedRecording(audioURL: URL, durationSec: TimeInterval) {
        let entry = FailedRecordingStore.save(
            sourceAudioURL: audioURL,
            recognitionEngine: recognitionEngine,
            localeIdentifier: localeIdentifier,
            whisperModel: whisperModel,
            whisperComputeType: whisperComputeType,
            openAIModel: openAIModel,
            qwenModel: qwenModel,
            durationSeconds: durationSec
        )
        if let entry {
            failedRecordingEntry = entry
            RuntimeLogger.log(
                "[retry-audio] persisted failed recording path=\(entry.audioFileURL.path) engine=\(entry.recognitionEngineRawValue) durationSec=\(String(format: "%.2f", entry.durationSeconds))"
            )
        } else {
            try? FileManager.default.removeItem(at: audioURL)
            RuntimeLogger.log("[retry-audio] failed to persist failed recording; original audio removed")
        }
    }

    private nonisolated static func makeRecordedAudioURL() -> URL {
        let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return tempDirectory
            .appendingPathComponent("verbatim-flow-\(UUID().uuidString)", isDirectory: false)
            .appendingPathExtension("m4a")
    }

    private nonisolated static func transcribeWhisperAudioFile(
        audioURL: URL,
        model: String,
        computeType: String,
        languageCode: String?
    ) throws -> String {
        guard let scriptURL = resolveWhisperScriptURL() else {
            throw AppError.whisperScriptNotFound
        }

        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        if let pythonURL = resolvePythonExecutable(scriptURL: scriptURL) {
            process.executableURL = pythonURL
            process.arguments = [
                scriptURL.path,
                "--audio",
                audioURL.path,
                "--model",
                model,
                "--compute-type",
                computeType
            ]
        } else {
            throw AppError.pythonRuntimeNotFound
        }

        if let languageCode, !languageCode.isEmpty {
            process.arguments?.append(contentsOf: ["--language", languageCode])
        }

        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        let outputText = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let errorText = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if process.terminationStatus != 0 {
            let details = errorText.isEmpty ? outputText : errorText
            throw AppError.whisperTranscriptionFailed(details)
        }

        return outputText
    }

    private nonisolated static func transcribeOpenAIAudioFile(
        audioURL: URL,
        languageCode: String?,
        modelOverride: String?
    ) throws -> String {
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

        let resolvedModel = (modelOverride?.isEmpty == false ? modelOverride! : resolvedSetting(
            key: "VERBATIMFLOW_OPENAI_MODEL",
            environment: env,
            fileValues: fileValues
        )) ?? "gpt-4o-mini-transcribe"
        let endpoint = try resolvedOpenAIEndpoint(
            environment: env,
            fileValues: fileValues
        )
        guard let endpointURL = URL(string: endpoint) else {
            throw AppError.openAITranscriptionFailed("Invalid endpoint: \(endpoint)")
        }

        let boundary = "Boundary-\(UUID().uuidString)"
        let audioData = try Data(contentsOf: audioURL)

        var body = Data()
        appendMultipartField(name: "model", value: resolvedModel, boundary: boundary, to: &body)
        appendMultipartField(name: "response_format", value: "json", boundary: boundary, to: &body)
        if let languageCode, !languageCode.isEmpty {
            appendMultipartField(name: "language", value: languageCode, boundary: boundary, to: &body)
        }
        appendMultipartFile(
            name: "file",
            filename: audioURL.lastPathComponent,
            mimeType: "audio/m4a",
            fileData: audioData,
            boundary: boundary,
            to: &body
        )
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.httpBody = body
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (outputData, statusCode) = try performRequest(request, timeout: 180)
        if !(200...299).contains(statusCode) {
            let message = parseErrorMessage(from: outputData)
            throw AppError.openAITranscriptionFailed(
                message.isEmpty ? "HTTP \(statusCode)" : message
            )
        }

        guard
            let payload = try? JSONSerialization.jsonObject(with: outputData, options: []) as? [String: Any]
        else {
            let raw = String(data: outputData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if raw.isEmpty {
                throw AppError.openAITranscriptionFailed("Empty response")
            }
            throw AppError.openAITranscriptionFailed("Unexpected response: \(raw)")
        }

        if let text = payload["text"] as? String {
            return text
        }

        if let errorPayload = payload["error"] as? [String: Any],
           let message = errorPayload["message"] as? String,
           !message.isEmpty {
            throw AppError.openAITranscriptionFailed(message)
        }

        throw AppError.openAITranscriptionFailed("Response has no text field")
    }

    private nonisolated static func resolvedSetting(
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

    private nonisolated static func resolvedOpenAIEndpoint(
        environment: [String: String],
        fileValues: [String: String]
    ) throws -> String {
        let rawBaseURL = resolvedSetting(
            key: "VERBATIMFLOW_OPENAI_BASE_URL",
            environment: environment,
            fileValues: fileValues
        ) ?? "https://api.openai.com/v1"
        guard let baseURL = URL(string: rawBaseURL), let scheme = baseURL.scheme?.lowercased(), !scheme.isEmpty else {
            throw AppError.openAITranscriptionFailed("Invalid VERBATIMFLOW_OPENAI_BASE_URL: \(rawBaseURL)")
        }

        let allowInsecure = parseBooleanSetting(resolvedSetting(
            key: "VERBATIMFLOW_ALLOW_INSECURE_OPENAI_BASE_URL",
            environment: environment,
            fileValues: fileValues
        ))

        if scheme != "https" {
            guard allowInsecure else {
                throw AppError.openAITranscriptionFailed(
                    "VERBATIMFLOW_OPENAI_BASE_URL must use https:// (set VERBATIMFLOW_ALLOW_INSECURE_OPENAI_BASE_URL=1 only for local dev)."
                )
            }
            RuntimeLogger.log("[openai] insecure base url enabled via VERBATIMFLOW_ALLOW_INSECURE_OPENAI_BASE_URL")
        }

        return baseURL
            .appendingPathComponent("audio")
            .appendingPathComponent("transcriptions")
            .absoluteString
    }

    private nonisolated static func parseBooleanSetting(_ rawValue: String?) -> Bool {
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

    private nonisolated static func performRequest(_ request: URLRequest, timeout: TimeInterval) throws -> (Data, Int) {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout
        let session = URLSession(configuration: config)

        let semaphore = DispatchSemaphore(value: 0)
        var responseData: Data?
        var responseCode: Int?
        var responseError: Error?

        let task = session.dataTask(with: request) { data, response, error in
            responseData = data
            responseCode = (response as? HTTPURLResponse)?.statusCode
            responseError = error
            semaphore.signal()
        }
        task.resume()

        let waitResult = semaphore.wait(timeout: .now() + timeout + 1)
        session.invalidateAndCancel()

        if waitResult == .timedOut {
            task.cancel()
            throw AppError.openAITranscriptionFailed("Request timed out after \(Int(timeout))s")
        }

        if let responseError {
            throw AppError.openAITranscriptionFailed(responseError.localizedDescription)
        }

        guard let responseCode else {
            throw AppError.openAITranscriptionFailed("No HTTP response")
        }

        return (responseData ?? Data(), responseCode)
    }

    private nonisolated static func appendMultipartField(
        name: String,
        value: String,
        boundary: String,
        to body: inout Data
    ) {
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(value)\r\n".data(using: .utf8)!)
    }

    private nonisolated static func appendMultipartFile(
        name: String,
        filename: String,
        mimeType: String,
        fileData: Data,
        boundary: String,
        to body: inout Data
    ) {
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n".data(using: .utf8)!)
    }

    private nonisolated static func parseErrorMessage(from payload: Data) -> String {
        if let parsed = try? JSONSerialization.jsonObject(with: payload, options: []) as? [String: Any],
           let errorPayload = parsed["error"] as? [String: Any],
           let message = errorPayload["message"] as? String {
            return message.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return String(data: payload, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private nonisolated static func transcribeQwenAudioFile(
        audioURL: URL,
        model: String,
        languageCode: String?
    ) throws -> String {
        guard let scriptURL = resolveQwenScriptURL() else {
            throw AppError.qwenScriptNotFound
        }

        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        if let pythonURL = resolvePythonExecutable(scriptURL: scriptURL) {
            process.executableURL = pythonURL
            process.arguments = [
                scriptURL.path,
                "--audio",
                audioURL.path,
                "--model",
                model
            ]
        } else {
            throw AppError.pythonRuntimeNotFound
        }

        if let languageCode, !languageCode.isEmpty {
            process.arguments?.append(contentsOf: ["--language", languageCode])
        }

        // Use cached model without network authentication, and ensure
        // Homebrew tools (ffmpeg) are reachable for audio decoding.
        var env = ProcessInfo.processInfo.environment
        env["HF_HUB_OFFLINE"] = "1"
        let currentPath = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        let homebrewPaths = ["/opt/homebrew/bin", "/usr/local/bin"]
        let missingPaths = homebrewPaths.filter { !currentPath.contains($0) }
        if !missingPaths.isEmpty {
            env["PATH"] = (missingPaths + [currentPath]).joined(separator: ":")
        }
        process.environment = env

        // --- DEBUG DIAGNOSTICS (temporary) ---
        let diag = """
        [qwen-diag] scriptURL=\(scriptURL.path)
        [qwen-diag] scriptURL.standardized=\(scriptURL.standardizedFileURL.path)
        [qwen-diag] pythonURL=\(process.executableURL?.path ?? "nil")
        [qwen-diag] arguments=\(process.arguments ?? [])
        [qwen-diag] env.PATH=\(env["PATH"] ?? "nil")
        [qwen-diag] env.HOME=\(env["HOME"] ?? "nil")
        [qwen-diag] env.HF_HUB_OFFLINE=\(env["HF_HUB_OFFLINE"] ?? "nil")
        [qwen-diag] Bundle.main.executableURL=\(Bundle.main.executableURL?.path ?? "nil")
        [qwen-diag] Bundle.main.resourceURL=\(Bundle.main.resourceURL?.path ?? "nil")
        [qwen-diag] cwd=\(FileManager.default.currentDirectoryPath)
        """
        try? diag.write(toFile: "/tmp/verbatim-qwen-diag.log", atomically: true, encoding: .utf8)
        // --- END DEBUG ---

        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        let outputText = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let errorText = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if process.terminationStatus != 0 {
            let details = errorText.isEmpty ? outputText : errorText
            throw AppError.qwenTranscriptionFailed(details)
        }

        return outputText
    }

    private nonisolated static func resolveQwenScriptURL() -> URL? {
        resolveScript(named: "transcribe_qwen.py")
    }

    private nonisolated static func resolveWhisperScriptURL() -> URL? {
        resolveScript(named: "transcribe_once.py")
    }

    private nonisolated static func resolveScript(named filename: String) -> URL? {
        let fileManager = FileManager.default
        let currentDirectory = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
        let bundleDirectory = Bundle.main.bundleURL.deletingLastPathComponent()

        var candidates = [URL]()

        // Prefer source-tree paths so that the adjacent .venv is found by
        // resolvePythonExecutable.  Bundle resource copy is the last resort.

        // executable-relative: Contents/MacOS/../../../../python/scripts → source tree
        if let execURL = Bundle.main.executableURL {
            let execDir = execURL.deletingLastPathComponent() // Contents/MacOS
            candidates.append(
                execDir.appendingPathComponent("../../../../python/scripts/\(filename)")
            )
        }

        candidates.append(contentsOf: [
            currentDirectory.appendingPathComponent("python/scripts/\(filename)"),
            currentDirectory.appendingPathComponent("apps/mac-client/python/scripts/\(filename)"),
            bundleDirectory.appendingPathComponent("../python/scripts/\(filename)"),
            bundleDirectory.appendingPathComponent("python/scripts/\(filename)")
        ])

        // Bundle resource copy (no .venv alongside, used as fallback)
        if let resourceURL = Bundle.main.resourceURL {
            candidates.append(
                resourceURL.appendingPathComponent("python/scripts/\(filename)")
            )
        }

        let resolved = candidates.map { $0.standardizedFileURL }

        for candidate in resolved where fileManager.fileExists(atPath: candidate.path) {
            return candidate
        }

        return nil
    }

    private nonisolated static func resolvePythonExecutable(scriptURL: URL) -> URL? {
        let fileManager = FileManager.default

        var candidates = [URL]()

        // 1. venv adjacent to the script's python root (works in source tree)
        let pythonRoot = scriptURL.deletingLastPathComponent().deletingLastPathComponent()
        candidates.append(pythonRoot.appendingPathComponent(".venv/bin/python"))

        // 2. exec-relative: walk from Contents/MacOS back to source tree
        if let execURL = Bundle.main.executableURL {
            let macosDir = execURL.deletingLastPathComponent()
            candidates.append(
                macosDir.appendingPathComponent("../../../../python/.venv/bin/python")
            )
        }

        // 3. Well-known source tree path (covers /Applications install)
        let home = fileManager.homeDirectoryForCurrentUser
        candidates.append(
            home.appendingPathComponent("dev/verbatim-flow/apps/mac-client/python/.venv/bin/python")
        )

        for candidate in candidates {
            let resolved = candidate.standardizedFileURL
            if fileManager.fileExists(atPath: resolved.path) {
                return resolved
            }
        }

        let systemPython = URL(fileURLWithPath: "/usr/bin/python3")
        if fileManager.fileExists(atPath: systemPython.path) {
            return systemPython
        }

        return nil
    }

    private nonisolated static func whisperLanguageCode(from localeIdentifier: String) -> String? {
        let lowercased = localeIdentifier.lowercased()
        if lowercased.hasPrefix("zh") {
            return "zh"
        }
        if lowercased.hasPrefix("en") {
            return "en"
        }

        let languageCode = Locale(identifier: localeIdentifier).language.languageCode?.identifier
        return languageCode?.isEmpty == false ? languageCode : nil
    }

    private func resolveSpeechAuthorization() async -> Bool {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            return true
        case .denied, .restricted:
            return false
        case .notDetermined:
            return await requestSpeechAuthorization()
        @unknown default:
            return false
        }
    }

    private func resolveMicrophoneAuthorization() async -> Bool {
        if #available(macOS 14.0, *) {
            switch AVAudioApplication.shared.recordPermission {
            case .granted:
                return true
            case .denied:
                return false
            case .undetermined:
                let granted = await requestMicrophoneAuthorization()
                if granted {
                    return true
                }
                await attemptMicrophoneWarmup()
                return AVAudioApplication.shared.recordPermission == .granted
            @unknown default:
                return false
            }
        }

        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .denied, .restricted:
            return false
        case .notDetermined:
            let granted = await requestMicrophoneAuthorization()
            if granted {
                return true
            }
            await attemptMicrophoneWarmup()
            return AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        @unknown default:
            return false
        }
    }

    private func requestSpeechAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            let timeout = permissionRequestTimeout
            DispatchQueue.global(qos: .userInitiated).async {
                let semaphore = DispatchSemaphore(value: 0)
                var status: SFSpeechRecognizerAuthorizationStatus = .notDetermined
                var callbackInvoked = false

                SFSpeechRecognizer.requestAuthorization { newStatus in
                    status = newStatus
                    callbackInvoked = true
                    RuntimeLogger.log("[permissions] speech callback status=\(Self.speechStatusDescription(newStatus))")
                    semaphore.signal()
                }

                let waitResult = semaphore.wait(timeout: .now() + timeout)
                if waitResult == .timedOut {
                    RuntimeLogger.log("[permissions] speech callback timed out after \(Int(timeout))s")
                }

                let finalStatus: SFSpeechRecognizerAuthorizationStatus
                if status == .notDetermined {
                    finalStatus = SFSpeechRecognizer.authorizationStatus()
                } else {
                    finalStatus = status
                }

                RuntimeLogger.log(
                    "[permissions] speech final status=\(Self.speechStatusDescription(finalStatus)) callbackInvoked=\(callbackInvoked)"
                )
                continuation.resume(returning: finalStatus == .authorized)
            }
        }
    }

    private func requestMicrophoneAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            let timeout = permissionRequestTimeout
            DispatchQueue.global(qos: .userInitiated).async {
                let semaphore = DispatchSemaphore(value: 0)
                var callbackGranted = false
                var callbackInvoked = false

                if #available(macOS 14.0, *) {
                    AVAudioApplication.requestRecordPermission { granted in
                        callbackGranted = granted
                        callbackInvoked = true
                        RuntimeLogger.log("[permissions] microphone callback granted=\(granted)")
                        semaphore.signal()
                    }
                } else {
                    AVCaptureDevice.requestAccess(for: .audio) { granted in
                        callbackGranted = granted
                        callbackInvoked = true
                        RuntimeLogger.log("[permissions] microphone callback granted=\(granted)")
                        semaphore.signal()
                    }
                }

                let waitResult = semaphore.wait(timeout: .now() + timeout)
                if waitResult == .timedOut {
                    RuntimeLogger.log("[permissions] microphone callback timed out after \(Int(timeout))s")
                }

                let finalGranted: Bool
                if #available(macOS 14.0, *) {
                    finalGranted = callbackGranted || (callbackInvoked == false && AVAudioApplication.shared.recordPermission == .granted)
                } else {
                    finalGranted = callbackGranted || (callbackInvoked == false && AVCaptureDevice.authorizationStatus(for: .audio) == .authorized)
                }

                RuntimeLogger.log(
                    "[permissions] microphone final granted=\(finalGranted) callbackInvoked=\(callbackInvoked) status=\(Self.microphoneStatusDescription())"
                )
                continuation.resume(returning: finalGranted)
            }
        }
    }

    private func attemptMicrophoneWarmup() async {
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 256, format: format) { _, _ in }

        engine.prepare()
        _ = try? engine.start()
        try? await Task.sleep(nanoseconds: 250_000_000)
        engine.stop()
        inputNode.removeTap(onBus: 0)
    }

    private nonisolated static func speechStatusDescription(_ status: SFSpeechRecognizerAuthorizationStatus) -> String {
        switch status {
        case .authorized:
            return "authorized"
        case .denied:
            return "denied"
        case .restricted:
            return "restricted"
        case .notDetermined:
            return "not_determined"
        @unknown default:
            return "unknown"
        }
    }

    private nonisolated static func microphoneStatusDescription() -> String {
        if #available(macOS 14.0, *) {
            switch AVAudioApplication.shared.recordPermission {
            case .granted:
                return "authorized"
            case .denied:
                return "denied"
            case .undetermined:
                return "not_determined"
            @unknown default:
                return "unknown"
            }
        }

        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return "authorized"
        case .denied:
            return "denied"
        case .restricted:
            return "restricted"
        case .notDetermined:
            return "not_determined"
        @unknown default:
            return "unknown"
        }
    }

    private func contextualHints(for localeIdentifier: String) -> [String] {
        let customRules = TerminologyDictionary.loadRules()
        return DictationVocabulary.contextualHints(localeIdentifier: localeIdentifier, customHints: customRules.hints)
    }
}
