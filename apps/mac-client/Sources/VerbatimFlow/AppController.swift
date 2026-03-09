import AppKit
import AVFoundation
import ApplicationServices
import Foundation
import Speech

enum RuntimeState: Equatable {
    case stopped
    case ready
    case recording
    case processing
}

@MainActor
final class AppController {
    private struct PendingInsertTarget {
        let processIdentifier: pid_t
        let bundleIdentifier: String?
        let localizedName: String?
    }

    private(set) var localeIdentifier: String
    private var languageIsAutoDetect: Bool

    private let requireOnDeviceRecognition: Bool
    private var recognitionEngine: RecognitionEngine
    private var whisperModel: WhisperModel
    private var openAIModel: OpenAITranscriptionModel
    private var qwenModel: QwenModel
    private let whisperComputeType: String
    private var transcriber: SpeechTranscriber
    private let injector = TextInjector()
    private var hotkey: Hotkey
    private var clarifyHotkey: Hotkey
    private let dryRun: Bool

    private var mode: OutputMode
    private var primaryHotkeyMonitor: HotkeyMonitor?
    private var clarifyHotkeyMonitor: HotkeyMonitor?
    private var pendingSegmentModeOverride: OutputMode?
    private var isRecording = false
    private var activeProcessingToken: UUID?
    private var processingWatchdogWorkItem: DispatchWorkItem?
    private var pendingInsertTarget: PendingInsertTarget?
    private var lastSuccessfulInsertTarget: PendingInsertTarget?
    private let enableVoiceCommandPrefixes = false
    private(set) var runtimeState: RuntimeState = .stopped {
        didSet {
            onStateChanged?(runtimeState)
        }
    }

    private static let defaultClarifyHotkey: Hotkey = (try? HotkeyParser.parse(combo: "cmd+shift+space"))
        ?? Hotkey(
            keyCode: 49,
            modifiers: [.command, .shift],
            display: "cmd+shift+space"
        )
    static var defaultClarifyHotkeyValue: Hotkey {
        defaultClarifyHotkey
    }
    private static let processingWatchdogTimeoutSeconds: TimeInterval = {
        let env = ProcessInfo.processInfo.environment
        let fileValues = OpenAISettings.loadValues()
        let raw = (env["VERBATIMFLOW_PROCESSING_WATCHDOG_SECONDS"]
            ?? fileValues["VERBATIMFLOW_PROCESSING_WATCHDOG_SECONDS"])?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let raw, let seconds = Double(raw), seconds >= 15, seconds <= 600 else {
            return 120
        }
        return seconds
    }()

    var onStateChanged: ((RuntimeState) -> Void)?
    var onLog: ((String) -> Void)?
    var onTranscriptCommitted: ((String) -> Void)?
    var onPermissionSnapshot: ((PermissionSnapshot) -> Void)?
    var onRetriableAudioAvailabilityChanged: ((Bool) -> Void)?

    init(config: CLIConfig, languageIsAutoDetect: Bool = false) {
        self.localeIdentifier = config.localeIdentifier
        self.languageIsAutoDetect = languageIsAutoDetect
        self.requireOnDeviceRecognition = config.requireOnDeviceRecognition
        self.recognitionEngine = config.recognitionEngine
        self.whisperModel = config.whisperModel
        self.openAIModel = config.openAIModel
        self.qwenModel = config.qwenModel
        self.whisperComputeType = config.whisperComputeType
        self.hotkey = config.hotkey
        self.clarifyHotkey = Self.defaultClarifyHotkey
        self.mode = Self.normalizeDefaultMode(config.mode)
        self.dryRun = config.dryRun
        self.transcriber = SpeechTranscriber(
            localeIdentifier: config.localeIdentifier,
            requireOnDeviceRecognition: config.requireOnDeviceRecognition,
            recognitionEngine: config.recognitionEngine,
            whisperModel: config.whisperModel,
            openAIModel: config.openAIModel,
            qwenModel: config.qwenModel,
            whisperComputeType: config.whisperComputeType,
            languageIsAutoDetect: languageIsAutoDetect
        )
    }

    var currentMode: OutputMode {
        mode
    }

    var currentHotkeyDisplay: String {
        hotkey.display
    }

    var currentClarifyHotkeyDisplay: String {
        clarifyHotkey.display
    }

    var currentClarifyHotkey: Hotkey {
        clarifyHotkey
    }

    var currentHotkey: Hotkey {
        hotkey
    }

    var currentLocaleIdentifier: String {
        localeIdentifier
    }

    var currentRecognitionEngine: RecognitionEngine {
        recognitionEngine
    }

    var currentWhisperModel: WhisperModel {
        whisperModel
    }

    var currentOpenAIModel: OpenAITranscriptionModel {
        openAIModel
    }

    var currentQwenModel: QwenModel {
        qwenModel
    }

    var isRunning: Bool {
        primaryHotkeyMonitor != nil
    }

    var hasRetriableAudio: Bool {
        transcriber.hasFailedRecordingForRetry
    }

    var canRetryLastFailedAudio: Bool {
        runtimeState == .ready && !isRecording && hasRetriableAudio
    }

    func start() {
        guard primaryHotkeyMonitor == nil else {
            return
        }

        emit("verbatim-flow")
        emit(
            "mode=\(mode.rawValue) engine=\(recognitionEngine.rawValue) whisper-model=\(whisperModel.rawValue) openai-model=\(openAIModel.rawValue) qwen-model=\(qwenModel.displayName) locale=\(localeIdentifier) hotkey=\(hotkey.display)"
        )
        emit("release hotkey to transcribe and insert")
        emit("[hotkey] primary=\(hotkey.display) default-mode=\(mode.rawValue)")
        emit("[hotkey] secondary=\(clarifyHotkey.display) segment-mode=clarify")

        let trusted = injector.promptAccessibilityIfNeeded()
        if !trusted {
            emit("[warn] Accessibility permission is required for global hotkey and text injection.")
            emit("[hint] Grant permission in System Settings > Privacy & Security > Accessibility.")
        }

        primaryHotkeyMonitor = makeHotkeyMonitor(
            hotkey: hotkey,
            segmentMode: mode,
            monitorLabel: "primary"
        )
        primaryHotkeyMonitor?.start()

        if hotkey.keyCode == clarifyHotkey.keyCode, hotkey.modifiers == clarifyHotkey.modifiers {
            emit("[warn] clarify hotkey conflicts with primary; secondary clarify hotkey disabled")
            clarifyHotkeyMonitor = nil
        } else {
            clarifyHotkeyMonitor = makeHotkeyMonitor(
                hotkey: clarifyHotkey,
                segmentMode: .clarify,
                monitorLabel: "clarify"
            )
            clarifyHotkeyMonitor?.start()
        }
        runtimeState = .ready
        emit("[ready] Waiting for hotkey: \(hotkey.display)")
        notifyRetriableAudioAvailabilityChanged()
    }

    func stop() {
        stopInternal(emitLog: true)
    }

    func requestSpeechAndMicrophonePermissions() {
        RuntimeLogger.log("[permissions] controller request invoked")
        emit("[permissions] requesting access...")
        let accessibilityTrusted = injector.isAccessibilityTrusted()
        let requiresSpeechPermission = recognitionEngine == .apple
        if !accessibilityTrusted {
            emit("[permissions] Accessibility not granted yet")
        }

        let before = currentPermissionSnapshot()
        emit("[permissions] before: \(before.summaryLine)")

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else {
                RuntimeLogger.log("[permissions] background request dropped: self released")
                return
            }

            RuntimeLogger.log("[permissions] background request started")
            let micGranted = Self.requestMicrophoneAuthorization(timeout: 6)
            let speechGranted = requiresSpeechPermission ? Self.requestSpeechAuthorization(timeout: 6) : true
            RuntimeLogger.log("[permissions] background request finished micGranted=\(micGranted) speechGranted=\(speechGranted)")

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let snapshot = self.currentPermissionSnapshot()
                self.emit("[permissions] \(snapshot.summaryLine)")
                self.onPermissionSnapshot?(snapshot)
            }
        }
    }

    func currentPermissionSnapshot() -> PermissionSnapshot {
        let speechStatus = SFSpeechRecognizer.authorizationStatus()
        let accessibilityTrusted = AXIsProcessTrusted()

        let microphoneState: PermissionState
        if #available(macOS 14.0, *) {
            microphoneState = mapMicrophoneStatus(AVAudioApplication.shared.recordPermission)
        } else {
            microphoneState = mapMicrophoneStatus(AVCaptureDevice.authorizationStatus(for: .audio))
        }

        return PermissionSnapshot(
            speech: mapSpeechStatus(speechStatus),
            microphone: microphoneState,
            accessibilityTrusted: accessibilityTrusted,
            speechRequired: recognitionEngine == .apple
        )
    }

    func setMode(_ mode: OutputMode) {
        let normalized = Self.normalizeDefaultMode(mode)
        self.mode = normalized
        emit("[config] mode set to \(normalized.rawValue)")
        if mode == .raw {
            emit("[config] raw merged into format-only baseline")
        }
    }

    func setHotkey(_ hotkey: Hotkey) {
        let sameHotkey = self.hotkey.keyCode == hotkey.keyCode &&
            self.hotkey.modifiers == hotkey.modifiers
        guard !sameHotkey else {
            return
        }

        let wasRunning = isRunning
        if wasRunning {
            stopInternal(emitLog: false)
        }

        self.hotkey = hotkey
        emit("[config] hotkey set to \(hotkey.display)")

        if wasRunning {
            start()
        }
    }

    func setClarifyHotkey(_ hotkey: Hotkey) {
        let sameHotkey = self.clarifyHotkey.keyCode == hotkey.keyCode &&
            self.clarifyHotkey.modifiers == hotkey.modifiers
        guard !sameHotkey else {
            return
        }

        let wasRunning = isRunning
        if wasRunning {
            stopInternal(emitLog: false)
        }

        self.clarifyHotkey = hotkey
        emit("[config] clarify hotkey set to \(hotkey.display)")

        if wasRunning {
            start()
        }
    }

    func setLocaleIdentifier(_ localeIdentifier: String, isAutoDetect: Bool) {
        let changed = self.localeIdentifier != localeIdentifier || self.languageIsAutoDetect != isAutoDetect
        guard changed else { return }

        guard !isRecording else {
            emit("[warn] stop recording before changing language")
            return
        }

        self.localeIdentifier = localeIdentifier
        self.languageIsAutoDetect = isAutoDetect
        rebuildTranscriber()
        emit("[config] language set to \(localeIdentifier)\(isAutoDetect ? " (auto-detect)" : "")")
    }

    func setRecognitionEngine(_ engine: RecognitionEngine) {
        guard recognitionEngine != engine else {
            return
        }

        guard !isRecording else {
            emit("[warn] stop recording before changing engine")
            return
        }

        recognitionEngine = engine
        rebuildTranscriber()
        emit("[config] engine set to \(engine.rawValue)")
    }

    func setWhisperModel(_ model: WhisperModel) {
        guard whisperModel != model else {
            return
        }

        guard !isRecording else {
            emit("[warn] stop recording before changing model")
            return
        }

        whisperModel = model
        rebuildTranscriber()
        emit("[config] whisper model set to \(model.rawValue)")
    }

    func setOpenAIModel(_ model: OpenAITranscriptionModel) {
        guard openAIModel != model else {
            return
        }

        guard !isRecording else {
            emit("[warn] stop recording before changing OpenAI model")
            return
        }

        openAIModel = model
        rebuildTranscriber()
        emit("[config] openai model set to \(model.rawValue)")
    }

    func setQwenModel(_ model: QwenModel) {
        guard qwenModel != model else {
            return
        }

        guard !isRecording else {
            emit("[warn] stop recording before changing Qwen model")
            return
        }

        qwenModel = model
        rebuildTranscriber()
        emit("[config] qwen model set to \(model.displayName)")
    }

    func copyTranscriptToClipboard(_ text: String) {
        guard !text.isEmpty else {
            emit("[warn] nothing to copy")
            return
        }
        injector.copyToClipboard(text: text)
        emit("[clipboard] transcript copied")
    }

    func copyAndUndoLastInsert(_ text: String) {
        guard !text.isEmpty else {
            emit("[warn] nothing to rollback")
            return
        }

        injector.copyToClipboard(text: text)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            guard let self else { return }
            do {
                let preferredTarget = self.lastSuccessfulInsertTarget.map { target in
                    TextInjector.InsertionTarget(
                        processIdentifier: target.processIdentifier,
                        bundleIdentifier: target.bundleIdentifier,
                        localizedName: target.localizedName
                    )
                }
                try self.injector.undoLastInsert(preferredTarget: preferredTarget)
                self.emit("[rollback] copied transcript and sent undo")
            } catch {
                self.emit("[error] rollback failed: \(error)")
            }
        }
    }

    func retryLastFailedAudio() {
        guard runtimeState == .ready else {
            emit("[warn] wait until current operation completes before retry")
            return
        }

        guard !isRecording else {
            emit("[warn] stop recording before retrying failed audio")
            return
        }

        guard hasRetriableAudio else {
            emit("[warn] no failed recording available for retry")
            notifyRetriableAudioAvailabilityChanged()
            return
        }

        let processingToken = beginProcessing(context: "retry-audio")
        let retryTarget = capturePendingInsertTarget() ?? lastSuccessfulInsertTarget
        emit("[retry-audio] retrying last failed recording...")

        Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.endProcessingIfCurrent(processingToken)
            }

            do {
                let raw = try await self.transcriber.retryLastFailedRecording()
                guard self.isProcessingTokenCurrent(processingToken) else {
                    self.emit("[retry-audio] stale result dropped after watchdog reset")
                    return
                }
                await self.commitTranscript(raw, preferredTarget: retryTarget, processingToken: processingToken)
            } catch {
                self.emit("[error] Retry last audio failed: \(error)")
            }
        }
    }

    private func stopInternal(emitLog: Bool) {
        primaryHotkeyMonitor = nil
        clarifyHotkeyMonitor = nil
        pendingSegmentModeOverride = nil
        activeProcessingToken = nil
        processingWatchdogWorkItem?.cancel()
        processingWatchdogWorkItem = nil

        if isRecording {
            isRecording = false
            Task { @MainActor in
                _ = try? await transcriber.stopRecording()
            }
        }

        runtimeState = .stopped
        if emitLog {
            emit("[stopped] Hotkey listener paused")
        }
    }

    private func shouldAcceptHotkeyPress(segmentMode: OutputMode, monitorLabel: String) -> Bool {
        guard runtimeState != .stopped else {
            RuntimeLogger.log("[hotkey-handler] ignored pressed (bridge gate) monitor=\(monitorLabel) because runtimeState=stopped")
            return false
        }
        guard runtimeState == .ready else {
            RuntimeLogger.log("[hotkey-handler] ignored pressed (bridge gate) monitor=\(monitorLabel) mode=\(segmentMode.rawValue) because runtimeState=\(runtimeState)")
            return false
        }
        guard !isRecording else {
            RuntimeLogger.log("[hotkey-handler] ignored pressed (bridge gate) monitor=\(monitorLabel) because isRecording=true")
            return false
        }
        return true
    }

    private func handleHotkeyPressed() async {
        RuntimeLogger.log("[hotkey-handler] handleHotkeyPressed invoked")
        guard runtimeState != .stopped else {
            RuntimeLogger.log("[hotkey-handler] ignored pressed because runtimeState=stopped")
            return
        }
        guard runtimeState == .ready else {
            RuntimeLogger.log("[hotkey-handler] ignored pressed because runtimeState=\(runtimeState)")
            return
        }
        guard !isRecording else {
            RuntimeLogger.log("[hotkey-handler] ignored pressed because isRecording=true")
            return
        }

        emit("[hotkey] pressed")
        pendingInsertTarget = capturePendingInsertTarget()

        let permissionsGranted = await transcriber.ensurePermissions()
        guard permissionsGranted else {
            pendingInsertTarget = nil
            pendingSegmentModeOverride = nil
            emit("[error] Speech/Microphone permission denied.")
            onPermissionSnapshot?(currentPermissionSnapshot())
            return
        }

        do {
            try transcriber.startRecording()
            isRecording = true
            runtimeState = .recording
            emit("[recording] Speak now...")
        } catch {
            pendingInsertTarget = nil
            pendingSegmentModeOverride = nil
            emit("[error] Failed to start recording: \(error)")
            runtimeState = .ready
        }
    }

    private func handleHotkeyReleased() async {
        RuntimeLogger.log("[hotkey-handler] handleHotkeyReleased invoked")
        guard runtimeState != .stopped else {
            RuntimeLogger.log("[hotkey-handler] ignored released because runtimeState=stopped")
            return
        }
        guard isRecording else {
            RuntimeLogger.log("[hotkey-handler] ignored released because isRecording=false")
            return
        }

        emit("[hotkey] released")

        isRecording = false
        let processingToken = beginProcessing(context: "hotkey-release")
        defer {
            endProcessingIfCurrent(processingToken)
        }

        let raw: String
        do {
            raw = try await transcriber.stopRecording()
        } catch {
            if transcriber.hasFailedRecordingForRetry {
                emit("[retry-audio] transcription failed; audio saved for retry")
            }
            notifyRetriableAudioAvailabilityChanged()
            pendingInsertTarget = nil
            pendingSegmentModeOverride = nil
            emit("[error] Failed to transcribe audio: \(error)")
            return
        }
        guard isProcessingTokenCurrent(processingToken) else {
            emit("[stale] transcription result dropped because processing watchdog already reset state")
            pendingInsertTarget = nil
            pendingSegmentModeOverride = nil
            return
        }

        await commitTranscript(raw, preferredTarget: pendingInsertTarget, processingToken: processingToken)
        pendingInsertTarget = nil
        pendingSegmentModeOverride = nil
    }

    private func emit(_ message: String) {
        RuntimeLogger.log(message)
        onLog?(message)
    }

    private func notifyRetriableAudioAvailabilityChanged() {
        onRetriableAudioAvailabilityChanged?(hasRetriableAudio)
    }

    private func commitTranscript(
        _ raw: String,
        preferredTarget: PendingInsertTarget?,
        processingToken: UUID? = nil
    ) async {
        guard isProcessingTokenCurrent(processingToken) else {
            emit("[stale] transcript dropped before normalization")
            return
        }

        let defaultSegmentMode = pendingSegmentModeOverride ?? mode
        if let override = pendingSegmentModeOverride, override != mode {
            emit("[segment-mode] current segment uses \(override.rawValue) via secondary hotkey")
        }

        let commandParsed: OneShotVoiceCommandResult
        if enableVoiceCommandPrefixes {
            commandParsed = OneShotVoiceCommandParser.parse(raw: raw, defaultMode: defaultSegmentMode)
        } else {
            commandParsed = OneShotVoiceCommandResult(
                effectiveMode: defaultSegmentMode,
                content: raw.trimmingCharacters(in: .whitespacesAndNewlines),
                matchedCommand: nil
            )
        }
        if let matchedCommand = commandParsed.matchedCommand {
            if commandParsed.effectiveMode == mode {
                emit("[voice-command] detected '\(matchedCommand)' for current segment")
            } else {
                emit(
                    "[voice-command] override current segment mode: \(mode.rawValue) -> \(commandParsed.effectiveMode.rawValue) (\(matchedCommand))"
                )
            }
        }

        let guarded = TextGuard(mode: commandParsed.effectiveMode).apply(raw: commandParsed.content)
        guard !guarded.text.isEmpty else {
            if commandParsed.matchedCommand != nil {
                emit("[voice-command] command detected but no content after command")
            }
            emit("[skip] Empty transcript")
            return
        }

        let terminologyRules = TerminologyDictionary.loadRules()
        let terminologyApplied = TerminologyDictionary.applyReplacements(
            to: guarded.text,
            replacements: terminologyRules.replacements
        )
        let mixedEnhancement = MixedLanguageEnhancer.apply(
            text: terminologyApplied.text,
            localeIdentifier: localeIdentifier,
            vocabularyHints: DictationVocabulary.fuzzyCorrectionTerms(customHints: terminologyRules.hints)
        )
        var finalText = mixedEnhancement.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !finalText.isEmpty else {
            emit("[skip] Empty transcript after terminology normalization")
            return
        }

        if !terminologyApplied.appliedRules.isEmpty {
            emit("[terminology] applied: \(terminologyApplied.appliedRules.joined(separator: ", "))")
        }
        if !mixedEnhancement.appliedRules.isEmpty {
            emit("[mixed-language] applied: \(mixedEnhancement.appliedRules.joined(separator: ", "))")
        }

        if commandParsed.effectiveMode == .clarify {
            do {
                let textToRewrite = finalText
                let localeToRewrite = localeIdentifier
                let terminologyHints = DictationVocabulary.fuzzyCorrectionTerms(customHints: terminologyRules.hints)
                let rewritten = try await Task.detached(priority: .userInitiated) {
                    try ClarifyRewriter.rewrite(
                        text: textToRewrite,
                        localeIdentifier: localeToRewrite,
                        terminologyHints: terminologyHints
                    )
                }.value
                finalText = rewritten.text
                emit("[clarify] llm rewrite applied provider=\(rewritten.provider) model=\(rewritten.model)")
            } catch {
                emit("[clarify] llm rewrite unavailable, fallback to rules: \(error)")
            }
        }

        guard isProcessingTokenCurrent(processingToken) else {
            emit("[stale] transcript dropped after post-processing")
            return
        }

        onTranscriptCommitted?(finalText)

        if guarded.fellBackToRaw {
            emit("[guard] Format-only attempt changed semantics. Fallback to raw.")
        }

        if dryRun {
            emit("[dry-run] chars=\(finalText.count) preview=\"\(Self.logPreview(finalText))\"")
            return
        }

        guard isProcessingTokenCurrent(processingToken) else {
            emit("[stale] transcript dropped before insertion")
            return
        }

        do {
            try injector.insert(text: finalText, preferredTarget: injectorTarget(from: preferredTarget))
            lastSuccessfulInsertTarget = preferredTarget ?? capturePendingInsertTarget()
            emit("[inserted] chars=\(finalText.count) preview=\"\(Self.logPreview(finalText))\"")
        } catch {
            if let appError = error as? AppError, case .accessibilityPermissionRequired = appError {
                emit("[error] Accessibility permission missing/stale. Re-enable VerbatimFlow in Privacy & Security > Accessibility.")
            }
            emit("[error] Failed to inject text: \(error)")
        }
    }

    private func injectorTarget(from pendingTarget: PendingInsertTarget?) -> TextInjector.InsertionTarget? {
        guard let pendingTarget else {
            return nil
        }
        return TextInjector.InsertionTarget(
            processIdentifier: pendingTarget.processIdentifier,
            bundleIdentifier: pendingTarget.bundleIdentifier,
            localizedName: pendingTarget.localizedName
        )
    }

    private func rebuildTranscriber() {
        transcriber = SpeechTranscriber(
            localeIdentifier: localeIdentifier,
            requireOnDeviceRecognition: requireOnDeviceRecognition,
            recognitionEngine: recognitionEngine,
            whisperModel: whisperModel,
            openAIModel: openAIModel,
            qwenModel: qwenModel,
            whisperComputeType: whisperComputeType,
            languageIsAutoDetect: languageIsAutoDetect
        )
        notifyRetriableAudioAvailabilityChanged()
    }

    private func capturePendingInsertTarget() -> PendingInsertTarget? {
        guard let frontmost = NSWorkspace.shared.frontmostApplication else {
            RuntimeLogger.log("[insert-target] no frontmost application found on hotkey press")
            return nil
        }

        if frontmost.processIdentifier == ProcessInfo.processInfo.processIdentifier {
            RuntimeLogger.log("[insert-target] frontmost app is VerbatimFlow; skip capture")
            return nil
        }

        let target = PendingInsertTarget(
            processIdentifier: frontmost.processIdentifier,
            bundleIdentifier: frontmost.bundleIdentifier,
            localizedName: frontmost.localizedName
        )
        RuntimeLogger.log(
            "[insert-target] captured pid=\(target.processIdentifier) bundle=\(target.bundleIdentifier ?? "-") name=\(target.localizedName ?? "-")"
        )
        return target
    }

    private func mapSpeechStatus(_ status: SFSpeechRecognizerAuthorizationStatus) -> PermissionState {
        switch status {
        case .notDetermined:
            return .notDetermined
        case .authorized:
            return .authorized
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        @unknown default:
            return .unsupported
        }
    }

    private func mapMicrophoneStatus(_ status: AVAuthorizationStatus) -> PermissionState {
        switch status {
        case .notDetermined:
            return .notDetermined
        case .authorized:
            return .authorized
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        @unknown default:
            return .unsupported
        }
    }

    @available(macOS 14.0, *)
    private func mapMicrophoneStatus(_ status: AVAudioApplication.recordPermission) -> PermissionState {
        switch status {
        case .undetermined:
            return .notDetermined
        case .denied:
            return .denied
        case .granted:
            return .authorized
        @unknown default:
            return .unsupported
        }
    }

    private nonisolated static func requestSpeechAuthorization(timeout: TimeInterval) -> Bool {
        let current = SFSpeechRecognizer.authorizationStatus()
        switch current {
        case .authorized:
            return true
        case .denied, .restricted:
            return false
        case .notDetermined:
            let semaphore = DispatchSemaphore(value: 0)
            var status: SFSpeechRecognizerAuthorizationStatus = .notDetermined
            SFSpeechRecognizer.requestAuthorization { newStatus in
                status = newStatus
                RuntimeLogger.log("[permissions] speech callback status=\(newStatus.rawValue)")
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
            RuntimeLogger.log("[permissions] speech final status=\(finalStatus.rawValue)")
            return finalStatus == .authorized
        @unknown default:
            return false
        }
    }

    private nonisolated static func requestMicrophoneAuthorization(timeout: TimeInterval) -> Bool {
        if #available(macOS 14.0, *) {
            switch AVAudioApplication.shared.recordPermission {
            case .granted:
                return true
            case .denied:
                return false
            case .undetermined:
                let semaphore = DispatchSemaphore(value: 0)
                var callbackGranted = false
                AVAudioApplication.requestRecordPermission { granted in
                    callbackGranted = granted
                    RuntimeLogger.log("[permissions] microphone callback granted=\(granted)")
                    semaphore.signal()
                }

                let waitResult = semaphore.wait(timeout: .now() + timeout)
                if waitResult == .timedOut {
                    RuntimeLogger.log("[permissions] microphone callback timed out after \(Int(timeout))s")
                }
                let finalGranted = callbackGranted || AVAudioApplication.shared.recordPermission == .granted
                RuntimeLogger.log("[permissions] microphone final status=\(AVAudioApplication.shared.recordPermission.rawValue)")
                return finalGranted
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
            let semaphore = DispatchSemaphore(value: 0)
            var callbackGranted = false
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                callbackGranted = granted
                RuntimeLogger.log("[permissions] microphone callback granted=\(granted)")
                semaphore.signal()
            }

            let waitResult = semaphore.wait(timeout: .now() + timeout)
            if waitResult == .timedOut {
                RuntimeLogger.log("[permissions] microphone callback timed out after \(Int(timeout))s")
            }
            let finalGranted = callbackGranted || AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
            RuntimeLogger.log("[permissions] microphone final status=\(AVCaptureDevice.authorizationStatus(for: .audio).rawValue)")
            return finalGranted
        @unknown default:
            return false
        }
    }

    private func makeHotkeyMonitor(
        hotkey: Hotkey,
        segmentMode: OutputMode,
        monitorLabel: String
    ) -> HotkeyMonitor {
        HotkeyMonitor(
            hotkey: hotkey,
            onPressed: { [weak self] in
                RuntimeLogger.log("[hotkey-bridge] onPressed callback fired monitor=\(monitorLabel)")
                guard let self else {
                    RuntimeLogger.log("[hotkey-bridge] onPressed callback dropped: self released monitor=\(monitorLabel)")
                    return false
                }

                guard Thread.isMainThread else {
                    RuntimeLogger.log("[hotkey-bridge] onPressed callback dropped: not on main thread monitor=\(monitorLabel)")
                    return false
                }

                let accepted = MainActor.assumeIsolated {
                    self.shouldAcceptHotkeyPress(segmentMode: segmentMode, monitorLabel: monitorLabel)
                }
                guard accepted else {
                    RuntimeLogger.log("[hotkey-bridge] onPressed callback rejected by state gate monitor=\(monitorLabel)")
                    return false
                }

                MainActor.assumeIsolated {
                    self.pendingSegmentModeOverride = segmentMode
                }

                Task { @MainActor in
                    RuntimeLogger.log("[hotkey-bridge] onPressed task entered monitor=\(monitorLabel)")
                    await self.handleHotkeyPressed()
                    RuntimeLogger.log("[hotkey-bridge] onPressed task finished monitor=\(monitorLabel)")
                }
                return true
            },
            onReleased: { [weak self] in
                RuntimeLogger.log("[hotkey-bridge] onReleased callback fired monitor=\(monitorLabel)")
                guard let self else {
                    RuntimeLogger.log("[hotkey-bridge] onReleased callback dropped: self released monitor=\(monitorLabel)")
                    return
                }
                Task { @MainActor in
                    RuntimeLogger.log("[hotkey-bridge] onReleased task entered monitor=\(monitorLabel)")
                    await self.handleHotkeyReleased()
                    RuntimeLogger.log("[hotkey-bridge] onReleased task finished monitor=\(monitorLabel)")
                }
            }
        )
    }

    private static func normalizeDefaultMode(_ mode: OutputMode) -> OutputMode {
        mode == .raw ? .formatOnly : mode
    }

    private static func logPreview(_ text: String, limit: Int = 24) -> String {
        let singleLine = text.replacingOccurrences(of: "\n", with: " ")
        if singleLine.count <= limit {
            return singleLine
        }
        return String(singleLine.prefix(limit)) + "…"
    }

    private func beginProcessing(context: String) -> UUID {
        let token = UUID()
        activeProcessingToken = token
        runtimeState = .processing
        scheduleProcessingWatchdog(for: token, context: context)
        return token
    }

    private func scheduleProcessingWatchdog(for token: UUID, context: String) {
        processingWatchdogWorkItem?.cancel()

        let timeout = Self.processingWatchdogTimeoutSeconds
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard self.activeProcessingToken == token, self.runtimeState == .processing else {
                return
            }

            self.emit(
                "[watchdog] processing exceeded \(Int(timeout))s (\(context)); reset to ready and drop stale result"
            )
            self.transcriber.persistPendingTranscriptionForRetryIfNeeded(reason: "processing-watchdog")
            self.activeProcessingToken = nil
            self.pendingInsertTarget = nil
            self.pendingSegmentModeOverride = nil
            self.isRecording = false
            self.runtimeState = .ready
            self.notifyRetriableAudioAvailabilityChanged()
        }
        processingWatchdogWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: workItem)
    }

    private func isProcessingTokenCurrent(_ token: UUID?) -> Bool {
        guard let token else {
            return true
        }
        return activeProcessingToken == token
    }

    private func endProcessingIfCurrent(_ token: UUID?) {
        guard let token, activeProcessingToken == token else {
            return
        }
        activeProcessingToken = nil
        processingWatchdogWorkItem?.cancel()
        processingWatchdogWorkItem = nil
        runtimeState = .ready
        notifyRetriableAudioAvailabilityChanged()
    }
}
