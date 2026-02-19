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
    private let whisperComputeType: String

    private let audioEngine = AVAudioEngine()
    private var recognitionTask: SFSpeechRecognitionTask?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var speechRecognizer: SFSpeechRecognizer?

    private var latestTranscript: String = ""
    private var stopContinuation: CheckedContinuation<String, Never>?

    private var audioRecorder: AVAudioRecorder?
    private var recordedAudioURL: URL?

    init(
        localeIdentifier: String,
        requireOnDeviceRecognition: Bool,
        recognitionEngine: RecognitionEngine,
        whisperModel: WhisperModel,
        whisperComputeType: String
    ) {
        self.localeIdentifier = localeIdentifier
        self.requireOnDeviceRecognition = requireOnDeviceRecognition
        self.recognitionEngine = recognitionEngine
        self.whisperModel = whisperModel
        self.whisperComputeType = whisperComputeType
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
        case .whisper:
            try startFileRecording()
        case .openai:
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
        }
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

        defer {
            try? FileManager.default.removeItem(at: recordingURL)
        }

        if durationSec < 0.18 {
            return ""
        }

        let model = whisperModel.rawValue
        let computeType = whisperComputeType
        let languageCode = Self.whisperLanguageCode(from: localeIdentifier)

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

        return transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func stopOpenAIRecording() async throws -> String {
        guard let recorder = audioRecorder, let recordingURL = recordedAudioURL else {
            return ""
        }

        let durationSec = recorder.currentTime
        recorder.stop()

        audioRecorder = nil
        recordedAudioURL = nil

        defer {
            try? FileManager.default.removeItem(at: recordingURL)
        }

        if durationSec < 0.18 {
            return ""
        }

        let languageCode = Self.whisperLanguageCode(from: localeIdentifier)
        let transcript = try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let text = try Self.transcribeOpenAIAudioFile(audioURL: recordingURL, languageCode: languageCode)
                    continuation.resume(returning: text)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }

        return transcript.trimmingCharacters(in: .whitespacesAndNewlines)
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

    private nonisolated static func transcribeOpenAIAudioFile(audioURL: URL, languageCode: String?) throws -> String {
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

        let resolvedModel = resolvedSetting(
            key: "VERBATIMFLOW_OPENAI_MODEL",
            environment: env,
            fileValues: fileValues
        ) ?? "gpt-4o-mini-transcribe"
        let resolvedBaseURL = resolvedSetting(
            key: "VERBATIMFLOW_OPENAI_BASE_URL",
            environment: env,
            fileValues: fileValues
        ) ?? "https://api.openai.com/v1"
        let endpoint = resolvedBaseURL.hasSuffix("/") ? "\(resolvedBaseURL)audio/transcriptions" : "\(resolvedBaseURL)/audio/transcriptions"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")

        var arguments: [String] = [
            "-sS",
            "-X", "POST",
            endpoint,
            "-H", "Authorization: Bearer \(apiKey)",
            "-F", "file=@\(audioURL.path)",
            "-F", "model=\(resolvedModel)",
            "-F", "response_format=json"
        ]

        if let languageCode, !languageCode.isEmpty {
            arguments.append(contentsOf: ["-F", "language=\(languageCode)"])
        }

        process.arguments = arguments

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorText = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if process.terminationStatus != 0 {
            let details = errorText.isEmpty
                ? (String(data: outputData, encoding: .utf8) ?? "")
                : errorText
            throw AppError.openAITranscriptionFailed(details)
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

    private nonisolated static func resolveWhisperScriptURL() -> URL? {
        let fileManager = FileManager.default
        let currentDirectory = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
        let bundleDirectory = Bundle.main.bundleURL.deletingLastPathComponent()

        let candidates = [
            currentDirectory.appendingPathComponent("python/scripts/transcribe_once.py"),
            currentDirectory.appendingPathComponent("apps/mac-client/python/scripts/transcribe_once.py"),
            bundleDirectory.appendingPathComponent("../python/scripts/transcribe_once.py"),
            bundleDirectory.appendingPathComponent("python/scripts/transcribe_once.py")
        ].map { $0.standardizedFileURL }

        for candidate in candidates where fileManager.fileExists(atPath: candidate.path) {
            return candidate
        }

        return nil
    }

    private nonisolated static func resolvePythonExecutable(scriptURL: URL) -> URL? {
        let fileManager = FileManager.default
        let pythonRoot = scriptURL.deletingLastPathComponent().deletingLastPathComponent()
        let venvPython = pythonRoot.appendingPathComponent(".venv/bin/python")
        if fileManager.fileExists(atPath: venvPython.path) {
            return venvPython
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
