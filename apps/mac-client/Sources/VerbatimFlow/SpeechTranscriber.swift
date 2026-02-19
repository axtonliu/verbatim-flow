import AVFoundation
import Foundation
import Speech

@MainActor
final class SpeechTranscriber {
    private let permissionRequestTimeout: TimeInterval = 5

    private let localeIdentifier: String
    private let requireOnDeviceRecognition: Bool

    private let audioEngine = AVAudioEngine()
    private var recognitionTask: SFSpeechRecognitionTask?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var speechRecognizer: SFSpeechRecognizer?

    private var latestTranscript: String = ""
    private var stopContinuation: CheckedContinuation<String, Never>?

    init(localeIdentifier: String, requireOnDeviceRecognition: Bool) {
        self.localeIdentifier = localeIdentifier
        self.requireOnDeviceRecognition = requireOnDeviceRecognition
    }

    func ensurePermissions() async -> Bool {
        RuntimeLogger.log("[permissions] ensure start speech=\(Self.speechStatusDescription(SFSpeechRecognizer.authorizationStatus())) mic=\(Self.microphoneStatusDescription())")
        let micAuthorized = await resolveMicrophoneAuthorization()
        let speechAuthorized = await resolveSpeechAuthorization()
        RuntimeLogger.log("[permissions] ensure done speechAuthorized=\(speechAuthorized) micAuthorized=\(micAuthorized)")
        return speechAuthorized && micAuthorized
    }

    func startRecording() throws {
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

    func stopRecording() async -> String {
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

                RuntimeLogger.log("[permissions] speech final status=\(Self.speechStatusDescription(finalStatus)) callbackInvoked=\(callbackInvoked)")
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

                RuntimeLogger.log("[permissions] microphone final granted=\(finalGranted) callbackInvoked=\(callbackInvoked) status=\(Self.microphoneStatusDescription())")
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
