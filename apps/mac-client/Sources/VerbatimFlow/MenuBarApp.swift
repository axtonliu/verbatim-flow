import AppKit
import Carbon.HIToolbox
import Foundation

@MainActor
final class MenuBarApp: NSObject, NSApplicationDelegate {
    private struct TranscriptEntry {
        let text: String
        let createdAt: Date
    }

    private static let maxRecentTranscripts = 8

    private let config: CLIConfig
    private let preferences: AppPreferences
    private var languageSelection: String
    private lazy var controller = AppController(
        config: config,
        languageIsAutoDetect: languageSelection == AppPreferences.systemLanguageToken
    )

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private lazy var aboutMenuItem = NSMenuItem(
        title: "About VerbatimFlow",
        action: #selector(openAboutPanel),
        keyEquivalent: ""
    )
    private let settingsMenuItem = NSMenuItem(title: "Settings", action: nil, keyEquivalent: "")

    private let stateMenuItem = NSMenuItem(title: "State: Starting", action: nil, keyEquivalent: "")
    private lazy var toggleMenuItem = NSMenuItem(
        title: "Pause Hotkey",
        action: #selector(toggleRunning),
        keyEquivalent: ""
    )

    private let modeMenuItem = NSMenuItem(title: "Mode", action: nil, keyEquivalent: "")
    private lazy var formatOnlyModeItem = NSMenuItem(
        title: "Standard (Raw+Format)",
        action: #selector(setFormatOnlyMode),
        keyEquivalent: ""
    )
    private lazy var clarifyModeItem = NSMenuItem(
        title: "Clarify",
        action: #selector(setClarifyMode),
        keyEquivalent: ""
    )

    private let engineMenuItem = NSMenuItem(title: "Recognition Engine", action: nil, keyEquivalent: "")
    private lazy var engineAppleItem = NSMenuItem(
        title: "Apple Speech",
        action: #selector(setEngineApple),
        keyEquivalent: ""
    )
    private lazy var engineWhisperItem = NSMenuItem(
        title: "Whisper",
        action: #selector(setEngineWhisper),
        keyEquivalent: ""
    )
    private lazy var engineOpenAIItem = NSMenuItem(
        title: "OpenAI Cloud",
        action: #selector(setEngineOpenAI),
        keyEquivalent: ""
    )
    private lazy var engineQwenItem = NSMenuItem(
        title: "Qwen3 ASR",
        action: #selector(setEngineQwen),
        keyEquivalent: ""
    )
    private lazy var engineMlxWhisperItem = NSMenuItem(
        title: "MLX Whisper",
        action: #selector(setEngineMlxWhisper),
        keyEquivalent: ""
    )

    private let qwenModelMenuItem = NSMenuItem(title: "Qwen Model", action: nil, keyEquivalent: "")
    private lazy var qwenModelSmallItem = NSMenuItem(
        title: "Qwen3-ASR-0.6B",
        action: #selector(setQwenModelSmall),
        keyEquivalent: ""
    )
    private lazy var qwenModelLargeItem = NSMenuItem(
        title: "Qwen3-ASR-1.7B",
        action: #selector(setQwenModelLarge),
        keyEquivalent: ""
    )
    private let qwenModelInfoItem: NSMenuItem = NSMenuItem(title: "Qwen Model: -", action: nil, keyEquivalent: "")

    private let openAIModelMenuItem = NSMenuItem(title: "OpenAI Model", action: nil, keyEquivalent: "")
    private lazy var openAIModelMiniItem = NSMenuItem(
        title: "gpt-4o-mini-transcribe",
        action: #selector(setOpenAIModelMini),
        keyEquivalent: ""
    )
    private lazy var openAIModelWhisper1Item = NSMenuItem(
        title: "whisper-1",
        action: #selector(setOpenAIModelWhisper1),
        keyEquivalent: ""
    )

    private let whisperModelMenuItem = NSMenuItem(title: "Whisper Model", action: nil, keyEquivalent: "")
    private lazy var whisperModelTinyItem = NSMenuItem(
        title: "tiny",
        action: #selector(setWhisperModelTiny),
        keyEquivalent: ""
    )
    private lazy var whisperModelBaseItem = NSMenuItem(
        title: "base",
        action: #selector(setWhisperModelBase),
        keyEquivalent: ""
    )
    private lazy var whisperModelSmallItem = NSMenuItem(
        title: "small",
        action: #selector(setWhisperModelSmall),
        keyEquivalent: ""
    )
    private lazy var whisperModelMediumItem = NSMenuItem(
        title: "medium",
        action: #selector(setWhisperModelMedium),
        keyEquivalent: ""
    )
    private lazy var whisperModelLargeV3Item = NSMenuItem(
        title: "large-v3",
        action: #selector(setWhisperModelLargeV3),
        keyEquivalent: ""
    )

    private let hotkeyInfoItem: NSMenuItem
    private let clarifyHotkeyInfoItem: NSMenuItem
    private let engineInfoItem: NSMenuItem
    private let whisperModelInfoItem: NSMenuItem
    private let openAIModelInfoItem: NSMenuItem
    private let hotkeyMenuItem = NSMenuItem(title: "Hotkey", action: nil, keyEquivalent: "")
    private let clarifyHotkeyMenuItem = NSMenuItem(title: "Clarify Hotkey", action: nil, keyEquivalent: "")
    private lazy var hotkeyCtrlShiftSpaceItem = NSMenuItem(
        title: "Ctrl+Shift+Space",
        action: #selector(setHotkeyCtrlShiftSpace),
        keyEquivalent: ""
    )
    private lazy var hotkeyShiftOptionItem = NSMenuItem(
        title: "Shift+Option",
        action: #selector(setHotkeyShiftOption),
        keyEquivalent: ""
    )
    private lazy var hotkeyCmdShiftSpaceItem = NSMenuItem(
        title: "Cmd+Shift+Space",
        action: #selector(setHotkeyCmdShiftSpace),
        keyEquivalent: ""
    )
    private lazy var clarifyHotkeyCtrlShiftSpaceItem = NSMenuItem(
        title: "Ctrl+Shift+Space",
        action: #selector(setClarifyHotkeyCtrlShiftSpace),
        keyEquivalent: ""
    )
    private lazy var clarifyHotkeyShiftOptionItem = NSMenuItem(
        title: "Shift+Option",
        action: #selector(setClarifyHotkeyShiftOption),
        keyEquivalent: ""
    )
    private lazy var clarifyHotkeyCmdShiftSpaceItem = NSMenuItem(
        title: "Cmd+Shift+Space",
        action: #selector(setClarifyHotkeyCmdShiftSpace),
        keyEquivalent: ""
    )

    private let languageInfoItem: NSMenuItem
    private let languageMenuItem = NSMenuItem(title: "Language", action: nil, keyEquivalent: "")
    private lazy var languageSystemItem = NSMenuItem(
        title: "System Default",
        action: #selector(setLanguageSystem),
        keyEquivalent: ""
    )
    private lazy var languageZhHansItem = NSMenuItem(
        title: "Chinese (zh-Hans)",
        action: #selector(setLanguageZhHans),
        keyEquivalent: ""
    )
    private lazy var languageZhHantItem = NSMenuItem(
        title: "Traditional Chinese (zh-Hant)",
        action: #selector(setLanguageZhHant),
        keyEquivalent: ""
    )
    private lazy var languageEnUSItem = NSMenuItem(
        title: "English (en-US)",
        action: #selector(setLanguageEnUS),
        keyEquivalent: ""
    )

    private let lastEventItem = NSMenuItem(title: "Last event: -", action: nil, keyEquivalent: "")
    private let permissionStatusItem = NSMenuItem(title: "Permissions: Checking...", action: nil, keyEquivalent: "")
    private let permissionsMenuItem = NSMenuItem(title: "Permissions", action: nil, keyEquivalent: "")

    private let recentMenuItem = NSMenuItem(title: "Recent transcripts", action: nil, keyEquivalent: "")
    private let recentSubmenu = NSMenu(title: "Recent transcripts")
    private lazy var copyLatestTranscriptItem = NSMenuItem(
        title: "Copy Latest Transcript",
        action: #selector(copyLatestTranscript),
        keyEquivalent: ""
    )
    private lazy var copyAndRollbackItem = NSMenuItem(
        title: "Copy + Undo Last Insert",
        action: #selector(copyAndRollbackLatestTranscript),
        keyEquivalent: ""
    )
    private lazy var retryLastFailedAudioItem = NSMenuItem(
        title: "Retry Last Failed Audio",
        action: #selector(retryLastFailedAudio),
        keyEquivalent: ""
    )

    private lazy var requestPermissionsItem = NSMenuItem(
        title: "Request Mic/Speech Permission",
        action: #selector(requestPermissions),
        keyEquivalent: ""
    )

    private lazy var openAccessibilityItem = NSMenuItem(
        title: "Open Accessibility Settings",
        action: #selector(openAccessibilitySettings),
        keyEquivalent: ""
    )

    private lazy var openMicItem = NSMenuItem(
        title: "Open Microphone Settings",
        action: #selector(openMicrophoneSettings),
        keyEquivalent: ""
    )

    private lazy var openSpeechItem = NSMenuItem(
        title: "Open Speech Recognition Settings",
        action: #selector(openSpeechRecognitionSettings),
        keyEquivalent: ""
    )

    private lazy var openInputMonitoringItem = NSMenuItem(
        title: "Open Input Monitoring Settings",
        action: #selector(openInputMonitoringSettings),
        keyEquivalent: ""
    )

    private lazy var openLogsItem = NSMenuItem(
        title: "Open VerbatimFlow Logs",
        action: #selector(openLogsFolder),
        keyEquivalent: ""
    )

    private lazy var openTerminologyItem = NSMenuItem(
        title: "Open Terminology Dictionary",
        action: #selector(openTerminologyDictionary),
        keyEquivalent: ""
    )

    private lazy var openOpenAISettingsItem = NSMenuItem(
        title: "Open OpenAI Cloud Settings",
        action: #selector(openOpenAISettings),
        keyEquivalent: ""
    )

    private lazy var quitItem = NSMenuItem(
        title: "Quit VerbatimFlow",
        action: #selector(quitApp),
        keyEquivalent: "q"
    )

    private var recentTranscripts: [TranscriptEntry] = []
    private var shouldShowPermissionAlertOnNextSnapshot = false
    private var permissionRequestFallbackWorkItem: DispatchWorkItem?
    private var shouldRestoreAccessoryAfterPermissionRequest = false
    private var aboutWindowController: NSWindowController?
    private let initialClarifyHotkey: Hotkey
    private let transcriptDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    init(config: CLIConfig) {
        let preferences = AppPreferences()
        let mode = MenuBarApp.resolveMode(config: config, preferences: preferences)
        let recognitionEngine = MenuBarApp.resolveRecognitionEngine(config: config, preferences: preferences)
        let whisperModel = MenuBarApp.resolveWhisperModel(config: config, preferences: preferences)
        let openAIModel = MenuBarApp.resolveOpenAIModel(config: config, preferences: preferences)
        let qwenModel = MenuBarApp.resolveQwenModel(config: config, preferences: preferences)
        let hotkey = MenuBarApp.resolveHotkey(config: config, preferences: preferences)
        let clarifyHotkey = MenuBarApp.resolveClarifyHotkey(preferences: preferences)
        let languageSelection = MenuBarApp.resolveLanguageSelection(config: config, preferences: preferences)
        let localeIdentifier = MenuBarApp.localeIdentifier(forSelection: languageSelection)

        self.config = CLIConfig(
            mode: mode,
            recognitionEngine: recognitionEngine,
            whisperModel: whisperModel,
            whisperComputeType: config.whisperComputeType,
            openAIModel: openAIModel,
            qwenModel: qwenModel,
            localeIdentifier: localeIdentifier,
            hotkey: hotkey,
            requireOnDeviceRecognition: config.requireOnDeviceRecognition,
            dryRun: config.dryRun
        )
        self.preferences = preferences
        self.languageSelection = languageSelection
        self.initialClarifyHotkey = clarifyHotkey
        self.engineInfoItem = NSMenuItem(title: "Engine: \(recognitionEngine.displayName)", action: nil, keyEquivalent: "")
        self.whisperModelInfoItem = NSMenuItem(title: "Whisper Model: \(whisperModel.displayName)", action: nil, keyEquivalent: "")
        self.openAIModelInfoItem = NSMenuItem(title: "OpenAI Model: \(openAIModel.displayName)", action: nil, keyEquivalent: "")
        self.hotkeyInfoItem = NSMenuItem(title: "Hotkey: \(hotkey.display)", action: nil, keyEquivalent: "")
        self.clarifyHotkeyInfoItem = NSMenuItem(title: "Clarify Hotkey: \(clarifyHotkey.display)", action: nil, keyEquivalent: "")
        self.languageInfoItem = NSMenuItem(title: "Language: \(localeIdentifier)", action: nil, keyEquivalent: "")
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        TerminologyDictionary.ensureDictionaryFileExists()
        OpenAISettings.ensureConfigFileExists()
        setupStatusItem()
        setupMenu()
        bindControllerCallbacks()

        controller.setClarifyHotkey(initialClarifyHotkey)
        controller.start()
        refreshModeChecks()
        refreshEngineChecks()
        refreshHotkeyChecks()
        refreshLanguageChecks()
        refreshRecentTranscriptMenu()
        refreshPermissionStatus(controller.currentPermissionSnapshot())
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller.stop()
    }

    private func setupStatusItem() {
        guard let button = statusItem.button else { return }
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        applyStatusIcon(for: .ready)
        button.toolTip = "VerbatimFlow"
        statusItem.menu = menu
    }

    private func setupMenu() {
        stateMenuItem.isEnabled = false
        engineInfoItem.isEnabled = false
        whisperModelInfoItem.isEnabled = false
        openAIModelInfoItem.isEnabled = false
        qwenModelInfoItem.isEnabled = false
        hotkeyInfoItem.isEnabled = false
        clarifyHotkeyInfoItem.isEnabled = false
        languageInfoItem.isEnabled = false
        lastEventItem.isEnabled = false
        permissionStatusItem.isEnabled = false

        toggleMenuItem.target = self

        formatOnlyModeItem.target = self
        clarifyModeItem.target = self

        let modeSubmenu = NSMenu(title: "Mode")
        modeSubmenu.addItem(formatOnlyModeItem)
        modeSubmenu.addItem(clarifyModeItem)
        modeMenuItem.submenu = modeSubmenu

        engineAppleItem.target = self
        engineWhisperItem.target = self
        engineOpenAIItem.target = self
        engineQwenItem.target = self
        engineMlxWhisperItem.target = self
        let engineSubmenu = NSMenu(title: "Recognition Engine")
        engineSubmenu.addItem(engineAppleItem)
        engineSubmenu.addItem(engineWhisperItem)
        engineSubmenu.addItem(engineOpenAIItem)
        engineSubmenu.addItem(engineQwenItem)
        engineSubmenu.addItem(engineMlxWhisperItem)
        engineMenuItem.submenu = engineSubmenu

        qwenModelSmallItem.target = self
        qwenModelLargeItem.target = self
        let qwenModelSubmenu = NSMenu(title: "Qwen Model")
        qwenModelSubmenu.addItem(qwenModelSmallItem)
        qwenModelSubmenu.addItem(qwenModelLargeItem)
        qwenModelMenuItem.submenu = qwenModelSubmenu

        openAIModelMiniItem.target = self
        openAIModelWhisper1Item.target = self
        let openAIModelSubmenu = NSMenu(title: "OpenAI Model")
        openAIModelSubmenu.addItem(openAIModelMiniItem)
        openAIModelSubmenu.addItem(openAIModelWhisper1Item)
        openAIModelMenuItem.submenu = openAIModelSubmenu

        whisperModelSmallItem.target = self
        whisperModelTinyItem.target = self
        whisperModelBaseItem.target = self
        whisperModelMediumItem.target = self
        whisperModelLargeV3Item.target = self
        let whisperModelSubmenu = NSMenu(title: "Whisper Model")
        whisperModelSubmenu.addItem(whisperModelTinyItem)
        whisperModelSubmenu.addItem(whisperModelBaseItem)
        whisperModelSubmenu.addItem(whisperModelSmallItem)
        whisperModelSubmenu.addItem(whisperModelMediumItem)
        whisperModelSubmenu.addItem(whisperModelLargeV3Item)
        whisperModelMenuItem.submenu = whisperModelSubmenu

        hotkeyCtrlShiftSpaceItem.target = self
        hotkeyShiftOptionItem.target = self
        hotkeyCmdShiftSpaceItem.target = self
        clarifyHotkeyCtrlShiftSpaceItem.target = self
        clarifyHotkeyShiftOptionItem.target = self
        clarifyHotkeyCmdShiftSpaceItem.target = self

        let hotkeySubmenu = NSMenu(title: "Hotkey")
        hotkeySubmenu.addItem(hotkeyCtrlShiftSpaceItem)
        hotkeySubmenu.addItem(hotkeyShiftOptionItem)
        hotkeySubmenu.addItem(hotkeyCmdShiftSpaceItem)
        hotkeyMenuItem.submenu = hotkeySubmenu

        let clarifyHotkeySubmenu = NSMenu(title: "Clarify Hotkey")
        clarifyHotkeySubmenu.addItem(clarifyHotkeyCtrlShiftSpaceItem)
        clarifyHotkeySubmenu.addItem(clarifyHotkeyShiftOptionItem)
        clarifyHotkeySubmenu.addItem(clarifyHotkeyCmdShiftSpaceItem)
        clarifyHotkeyMenuItem.submenu = clarifyHotkeySubmenu

        languageSystemItem.target = self
        languageZhHansItem.target = self
        languageZhHantItem.target = self
        languageEnUSItem.target = self

        let languageSubmenu = NSMenu(title: "Language")
        languageSubmenu.addItem(languageSystemItem)
        languageSubmenu.addItem(languageZhHansItem)
        languageSubmenu.addItem(languageZhHantItem)
        languageSubmenu.addItem(languageEnUSItem)
        languageMenuItem.submenu = languageSubmenu

        copyLatestTranscriptItem.target = self
        copyAndRollbackItem.target = self
        retryLastFailedAudioItem.target = self
        recentMenuItem.submenu = recentSubmenu

        requestPermissionsItem.target = self
        openAccessibilityItem.target = self
        openMicItem.target = self
        openSpeechItem.target = self
        openInputMonitoringItem.target = self
        openLogsItem.target = self
        openTerminologyItem.target = self
        openOpenAISettingsItem.target = self
        aboutMenuItem.target = self

        let permissionsSubmenu = NSMenu(title: "Permissions")
        permissionsSubmenu.addItem(requestPermissionsItem)
        permissionsSubmenu.addItem(openAccessibilityItem)
        permissionsSubmenu.addItem(openInputMonitoringItem)
        permissionsSubmenu.addItem(openMicItem)
        permissionsSubmenu.addItem(openSpeechItem)
        permissionsMenuItem.submenu = permissionsSubmenu

        let settingsSubmenu = NSMenu(title: "Settings")
        settingsSubmenu.addItem(modeMenuItem)
        settingsSubmenu.addItem(engineMenuItem)
        settingsSubmenu.addItem(whisperModelMenuItem)
        settingsSubmenu.addItem(openAIModelMenuItem)
        settingsSubmenu.addItem(qwenModelMenuItem)
        settingsSubmenu.addItem(hotkeyMenuItem)
        settingsSubmenu.addItem(clarifyHotkeyMenuItem)
        settingsSubmenu.addItem(languageMenuItem)
        settingsSubmenu.addItem(NSMenuItem.separator())
        settingsSubmenu.addItem(engineInfoItem)
        settingsSubmenu.addItem(whisperModelInfoItem)
        settingsSubmenu.addItem(openAIModelInfoItem)
        settingsSubmenu.addItem(qwenModelInfoItem)
        settingsSubmenu.addItem(hotkeyInfoItem)
        settingsSubmenu.addItem(clarifyHotkeyInfoItem)
        settingsSubmenu.addItem(languageInfoItem)
        settingsSubmenu.addItem(NSMenuItem.separator())
        settingsSubmenu.addItem(requestPermissionsItem)
        settingsSubmenu.addItem(openAccessibilityItem)
        settingsSubmenu.addItem(openInputMonitoringItem)
        settingsSubmenu.addItem(openMicItem)
        settingsSubmenu.addItem(openSpeechItem)
        settingsSubmenu.addItem(NSMenuItem.separator())
        settingsSubmenu.addItem(openTerminologyItem)
        settingsSubmenu.addItem(openOpenAISettingsItem)
        settingsMenuItem.submenu = settingsSubmenu

        quitItem.target = self

        menu.addItem(stateMenuItem)
        menu.addItem(lastEventItem)
        menu.addItem(permissionStatusItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(toggleMenuItem)
        menu.addItem(aboutMenuItem)
        menu.addItem(settingsMenuItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(recentMenuItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(quitItem)
    }

    private func bindControllerCallbacks() {
        controller.onStateChanged = { [weak self] state in
            self?.applyRuntimeState(state)
            self?.refreshRecentTranscriptMenu()
        }

        controller.onLog = { [weak self] message in
            self?.lastEventItem.title = "Last event: \(message)"
            self?.refreshRecentTranscriptMenu()
        }

        controller.onTranscriptCommitted = { [weak self] text in
            self?.appendRecentTranscript(text)
        }

        controller.onRetriableAudioAvailabilityChanged = { [weak self] _ in
            self?.refreshRecentTranscriptMenu()
        }

        controller.onPermissionSnapshot = { [weak self] snapshot in
            self?.permissionRequestFallbackWorkItem?.cancel()
            self?.refreshPermissionStatus(snapshot)
            if self?.shouldShowPermissionAlertOnNextSnapshot == true {
                self?.shouldShowPermissionAlertOnNextSnapshot = false
                self?.presentPermissionAlert(snapshot)
            }
            self?.restoreAccessoryModeIfNeeded()
        }
    }

    private func applyRuntimeState(_ state: RuntimeState) {
        switch state {
        case .stopped:
            stateMenuItem.title = "State: Stopped"
            toggleMenuItem.title = "Resume Hotkey"
            applyStatusIcon(for: .stopped)
        case .ready:
            stateMenuItem.title = "State: Ready"
            toggleMenuItem.title = "Pause Hotkey"
            applyStatusIcon(for: .ready)
        case .recording:
            stateMenuItem.title = "State: Recording"
            toggleMenuItem.title = "Pause Hotkey"
            applyStatusIcon(for: .recording)
        case .processing:
            stateMenuItem.title = "State: Processing"
            toggleMenuItem.title = "Pause Hotkey"
            applyStatusIcon(for: .processing)
        }
    }

    private func applyStatusIcon(for state: RuntimeState) {
        guard let button = statusItem.button else { return }
        button.image = makeMenuBarIcon(for: state)
        button.title = ""
    }

    private func makeMenuBarIcon(for state: RuntimeState) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let canvas = NSImage(size: size)
        canvas.lockFocus()
        defer { canvas.unlockFocus() }

        NSColor.clear.setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()

        // Draw a template monochrome V mark so menu bar appearance matches
        // native status items (single-color glyph on transparent background).
        NSColor.white.setFill()
        drawMenuBarCapsule(
            center: CGPoint(x: 7.0, y: 9.1),
            size: CGSize(width: 3.4, height: 10.6),
            angleDegrees: 35
        )
        drawMenuBarCapsule(
            center: CGPoint(x: 10.9, y: 9.1),
            size: CGSize(width: 3.4, height: 10.6),
            angleDegrees: -35
        )

        switch state {
        case .ready:
            break
        case .stopped:
            // Paused: short horizontal dash.
            let dashRect = NSRect(x: 12.8, y: 1.3, width: 3.8, height: 1.4)
            let dashPath = NSBezierPath(
                roundedRect: dashRect,
                xRadius: dashRect.height / 2,
                yRadius: dashRect.height / 2
            )
            dashPath.fill()
        case .recording:
            // Recording: filled dot.
            NSBezierPath(ovalIn: NSRect(x: 13.1, y: 0.9, width: 3.6, height: 3.6)).fill()
        case .processing:
            // Processing: hollow ring.
            let ring = NSBezierPath(ovalIn: NSRect(x: 13.0, y: 0.8, width: 3.8, height: 3.8))
            ring.lineWidth = 1.0
            ring.stroke()
        }

        canvas.isTemplate = true
        return canvas
    }

    private func drawMenuBarCapsule(center: CGPoint, size: CGSize, angleDegrees: CGFloat) {
        let rect = NSRect(
            x: -size.width / 2,
            y: -size.height / 2,
            width: size.width,
            height: size.height
        )
        let path = NSBezierPath(
            roundedRect: rect,
            xRadius: size.width / 2,
            yRadius: size.width / 2
        )

        var transform = AffineTransform.identity
        transform.translate(x: center.x, y: center.y)
        transform.rotate(byDegrees: angleDegrees)
        path.transform(using: transform)
        path.fill()
    }

    private func refreshModeChecks() {
        formatOnlyModeItem.state = controller.currentMode == .formatOnly ? .on : .off
        clarifyModeItem.state = controller.currentMode == .clarify ? .on : .off
    }

    private func refreshEngineChecks() {
        let currentEngine = controller.currentRecognitionEngine
        let currentWhisperModel = controller.currentWhisperModel
        let currentOpenAIModel = controller.currentOpenAIModel
        let currentQwenModel = controller.currentQwenModel

        engineInfoItem.title = "Engine: \(currentEngine.displayName)"
        whisperModelInfoItem.title = "Whisper Model: \(currentWhisperModel.displayName)"
        openAIModelInfoItem.title = "OpenAI Model: \(currentOpenAIModel.displayName)"
        qwenModelInfoItem.title = "Qwen Model: \(currentQwenModel.displayName)"

        engineAppleItem.state = currentEngine == .apple ? .on : .off
        engineWhisperItem.state = currentEngine == .whisper ? .on : .off
        engineOpenAIItem.state = currentEngine == .openai ? .on : .off
        engineQwenItem.state = currentEngine == .qwen ? .on : .off
        engineMlxWhisperItem.state = currentEngine == .mlxWhisper ? .on : .off

        whisperModelSmallItem.state = currentWhisperModel == .small ? .on : .off
        whisperModelTinyItem.state = currentWhisperModel == .tiny ? .on : .off
        whisperModelBaseItem.state = currentWhisperModel == .base ? .on : .off
        whisperModelMediumItem.state = currentWhisperModel == .medium ? .on : .off
        whisperModelLargeV3Item.state = currentWhisperModel == .largeV3 ? .on : .off
        openAIModelMiniItem.state = currentOpenAIModel == .gpt4oMiniTranscribe ? .on : .off
        openAIModelWhisper1Item.state = currentOpenAIModel == .whisper1 ? .on : .off
        qwenModelSmallItem.state = currentQwenModel == .small ? .on : .off
        qwenModelLargeItem.state = currentQwenModel == .large ? .on : .off

        whisperModelMenuItem.isEnabled = currentEngine == .whisper
        openAIModelMenuItem.isEnabled = currentEngine == .openai
        qwenModelMenuItem.isEnabled = currentEngine == .qwen
        whisperModelInfoItem.isHidden = currentEngine != .whisper
        openAIModelInfoItem.isHidden = currentEngine != .openai
        qwenModelInfoItem.isHidden = currentEngine != .qwen
    }

    private func refreshHotkeyChecks() {
        hotkeyInfoItem.title = "Hotkey: \(controller.currentHotkeyDisplay)"
        clarifyHotkeyInfoItem.title = "Clarify Hotkey: \(controller.currentClarifyHotkeyDisplay)"
        hotkeyMenuItem.title = "Hotkey: \(humanHotkeyLabel(controller.currentHotkeyDisplay))"
        clarifyHotkeyMenuItem.title = "Clarify Hotkey: \(humanHotkeyLabel(controller.currentClarifyHotkeyDisplay))"
        hotkeyCtrlShiftSpaceItem.state = isCurrentHotkey("ctrl+shift+space") ? .on : .off
        hotkeyShiftOptionItem.state = isCurrentHotkey("shift+option") ? .on : .off
        hotkeyCmdShiftSpaceItem.state = isCurrentHotkey("cmd+shift+space") ? .on : .off
        clarifyHotkeyCtrlShiftSpaceItem.state = isCurrentClarifyHotkey("ctrl+shift+space") ? .on : .off
        clarifyHotkeyShiftOptionItem.state = isCurrentClarifyHotkey("shift+option") ? .on : .off
        clarifyHotkeyCmdShiftSpaceItem.state = isCurrentClarifyHotkey("cmd+shift+space") ? .on : .off
    }

    private func isCurrentHotkey(_ combo: String) -> Bool {
        guard let parsed = try? HotkeyParser.parse(combo: combo) else {
            return false
        }
        return parsed.keyCode == controller.currentHotkey.keyCode &&
            parsed.modifiers == controller.currentHotkey.modifiers
    }

    private func isCurrentClarifyHotkey(_ combo: String) -> Bool {
        guard let parsed = try? HotkeyParser.parse(combo: combo) else {
            return false
        }
        return parsed.keyCode == controller.currentClarifyHotkey.keyCode &&
            parsed.modifiers == controller.currentClarifyHotkey.modifiers
    }

    private func refreshLanguageChecks() {
        languageInfoItem.title = "Language: \(controller.currentLocaleIdentifier)"
        languageSystemItem.state = languageSelection == AppPreferences.systemLanguageToken ? .on : .off
        languageZhHansItem.state = languageSelection == "zh-Hans" ? .on : .off
        languageZhHantItem.state = languageSelection == "zh-Hant" ? .on : .off
        languageEnUSItem.state = languageSelection == "en-US" ? .on : .off
    }

    private func refreshRecentTranscriptMenu() {
        recentSubmenu.removeAllItems()

        recentSubmenu.addItem(copyLatestTranscriptItem)
        recentSubmenu.addItem(copyAndRollbackItem)
        recentSubmenu.addItem(retryLastFailedAudioItem)
        recentSubmenu.addItem(NSMenuItem.separator())

        let hasRecent = !recentTranscripts.isEmpty
        copyLatestTranscriptItem.isEnabled = hasRecent
        copyAndRollbackItem.isEnabled = hasRecent
        retryLastFailedAudioItem.isEnabled = controller.canRetryLastFailedAudio

        guard hasRecent else {
            let emptyItem = NSMenuItem(title: "No transcripts yet", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            recentSubmenu.addItem(emptyItem)
            return
        }

        for (index, entry) in recentTranscripts.enumerated() {
            let item = NSMenuItem(
                title: "\(index + 1). \(historyPreview(for: entry))",
                action: #selector(copyRecentTranscript(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = entry.text
            recentSubmenu.addItem(item)
        }
    }

    private func refreshPermissionStatus(_ snapshot: PermissionSnapshot) {
        permissionStatusItem.title = "Permissions: \(snapshot.summaryLine)"
    }

    private func appendRecentTranscript(_ text: String) {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return
        }

        recentTranscripts.removeAll { $0.text == normalized }
        recentTranscripts.insert(TranscriptEntry(text: normalized, createdAt: Date()), at: 0)

        if recentTranscripts.count > Self.maxRecentTranscripts {
            recentTranscripts.removeLast(recentTranscripts.count - Self.maxRecentTranscripts)
        }

        refreshRecentTranscriptMenu()
    }

    private func historyPreview(for entry: TranscriptEntry) -> String {
        let timestamp = transcriptDateFormatter.string(from: entry.createdAt)
        let singleLine = entry.text.replacingOccurrences(of: "\n", with: " ")
        let previewLimit = 58
        let preview: String
        if singleLine.count > previewLimit {
            preview = String(singleLine.prefix(previewLimit)) + "…"
        } else {
            preview = singleLine
        }
        return "[\(timestamp)] \(preview)"
    }

    @objc
    private func toggleRunning() {
        if controller.isRunning {
            controller.stop()
            return
        }
        controller.start()
    }

    @objc
    private func setFormatOnlyMode() {
        controller.setMode(.formatOnly)
        preferences.saveMode(.formatOnly)
        refreshModeChecks()
    }

    @objc
    private func setClarifyMode() {
        controller.setMode(.clarify)
        preferences.saveMode(.clarify)
        refreshModeChecks()
    }

    @objc
    private func setEngineApple() {
        setRecognitionEngine(.apple)
    }

    @objc
    private func setEngineWhisper() {
        setRecognitionEngine(.whisper)
    }

    @objc
    private func setEngineOpenAI() {
        setRecognitionEngine(.openai)
    }

    @objc
    private func setEngineQwen() {
        setRecognitionEngine(.qwen)
    }

    @objc
    private func setEngineMlxWhisper() {
        setRecognitionEngine(.mlxWhisper)
    }

    private func setRecognitionEngine(_ engine: RecognitionEngine) {
        controller.setRecognitionEngine(engine)
        preferences.saveRecognitionEngine(controller.currentRecognitionEngine)
        refreshEngineChecks()
    }

    @objc
    private func setWhisperModelTiny() {
        setWhisperModel(.tiny)
    }

    @objc
    private func setWhisperModelBase() {
        setWhisperModel(.base)
    }

    @objc
    private func setWhisperModelSmall() {
        setWhisperModel(.small)
    }

    @objc
    private func setWhisperModelMedium() {
        setWhisperModel(.medium)
    }

    @objc
    private func setWhisperModelLargeV3() {
        setWhisperModel(.largeV3)
    }

    private func setWhisperModel(_ model: WhisperModel) {
        controller.setWhisperModel(model)
        preferences.saveWhisperModel(controller.currentWhisperModel)
        refreshEngineChecks()
    }

    @objc
    private func setOpenAIModelMini() {
        setOpenAIModel(.gpt4oMiniTranscribe)
    }

    @objc
    private func setOpenAIModelWhisper1() {
        setOpenAIModel(.whisper1)
    }

    private func setOpenAIModel(_ model: OpenAITranscriptionModel) {
        controller.setOpenAIModel(model)
        preferences.saveOpenAIModel(controller.currentOpenAIModel)
        refreshEngineChecks()
    }

    @objc
    private func setQwenModelSmall() {
        setQwenModel(.small)
    }

    @objc
    private func setQwenModelLarge() {
        setQwenModel(.large)
    }

    private func setQwenModel(_ model: QwenModel) {
        controller.setQwenModel(model)
        preferences.saveQwenModel(controller.currentQwenModel)
        refreshEngineChecks()
    }

    @objc
    private func setHotkeyCtrlShiftSpace() {
        setHotkeyCombo("ctrl+shift+space")
    }

    @objc
    private func setHotkeyShiftOption() {
        setHotkeyCombo("shift+option")
    }

    @objc
    private func setHotkeyCmdShiftSpace() {
        setHotkeyCombo("cmd+shift+space")
    }

    private func setHotkeyCombo(_ combo: String) {
        do {
            let parsed = try HotkeyParser.parse(combo: combo)
            guard !hotkeysConflict(parsed, controller.currentClarifyHotkey) else {
                lastEventItem.title = "Last event: [error] primary hotkey conflicts with clarify hotkey"
                return
            }
            controller.setHotkey(parsed)
            preferences.saveHotkey(parsed)
            refreshHotkeyChecks()
        } catch {
            lastEventItem.title = "Last event: [error] invalid hotkey \(combo)"
        }
    }

    @objc
    private func setClarifyHotkeyCtrlShiftSpace() {
        setClarifyHotkeyCombo("ctrl+shift+space")
    }

    @objc
    private func setClarifyHotkeyShiftOption() {
        setClarifyHotkeyCombo("shift+option")
    }

    @objc
    private func setClarifyHotkeyCmdShiftSpace() {
        setClarifyHotkeyCombo("cmd+shift+space")
    }

    private func setClarifyHotkeyCombo(_ combo: String) {
        do {
            let parsed = try HotkeyParser.parse(combo: combo)
            guard !hotkeysConflict(parsed, controller.currentHotkey) else {
                lastEventItem.title = "Last event: [error] clarify hotkey conflicts with primary hotkey"
                return
            }
            controller.setClarifyHotkey(parsed)
            preferences.saveClarifyHotkey(parsed)
            refreshHotkeyChecks()
        } catch {
            lastEventItem.title = "Last event: [error] invalid clarify hotkey \(combo)"
        }
    }

    @objc
    private func setLanguageSystem() {
        setLanguageSelection(AppPreferences.systemLanguageToken)
    }

    @objc
    private func setLanguageZhHans() {
        setLanguageSelection("zh-Hans")
    }

    @objc
    private func setLanguageZhHant() {
        setLanguageSelection("zh-Hant")
    }

    @objc
    private func setLanguageEnUS() {
        setLanguageSelection("en-US")
    }

    private func setLanguageSelection(_ selection: String) {
        languageSelection = selection
        let localeIdentifier = Self.localeIdentifier(forSelection: selection)
        controller.setLocaleIdentifier(localeIdentifier, isAutoDetect: selection == AppPreferences.systemLanguageToken)
        preferences.saveLanguageSelection(selection)
        refreshLanguageChecks()
    }

    @objc
    private func copyLatestTranscript() {
        guard let latest = recentTranscripts.first else {
            return
        }
        controller.copyTranscriptToClipboard(latest.text)
    }

    @objc
    private func copyAndRollbackLatestTranscript() {
        guard let latest = recentTranscripts.first else {
            return
        }
        controller.copyAndUndoLastInsert(latest.text)
    }

    @objc
    private func retryLastFailedAudio() {
        controller.retryLastFailedAudio()
    }

    @objc
    private func copyRecentTranscript(_ sender: NSMenuItem) {
        guard let text = sender.representedObject as? String else {
            return
        }
        controller.copyTranscriptToClipboard(text)
    }

    @objc
    private func requestPermissions() {
        RuntimeLogger.log("[permissions] menu click request initiated")
        RuntimeLogger.log("[permissions] activationPolicy=\(activationPolicyDescription(NSApp.activationPolicy()))")
        permissionRequestFallbackWorkItem?.cancel()
        RuntimeLogger.log("[permissions] menu before elevateForPermissionPromptIfNeeded")
        elevateForPermissionPromptIfNeeded()
        RuntimeLogger.log("[permissions] menu after elevateForPermissionPromptIfNeeded")
        lastEventItem.title = "Last event: [permissions] request initiated"
        permissionStatusItem.title = "Permissions: Requesting..."
        refreshPermissionStatus(controller.currentPermissionSnapshot())
        shouldShowPermissionAlertOnNextSnapshot = true
        RuntimeLogger.log("[permissions] menu calling controller.requestSpeechAndMicrophonePermissions")
        controller.requestSpeechAndMicrophonePermissions()
        RuntimeLogger.log("[permissions] menu returned from controller.requestSpeechAndMicrophonePermissions")

        let fallback = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard self.shouldShowPermissionAlertOnNextSnapshot else { return }
            RuntimeLogger.log("[permissions] menu fallback fired")
            self.shouldShowPermissionAlertOnNextSnapshot = false
            let snapshot = self.controller.currentPermissionSnapshot()
            self.refreshPermissionStatus(snapshot)
            self.lastEventItem.title = "Last event: [permissions] request timed out; check system settings"
            self.presentPermissionAlert(snapshot)
            self.restoreAccessoryModeIfNeeded()
        }
        permissionRequestFallbackWorkItem = fallback
        DispatchQueue.main.asyncAfter(deadline: .now() + 6.0, execute: fallback)
    }

    @objc
    private func openAccessibilitySettings() {
        openSystemSettings(url: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    @objc
    private func openInputMonitoringSettings() {
        openSystemSettings(url: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
    }

    @objc
    private func openMicrophoneSettings() {
        openSystemSettings(url: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
    }

    @objc
    private func openSpeechRecognitionSettings() {
        openSystemSettings(url: "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition")
    }

    private func openSystemSettings(url: String) {
        guard let target = URL(string: url) else { return }
        NSWorkspace.shared.open(target)
    }

    @objc
    private func openLogsFolder() {
        let logFile = RuntimeLogger.logFileURL
        let directory = logFile.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)

        if FileManager.default.fileExists(atPath: logFile.path) {
            NSWorkspace.shared.activateFileViewerSelecting([logFile])
            return
        }

        NSWorkspace.shared.open(directory)
    }

    @objc
    private func openTerminologyDictionary() {
        TerminologyDictionary.ensureDictionaryFileExists()
        NSWorkspace.shared.open(TerminologyDictionary.fileURL)
    }

    @objc
    private func openOpenAISettings() {
        OpenAISettings.ensureConfigFileExists()
        NSWorkspace.shared.open(OpenAISettings.fileURL)
    }

    @objc
    private func openAboutPanel() {
        if aboutWindowController == nil {
            aboutWindowController = makeAboutWindowController()
        }

        guard let window = aboutWindowController?.window else {
            return
        }

        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc
    private func openAxtonHomepage() {
        openExternalURL("https://www.axtonliu.ai")
    }

    @objc
    private func openAgentSkillsLibrary() {
        openExternalURL("https://www.axtonliu.ai/agent-skills")
    }

    @objc
    private func openAgentSkillsOriginGuide() {
        openExternalURL("https://www.axtonliu.ai/newsletters/ai-2/posts/claude-agent-skills-maps-framework")
    }

    @objc
    private func openAxtonYouTube() {
        openExternalURL("https://youtube.com/@AxtonLiu")
    }

    @objc
    private func openAxtonX() {
        openExternalURL("https://twitter.com/axtonliu")
    }

    private func makeAboutWindowController() -> NSWindowController {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 420),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "About VerbatimFlow"
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 520, height: 380)

        let rootView = NSView()
        rootView.translatesAutoresizingMaskIntoConstraints = false
        window.contentView = rootView

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        rootView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: rootView.leadingAnchor, constant: 22),
            stack.trailingAnchor.constraint(equalTo: rootView.trailingAnchor, constant: -22),
            stack.topAnchor.constraint(equalTo: rootView.topAnchor, constant: 20)
        ])

        let titleLabel = NSTextField(labelWithString: "VerbatimFlow")
        titleLabel.font = NSFont.systemFont(ofSize: 24, weight: .semibold)
        stack.addArrangedSubview(titleLabel)

        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.1"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "2"
        let versionLabel = NSTextField(labelWithString: "Version \(version) (\(build))")
        versionLabel.textColor = .secondaryLabelColor
        stack.addArrangedSubview(versionLabel)

        let descriptionLabel = NSTextField(
            wrappingLabelWithString: "Fast dictation input for macOS. Hold hotkey to record, release to transcribe and insert."
        )
        descriptionLabel.maximumNumberOfLines = 0
        descriptionLabel.preferredMaxLayoutWidth = 480
        stack.addArrangedSubview(descriptionLabel)

        let linksHeader = NSTextField(labelWithString: "Resources")
        linksHeader.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        stack.addArrangedSubview(linksHeader)

        stack.addArrangedSubview(makeAboutLinkButton(title: "Axton Homepage", action: #selector(openAxtonHomepage)))
        stack.addArrangedSubview(makeAboutLinkButton(title: "Agent Skills Resource Library", action: #selector(openAgentSkillsLibrary)))
        stack.addArrangedSubview(makeAboutLinkButton(title: "Agent Skills Origin Guide", action: #selector(openAgentSkillsOriginGuide)))
        stack.addArrangedSubview(makeAboutLinkButton(title: "Axton YouTube", action: #selector(openAxtonYouTube)))
        stack.addArrangedSubview(makeAboutLinkButton(title: "Axton X / Twitter", action: #selector(openAxtonX)))

        let footer = NSTextField(labelWithString: "© VerbatimFlow. Experimental release.")
        footer.textColor = .tertiaryLabelColor
        stack.addArrangedSubview(footer)

        return NSWindowController(window: window)
    }

    private func makeAboutLinkButton(title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.setButtonType(.momentaryPushIn)
        button.isBordered = false
        button.font = NSFont.systemFont(ofSize: 13, weight: .regular)
        button.contentTintColor = .linkColor
        button.alignment = .left
        return button
    }

    private func openExternalURL(_ rawURL: String) {
        guard let url = URL(string: rawURL) else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func elevateForPermissionPromptIfNeeded() {
        guard NSApp.activationPolicy() == .accessory else {
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        if NSApp.setActivationPolicy(.regular) {
            shouldRestoreAccessoryAfterPermissionRequest = true
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    private func restoreAccessoryModeIfNeeded() {
        guard shouldRestoreAccessoryAfterPermissionRequest else {
            return
        }
        shouldRestoreAccessoryAfterPermissionRequest = false
        _ = NSApp.setActivationPolicy(.accessory)
    }

    private func activationPolicyDescription(_ policy: NSApplication.ActivationPolicy) -> String {
        switch policy {
        case .regular:
            return "regular"
        case .accessory:
            return "accessory"
        case .prohibited:
            return "prohibited"
        @unknown default:
            return "unknown"
        }
    }

    private func presentPermissionAlert(_ snapshot: PermissionSnapshot) {
        let alert = NSAlert()
        alert.alertStyle = snapshot.isReadyForHotkeyDictation ? .informational : .warning
        alert.messageText = snapshot.isReadyForHotkeyDictation
            ? "Permissions are ready"
            : "Permissions are incomplete"
        alert.informativeText = snapshot.summaryLine
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    @objc
    private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    private static func hasCLIFlag(_ flag: String) -> Bool {
        CommandLine.arguments.contains(flag)
    }

    private static func resolveMode(config: CLIConfig, preferences: AppPreferences) -> OutputMode {
        let normalize: (OutputMode) -> OutputMode = { mode in
            mode == .raw ? .formatOnly : mode
        }
        if hasCLIFlag("--mode") {
            return normalize(config.mode)
        }
        return normalize(preferences.loadMode() ?? config.mode)
    }

    private static func resolveRecognitionEngine(config: CLIConfig, preferences: AppPreferences) -> RecognitionEngine {
        if hasCLIFlag("--engine") {
            return config.recognitionEngine
        }
        return preferences.loadRecognitionEngine() ?? config.recognitionEngine
    }

    private static func resolveWhisperModel(config: CLIConfig, preferences: AppPreferences) -> WhisperModel {
        if hasCLIFlag("--whisper-model") {
            return config.whisperModel
        }
        return preferences.loadWhisperModel() ?? config.whisperModel
    }

    private static func resolveOpenAIModel(config: CLIConfig, preferences: AppPreferences) -> OpenAITranscriptionModel {
        if hasCLIFlag("--openai-model") {
            return config.openAIModel
        }
        return preferences.loadOpenAIModel() ?? config.openAIModel
    }

    private static func resolveQwenModel(config: CLIConfig, preferences: AppPreferences) -> QwenModel {
        if hasCLIFlag("--qwen-model") {
            return config.qwenModel
        }
        return preferences.loadQwenModel() ?? config.qwenModel
    }

    private static func resolveHotkey(config: CLIConfig, preferences: AppPreferences) -> Hotkey {
        if hasCLIFlag("--hotkey") {
            return config.hotkey
        }
        return preferences.loadHotkey() ?? config.hotkey
    }

    private static func resolveClarifyHotkey(preferences: AppPreferences) -> Hotkey {
        preferences.loadClarifyHotkey() ?? AppController.defaultClarifyHotkeyValue
    }

    private static func resolveLanguageSelection(config: CLIConfig, preferences: AppPreferences) -> String {
        if hasCLIFlag("--locale") {
            return config.localeIdentifier
        }
        return preferences.loadLanguageSelection() ?? AppPreferences.systemLanguageToken
    }

    private static func localeIdentifier(forSelection selection: String) -> String {
        if selection == AppPreferences.systemLanguageToken {
            return recommendedSystemLocaleIdentifier()
        }
        return selection
    }

    private static func recommendedSystemLocaleIdentifier() -> String {
        if let inputSourceLanguage = currentInputSourceLanguageCode() {
            return mappedLocaleIdentifier(forLanguageCode: inputSourceLanguage)
        }

        if let preferred = Locale.preferredLanguages.first {
            return mappedLocaleIdentifier(forLanguageCode: preferred)
        }

        return Locale.autoupdatingCurrent.identifier
    }

    private func hotkeysConflict(_ lhs: Hotkey, _ rhs: Hotkey) -> Bool {
        lhs.keyCode == rhs.keyCode && lhs.modifiers == rhs.modifiers
    }

    private func humanHotkeyLabel(_ combo: String) -> String {
        combo
            .split(separator: "+")
            .map { token in
                switch token.lowercased() {
                case "ctrl": return "Ctrl"
                case "cmd": return "Cmd"
                case "shift": return "Shift"
                case "option": return "Option"
                case "space": return "Space"
                default: return String(token)
                }
            }
            .joined(separator: "+")
    }

    private static func currentInputSourceLanguageCode() -> String? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            return nil
        }
        guard let languages = TISGetInputSourceProperty(source, kTISPropertyInputSourceLanguages) else {
            return nil
        }
        let array = Unmanaged<CFArray>.fromOpaque(languages).takeUnretainedValue() as NSArray
        return array.firstObject as? String
    }

    private static func mappedLocaleIdentifier(forLanguageCode code: String) -> String {
        let lowercased = code.lowercased()
        if lowercased.hasPrefix("zh-hant") || lowercased.hasPrefix("zh-tw") || lowercased.hasPrefix("zh-hk") {
            return "zh-Hant"
        }
        if lowercased.hasPrefix("zh") {
            return "zh-Hans"
        }
        if lowercased.hasPrefix("en") {
            return "en-US"
        }
        return code
    }
}
