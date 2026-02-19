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
    private(set) var localeIdentifier: String

    private let requireOnDeviceRecognition: Bool
    private var transcriber: SpeechTranscriber
    private let injector = TextInjector()
    private var hotkey: Hotkey
    private let dryRun: Bool

    private var mode: OutputMode
    private var hotkeyMonitor: HotkeyMonitor?
    private var isRecording = false
    private(set) var runtimeState: RuntimeState = .stopped {
        didSet {
            onStateChanged?(runtimeState)
        }
    }

    var onStateChanged: ((RuntimeState) -> Void)?
    var onLog: ((String) -> Void)?
    var onTranscriptCommitted: ((String) -> Void)?
    var onPermissionSnapshot: ((PermissionSnapshot) -> Void)?

    init(config: CLIConfig) {
        self.localeIdentifier = config.localeIdentifier
        self.requireOnDeviceRecognition = config.requireOnDeviceRecognition
        self.hotkey = config.hotkey
        self.mode = config.mode
        self.dryRun = config.dryRun
        self.transcriber = SpeechTranscriber(
            localeIdentifier: config.localeIdentifier,
            requireOnDeviceRecognition: config.requireOnDeviceRecognition
        )
    }

    var currentMode: OutputMode {
        mode
    }

    var currentHotkeyDisplay: String {
        hotkey.display
    }

    var currentHotkey: Hotkey {
        hotkey
    }

    var currentLocaleIdentifier: String {
        localeIdentifier
    }

    var isRunning: Bool {
        hotkeyMonitor != nil
    }

    func start() {
        guard hotkeyMonitor == nil else {
            return
        }

        emit("verbatim-flow")
        emit("mode=\(mode.rawValue) locale=\(localeIdentifier) hotkey=\(hotkey.display)")
        emit("release hotkey to transcribe and insert")

        let trusted = injector.promptAccessibilityIfNeeded()
        if !trusted {
            emit("[warn] Accessibility permission is required for global hotkey and text injection.")
            emit("[hint] Grant permission in System Settings > Privacy & Security > Accessibility.")
        }

        hotkeyMonitor = HotkeyMonitor(
            hotkey: hotkey,
            onPressed: { [weak self] in
                Task { @MainActor in
                    await self?.handleHotkeyPressed()
                }
            },
            onReleased: { [weak self] in
                Task { @MainActor in
                    await self?.handleHotkeyReleased()
                }
            }
        )

        hotkeyMonitor?.start()
        runtimeState = .ready
        emit("[ready] Waiting for hotkey: \(hotkey.display)")
    }

    func stop() {
        stopInternal(emitLog: true)
    }

    func requestSpeechAndMicrophonePermissions() {
        Task { @MainActor in
            emit("[permissions] requesting access...")
            let accessibilityTrusted = injector.promptAccessibilityIfNeeded()
            if !accessibilityTrusted {
                emit("[permissions] Accessibility not granted yet")
            }

            let before = currentPermissionSnapshot()
            emit("[permissions] before: \(before.summaryLine)")

            _ = await transcriber.ensurePermissions()
            let snapshot = currentPermissionSnapshot()
            emit("[permissions] \(snapshot.summaryLine)")
            onPermissionSnapshot?(snapshot)
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
            accessibilityTrusted: accessibilityTrusted
        )
    }

    func setMode(_ mode: OutputMode) {
        self.mode = mode
        emit("[config] mode set to \(mode.rawValue)")
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

    func setLocaleIdentifier(_ localeIdentifier: String) {
        guard self.localeIdentifier != localeIdentifier else {
            return
        }

        guard !isRecording else {
            emit("[warn] stop recording before changing language")
            return
        }

        self.localeIdentifier = localeIdentifier
        self.transcriber = SpeechTranscriber(
            localeIdentifier: localeIdentifier,
            requireOnDeviceRecognition: requireOnDeviceRecognition
        )
        emit("[config] language set to \(localeIdentifier)")
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
                try self.injector.undoLastInsert()
                self.emit("[rollback] copied transcript and sent undo")
            } catch {
                self.emit("[error] rollback failed: \(error)")
            }
        }
    }

    private func stopInternal(emitLog: Bool) {
        hotkeyMonitor = nil

        if isRecording {
            isRecording = false
            Task { @MainActor in
                _ = await transcriber.stopRecording()
            }
        }

        runtimeState = .stopped
        if emitLog {
            emit("[stopped] Hotkey listener paused")
        }
    }

    private func handleHotkeyPressed() async {
        guard runtimeState != .stopped else {
            return
        }
        guard !isRecording else {
            return
        }

        emit("[hotkey] pressed")

        let permissionsGranted = await transcriber.ensurePermissions()
        guard permissionsGranted else {
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
            emit("[error] Failed to start recording: \(error)")
            runtimeState = .ready
        }
    }

    private func handleHotkeyReleased() async {
        guard runtimeState != .stopped else {
            return
        }
        guard isRecording else {
            return
        }

        emit("[hotkey] released")

        isRecording = false
        runtimeState = .processing

        let raw = await transcriber.stopRecording()
        let guarded = TextGuard(mode: mode).apply(raw: raw)
        guard !guarded.text.isEmpty else {
            emit("[skip] Empty transcript")
            runtimeState = .ready
            return
        }

        onTranscriptCommitted?(guarded.text)

        if guarded.fellBackToRaw {
            emit("[guard] Format-only attempt changed semantics. Fallback to raw.")
        }

        if dryRun {
            emit("[dry-run] \(guarded.text)")
            runtimeState = .ready
            return
        }

        do {
            try injector.insert(text: guarded.text)
            emit("[inserted] \(guarded.text)")
        } catch {
            emit("[error] Failed to inject text: \(error)")
        }

        runtimeState = .ready
    }

    private func emit(_ message: String) {
        RuntimeLogger.log(message)
        onLog?(message)
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
}
