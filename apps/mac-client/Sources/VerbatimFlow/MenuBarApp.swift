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
    private lazy var controller = AppController(config: config)

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()

    private let stateMenuItem = NSMenuItem(title: "State: Starting", action: nil, keyEquivalent: "")
    private lazy var toggleMenuItem = NSMenuItem(
        title: "Pause Hotkey",
        action: #selector(toggleRunning),
        keyEquivalent: "p"
    )

    private let modeMenuItem = NSMenuItem(title: "Mode", action: nil, keyEquivalent: "")
    private lazy var rawModeItem = NSMenuItem(
        title: "Raw",
        action: #selector(setRawMode),
        keyEquivalent: "r"
    )
    private lazy var formatOnlyModeItem = NSMenuItem(
        title: "Format-only",
        action: #selector(setFormatOnlyMode),
        keyEquivalent: "f"
    )
    private lazy var clarifyModeItem = NSMenuItem(
        title: "Clarify",
        action: #selector(setClarifyMode),
        keyEquivalent: "c"
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
    private let engineInfoItem: NSMenuItem
    private let whisperModelInfoItem: NSMenuItem
    private let hotkeyMenuItem = NSMenuItem(title: "Hotkey", action: nil, keyEquivalent: "")
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
    private lazy var languageEnUSItem = NSMenuItem(
        title: "English (en-US)",
        action: #selector(setLanguageEnUS),
        keyEquivalent: ""
    )

    private let lastEventItem = NSMenuItem(title: "Last event: -", action: nil, keyEquivalent: "")
    private let permissionStatusItem = NSMenuItem(title: "Permissions: Checking...", action: nil, keyEquivalent: "")

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
        let hotkey = MenuBarApp.resolveHotkey(config: config, preferences: preferences)
        let languageSelection = MenuBarApp.resolveLanguageSelection(config: config, preferences: preferences)
        let localeIdentifier = MenuBarApp.localeIdentifier(forSelection: languageSelection)

        self.config = CLIConfig(
            mode: mode,
            recognitionEngine: recognitionEngine,
            whisperModel: whisperModel,
            whisperComputeType: config.whisperComputeType,
            localeIdentifier: localeIdentifier,
            hotkey: hotkey,
            requireOnDeviceRecognition: config.requireOnDeviceRecognition,
            dryRun: config.dryRun
        )
        self.preferences = preferences
        self.languageSelection = languageSelection
        self.engineInfoItem = NSMenuItem(title: "Engine: \(recognitionEngine.displayName)", action: nil, keyEquivalent: "")
        self.whisperModelInfoItem = NSMenuItem(title: "Whisper Model: \(whisperModel.displayName)", action: nil, keyEquivalent: "")
        self.hotkeyInfoItem = NSMenuItem(title: "Hotkey: \(hotkey.display)", action: nil, keyEquivalent: "")
        self.languageInfoItem = NSMenuItem(title: "Language: \(localeIdentifier)", action: nil, keyEquivalent: "")
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        TerminologyDictionary.ensureDictionaryFileExists()
        OpenAISettings.ensureConfigFileExists()
        setupStatusItem()
        setupMenu()
        bindControllerCallbacks()

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
        button.title = "VF"
        button.toolTip = "VerbatimFlow"
        statusItem.menu = menu
    }

    private func setupMenu() {
        stateMenuItem.isEnabled = false
        engineInfoItem.isEnabled = false
        whisperModelInfoItem.isEnabled = false
        hotkeyInfoItem.isEnabled = false
        languageInfoItem.isEnabled = false
        lastEventItem.isEnabled = false
        permissionStatusItem.isEnabled = false

        toggleMenuItem.target = self

        rawModeItem.target = self
        formatOnlyModeItem.target = self
        clarifyModeItem.target = self

        let modeSubmenu = NSMenu(title: "Mode")
        modeSubmenu.addItem(rawModeItem)
        modeSubmenu.addItem(formatOnlyModeItem)
        modeSubmenu.addItem(clarifyModeItem)
        modeMenuItem.submenu = modeSubmenu

        engineAppleItem.target = self
        engineWhisperItem.target = self
        engineOpenAIItem.target = self
        let engineSubmenu = NSMenu(title: "Recognition Engine")
        engineSubmenu.addItem(engineAppleItem)
        engineSubmenu.addItem(engineWhisperItem)
        engineSubmenu.addItem(engineOpenAIItem)
        engineMenuItem.submenu = engineSubmenu

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

        let hotkeySubmenu = NSMenu(title: "Hotkey")
        hotkeySubmenu.addItem(hotkeyCtrlShiftSpaceItem)
        hotkeySubmenu.addItem(hotkeyShiftOptionItem)
        hotkeySubmenu.addItem(hotkeyCmdShiftSpaceItem)
        hotkeyMenuItem.submenu = hotkeySubmenu

        languageSystemItem.target = self
        languageZhHansItem.target = self
        languageEnUSItem.target = self

        let languageSubmenu = NSMenu(title: "Language")
        languageSubmenu.addItem(languageSystemItem)
        languageSubmenu.addItem(languageZhHansItem)
        languageSubmenu.addItem(languageEnUSItem)
        languageMenuItem.submenu = languageSubmenu

        copyLatestTranscriptItem.target = self
        copyAndRollbackItem.target = self
        recentMenuItem.submenu = recentSubmenu

        requestPermissionsItem.target = self
        openAccessibilityItem.target = self
        openMicItem.target = self
        openSpeechItem.target = self
        openInputMonitoringItem.target = self
        openLogsItem.target = self
        openTerminologyItem.target = self
        openOpenAISettingsItem.target = self

        quitItem.target = self

        menu.addItem(stateMenuItem)
        menu.addItem(lastEventItem)
        menu.addItem(permissionStatusItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(toggleMenuItem)
        menu.addItem(modeMenuItem)
        menu.addItem(engineMenuItem)
        menu.addItem(whisperModelMenuItem)
        menu.addItem(hotkeyMenuItem)
        menu.addItem(languageMenuItem)
        menu.addItem(engineInfoItem)
        menu.addItem(whisperModelInfoItem)
        menu.addItem(hotkeyInfoItem)
        menu.addItem(languageInfoItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(recentMenuItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(requestPermissionsItem)
        menu.addItem(openAccessibilityItem)
        menu.addItem(openInputMonitoringItem)
        menu.addItem(openMicItem)
        menu.addItem(openSpeechItem)
        menu.addItem(openTerminologyItem)
        menu.addItem(openOpenAISettingsItem)
        menu.addItem(openLogsItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(quitItem)
    }

    private func bindControllerCallbacks() {
        controller.onStateChanged = { [weak self] state in
            self?.applyRuntimeState(state)
        }

        controller.onLog = { [weak self] message in
            self?.lastEventItem.title = "Last event: \(message)"
        }

        controller.onTranscriptCommitted = { [weak self] text in
            self?.appendRecentTranscript(text)
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
            statusItem.button?.title = "VF⏸"
        case .ready:
            stateMenuItem.title = "State: Ready"
            toggleMenuItem.title = "Pause Hotkey"
            statusItem.button?.title = "VF"
        case .recording:
            stateMenuItem.title = "State: Recording"
            toggleMenuItem.title = "Pause Hotkey"
            statusItem.button?.title = "VF●"
        case .processing:
            stateMenuItem.title = "State: Processing"
            toggleMenuItem.title = "Pause Hotkey"
            statusItem.button?.title = "VF…"
        }
    }

    private func refreshModeChecks() {
        rawModeItem.state = controller.currentMode == .raw ? .on : .off
        formatOnlyModeItem.state = controller.currentMode == .formatOnly ? .on : .off
        clarifyModeItem.state = controller.currentMode == .clarify ? .on : .off
    }

    private func refreshEngineChecks() {
        let currentEngine = controller.currentRecognitionEngine
        let currentWhisperModel = controller.currentWhisperModel

        engineInfoItem.title = "Engine: \(currentEngine.displayName)"
        whisperModelInfoItem.title = "Whisper Model: \(currentWhisperModel.displayName)"

        engineAppleItem.state = currentEngine == .apple ? .on : .off
        engineWhisperItem.state = currentEngine == .whisper ? .on : .off
        engineOpenAIItem.state = currentEngine == .openai ? .on : .off

        whisperModelSmallItem.state = currentWhisperModel == .small ? .on : .off
        whisperModelTinyItem.state = currentWhisperModel == .tiny ? .on : .off
        whisperModelBaseItem.state = currentWhisperModel == .base ? .on : .off
        whisperModelMediumItem.state = currentWhisperModel == .medium ? .on : .off
        whisperModelLargeV3Item.state = currentWhisperModel == .largeV3 ? .on : .off

        whisperModelMenuItem.isEnabled = currentEngine == .whisper
        whisperModelInfoItem.isHidden = currentEngine != .whisper
    }

    private func refreshHotkeyChecks() {
        hotkeyInfoItem.title = "Hotkey: \(controller.currentHotkeyDisplay)"
        hotkeyCtrlShiftSpaceItem.state = isCurrentHotkey("ctrl+shift+space") ? .on : .off
        hotkeyShiftOptionItem.state = isCurrentHotkey("shift+option") ? .on : .off
        hotkeyCmdShiftSpaceItem.state = isCurrentHotkey("cmd+shift+space") ? .on : .off
    }

    private func isCurrentHotkey(_ combo: String) -> Bool {
        guard let parsed = try? HotkeyParser.parse(combo: combo) else {
            return false
        }
        return parsed.keyCode == controller.currentHotkey.keyCode &&
            parsed.modifiers == controller.currentHotkey.modifiers
    }

    private func refreshLanguageChecks() {
        languageInfoItem.title = "Language: \(controller.currentLocaleIdentifier)"
        languageSystemItem.state = languageSelection == AppPreferences.systemLanguageToken ? .on : .off
        languageZhHansItem.state = languageSelection == "zh-Hans" ? .on : .off
        languageEnUSItem.state = languageSelection == "en-US" ? .on : .off
    }

    private func refreshRecentTranscriptMenu() {
        recentSubmenu.removeAllItems()

        recentSubmenu.addItem(copyLatestTranscriptItem)
        recentSubmenu.addItem(copyAndRollbackItem)
        recentSubmenu.addItem(NSMenuItem.separator())

        let hasRecent = !recentTranscripts.isEmpty
        copyLatestTranscriptItem.isEnabled = hasRecent
        copyAndRollbackItem.isEnabled = hasRecent

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
    private func setRawMode() {
        controller.setMode(.raw)
        preferences.saveMode(.raw)
        refreshModeChecks()
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
            controller.setHotkey(parsed)
            preferences.saveHotkey(parsed)
            refreshHotkeyChecks()
        } catch {
            lastEventItem.title = "Last event: [error] invalid hotkey \(combo)"
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
    private func setLanguageEnUS() {
        setLanguageSelection("en-US")
    }

    private func setLanguageSelection(_ selection: String) {
        languageSelection = selection
        let localeIdentifier = Self.localeIdentifier(forSelection: selection)
        controller.setLocaleIdentifier(localeIdentifier)
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
        if hasCLIFlag("--mode") {
            return config.mode
        }
        return preferences.loadMode() ?? config.mode
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

    private static func resolveHotkey(config: CLIConfig, preferences: AppPreferences) -> Hotkey {
        if hasCLIFlag("--hotkey") {
            return config.hotkey
        }
        return preferences.loadHotkey() ?? config.hotkey
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
