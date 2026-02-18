import Foundation

enum RuntimeState: Equatable {
    case stopped
    case ready
    case recording
    case processing
}

@MainActor
final class AppController {
    let localeIdentifier: String
    let hotkeyDisplay: String

    private let transcriber: SpeechTranscriber
    private let injector = TextInjector()
    private let hotkey: Hotkey
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

    init(config: CLIConfig) {
        self.localeIdentifier = config.localeIdentifier
        self.hotkeyDisplay = config.hotkey.display
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

    var isRunning: Bool {
        hotkeyMonitor != nil
    }

    func start() {
        guard hotkeyMonitor == nil else {
            return
        }

        emit("verbatim-flow")
        emit("mode=\(mode.rawValue) locale=\(localeIdentifier) hotkey=\(hotkeyDisplay)")
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
        emit("[ready] Waiting for hotkey: \(hotkeyDisplay)")
    }

    func stop() {
        hotkeyMonitor = nil

        if isRecording {
            isRecording = false
            Task { @MainActor in
                _ = await transcriber.stopRecording()
            }
        }

        runtimeState = .stopped
        emit("[stopped] Hotkey listener paused")
    }

    func setMode(_ mode: OutputMode) {
        self.mode = mode
        emit("[config] mode set to \(mode.rawValue)")
    }

    private func handleHotkeyPressed() async {
        guard runtimeState != .stopped else {
            return
        }
        guard !isRecording else {
            return
        }

        let permissionsGranted = await transcriber.ensurePermissions()
        guard permissionsGranted else {
            emit("[error] Speech/Microphone permission denied.")
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

        isRecording = false
        runtimeState = .processing

        let raw = await transcriber.stopRecording()
        let guarded = TextGuard(mode: mode).apply(raw: raw)
        guard !guarded.text.isEmpty else {
            emit("[skip] Empty transcript")
            runtimeState = .ready
            return
        }

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
        print(message)
        onLog?(message)
    }
}
