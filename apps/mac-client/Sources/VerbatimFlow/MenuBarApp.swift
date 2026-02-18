import AppKit
import Foundation

@MainActor
final class MenuBarApp: NSObject, NSApplicationDelegate {
    private let config: CLIConfig
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
    private let lastEventItem = NSMenuItem(title: "Last event: -", action: nil, keyEquivalent: "")

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

    private lazy var quitItem = NSMenuItem(
        title: "Quit VerbatimFlow",
        action: #selector(quitApp),
        keyEquivalent: "q"
    )

    init(config: CLIConfig) {
        self.config = config
        self.hotkeyInfoItem = NSMenuItem(title: "Hotkey: \(config.hotkey.display)", action: nil, keyEquivalent: "")
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupMenu()
        bindControllerCallbacks()

        controller.start()
        refreshModeChecks()
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
        lastEventItem.isEnabled = false

        toggleMenuItem.target = self

        rawModeItem.target = self
        formatOnlyModeItem.target = self

        let modeSubmenu = NSMenu(title: "Mode")
        modeSubmenu.addItem(rawModeItem)
        modeSubmenu.addItem(formatOnlyModeItem)
        modeMenuItem.submenu = modeSubmenu

        openAccessibilityItem.target = self
        openMicItem.target = self

        quitItem.target = self

        menu.addItem(stateMenuItem)
        menu.addItem(lastEventItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(toggleMenuItem)
        menu.addItem(modeMenuItem)
        menu.addItem(hotkeyInfoItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(openAccessibilityItem)
        menu.addItem(openMicItem)
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
    }

    private func applyRuntimeState(_ state: RuntimeState) {
        switch state {
        case .stopped:
            stateMenuItem.title = "State: Stopped"
            toggleMenuItem.title = "Resume Hotkey"
        case .ready:
            stateMenuItem.title = "State: Ready"
            toggleMenuItem.title = "Pause Hotkey"
        case .recording:
            stateMenuItem.title = "State: Recording"
            toggleMenuItem.title = "Pause Hotkey"
        case .processing:
            stateMenuItem.title = "State: Processing"
            toggleMenuItem.title = "Pause Hotkey"
        }
    }

    private func refreshModeChecks() {
        rawModeItem.state = controller.currentMode == .raw ? .on : .off
        formatOnlyModeItem.state = controller.currentMode == .formatOnly ? .on : .off
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
        refreshModeChecks()
    }

    @objc
    private func setFormatOnlyMode() {
        controller.setMode(.formatOnly)
        refreshModeChecks()
    }

    @objc
    private func openAccessibilitySettings() {
        openSystemSettings(url: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    @objc
    private func openMicrophoneSettings() {
        openSystemSettings(url: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
    }

    private func openSystemSettings(url: String) {
        guard let target = URL(string: url) else { return }
        NSWorkspace.shared.open(target)
    }

    @objc
    private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
