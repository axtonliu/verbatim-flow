import AppKit
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

    private let hotkeyInfoItem: NSMenuItem
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
        let hotkey = MenuBarApp.resolveHotkey(config: config, preferences: preferences)
        let languageSelection = MenuBarApp.resolveLanguageSelection(config: config, preferences: preferences)
        let localeIdentifier = MenuBarApp.localeIdentifier(forSelection: languageSelection)

        self.config = CLIConfig(
            mode: mode,
            localeIdentifier: localeIdentifier,
            hotkey: hotkey,
            requireOnDeviceRecognition: config.requireOnDeviceRecognition,
            dryRun: config.dryRun
        )
        self.preferences = preferences
        self.languageSelection = languageSelection
        self.hotkeyInfoItem = NSMenuItem(title: "Hotkey: \(hotkey.display)", action: nil, keyEquivalent: "")
        self.languageInfoItem = NSMenuItem(title: "Language: \(localeIdentifier)", action: nil, keyEquivalent: "")
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupMenu()
        bindControllerCallbacks()

        controller.start()
        refreshModeChecks()
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
        hotkeyInfoItem.isEnabled = false
        languageInfoItem.isEnabled = false
        lastEventItem.isEnabled = false
        permissionStatusItem.isEnabled = false

        toggleMenuItem.target = self

        rawModeItem.target = self
        formatOnlyModeItem.target = self

        let modeSubmenu = NSMenu(title: "Mode")
        modeSubmenu.addItem(rawModeItem)
        modeSubmenu.addItem(formatOnlyModeItem)
        modeMenuItem.submenu = modeSubmenu

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

        quitItem.target = self

        menu.addItem(stateMenuItem)
        menu.addItem(lastEventItem)
        menu.addItem(permissionStatusItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(toggleMenuItem)
        menu.addItem(modeMenuItem)
        menu.addItem(hotkeyMenuItem)
        menu.addItem(languageMenuItem)
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
        permissionRequestFallbackWorkItem?.cancel()
        elevateForPermissionPromptIfNeeded()
        lastEventItem.title = "Last event: [permissions] request initiated"
        refreshPermissionStatus(controller.currentPermissionSnapshot())
        shouldShowPermissionAlertOnNextSnapshot = true
        controller.requestSpeechAndMicrophonePermissions()

        let fallback = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard self.shouldShowPermissionAlertOnNextSnapshot else { return }
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
        return preferences.loadLanguageSelection() ?? config.localeIdentifier
    }

    private static func localeIdentifier(forSelection selection: String) -> String {
        if selection == AppPreferences.systemLanguageToken {
            return Locale.autoupdatingCurrent.identifier
        }
        return selection
    }
}
