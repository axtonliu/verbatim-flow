import AppKit
import Carbon.HIToolbox
import Foundation

final class HotkeyMonitor {
    private let hotkey: Hotkey
    private let onPressed: () -> Void
    private let onReleased: () -> Void

    private var keyDownMonitor: Any?
    private var keyUpMonitor: Any?
    private var flagsChangedMonitor: Any?
    private var eventHandlerRef: EventHandlerRef?
    private var hotKeyRef: EventHotKeyRef?
    private let hotKeyID = EventHotKeyID(signature: OSType(0x56464B59), id: 1) // "VFKY"
    private var isPressed = false

    init(hotkey: Hotkey, onPressed: @escaping () -> Void, onReleased: @escaping () -> Void) {
        self.hotkey = hotkey
        self.onPressed = onPressed
        self.onReleased = onReleased
    }

    func start() {
        RuntimeLogger.log("[hotkey-monitor] start combo=\(hotkey.display) keyCode=\(String(describing: hotkey.keyCode))")

        if let keyCode = hotkey.keyCode, installCarbonHotkey(keyCode: keyCode) {
            RuntimeLogger.log("[hotkey-monitor] using carbon hotkey for \(hotkey.display)")
            return
        }

        RuntimeLogger.log("[hotkey-monitor] fallback to NSEvent global monitors for \(hotkey.display)")
        installEventMonitors()
    }

    deinit {
        uninstallCarbonHotkey()
        uninstallEventMonitors()
    }

    private func installEventMonitors() {
        RuntimeLogger.log("[hotkey-monitor] installEventMonitors")
        keyDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            self?.handleKeyDown(event)
        }

        keyUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyUp]) { [weak self] event in
            self?.handleKeyUp(event)
        }

        flagsChangedMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged]) { [weak self] event in
            self?.handleFlagsChanged(event)
        }
    }

    private func uninstallEventMonitors() {
        if let keyDownMonitor {
            NSEvent.removeMonitor(keyDownMonitor)
            self.keyDownMonitor = nil
        }
        if let keyUpMonitor {
            NSEvent.removeMonitor(keyUpMonitor)
            self.keyUpMonitor = nil
        }
        if let flagsChangedMonitor {
            NSEvent.removeMonitor(flagsChangedMonitor)
            self.flagsChangedMonitor = nil
        }
    }

    private func handleKeyDown(_ event: NSEvent) {
        guard let keyCode = hotkey.keyCode else {
            return
        }

        guard event.keyCode == keyCode else {
            return
        }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.isSuperset(of: hotkey.modifiers) else {
            return
        }

        guard !isPressed else {
            return
        }
        isPressed = true
        RuntimeLogger.log("[hotkey-monitor] NSEvent keyDown matched keyCode=\(event.keyCode)")
        onPressed()
    }

    private func handleKeyUp(_ event: NSEvent) {
        guard let keyCode = hotkey.keyCode else {
            return
        }

        guard event.keyCode == keyCode else {
            return
        }

        guard isPressed else {
            return
        }
        isPressed = false
        RuntimeLogger.log("[hotkey-monitor] NSEvent keyUp matched keyCode=\(event.keyCode)")
        onReleased()
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        guard hotkey.keyCode == nil else {
            return
        }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let requiredDown = flags.isSuperset(of: hotkey.modifiers)

        if requiredDown && !isPressed {
            isPressed = true
            RuntimeLogger.log("[hotkey-monitor] NSEvent flagsChanged pressed")
            onPressed()
            return
        }

        if !requiredDown && isPressed {
            isPressed = false
            RuntimeLogger.log("[hotkey-monitor] NSEvent flagsChanged released")
            onReleased()
        }
    }

    private func installCarbonHotkey(keyCode: UInt16) -> Bool {
        var eventTypes = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyReleased))
        ]

        let userData = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        let installStatus = InstallEventHandler(
            GetEventDispatcherTarget(),
            Self.hotKeyEventHandler,
            2,
            &eventTypes,
            userData,
            &eventHandlerRef
        )
        guard installStatus == noErr else {
            RuntimeLogger.log("[hotkey-monitor] InstallEventHandler failed status=\(installStatus)")
            return false
        }

        let registerStatus = RegisterEventHotKey(
            UInt32(keyCode),
            carbonModifiers(from: hotkey.modifiers),
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )
        if registerStatus != noErr {
            RuntimeLogger.log("[hotkey-monitor] RegisterEventHotKey failed status=\(registerStatus)")
            uninstallCarbonHotkey()
            return false
        }

        RuntimeLogger.log("[hotkey-monitor] RegisterEventHotKey ok keyCode=\(keyCode) modifiers=\(carbonModifiers(from: hotkey.modifiers))")

        return true
    }

    private func uninstallCarbonHotkey() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
    }

    private func handleCarbonEvent(_ eventRef: EventRef) -> OSStatus {
        guard hotKeyRef != nil else {
            return noErr
        }

        var incomingHotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            eventRef,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &incomingHotKeyID
        )
        guard status == noErr else {
            return status
        }

        guard incomingHotKeyID.signature == hotKeyID.signature, incomingHotKeyID.id == hotKeyID.id else {
            return noErr
        }

        let kind = GetEventKind(eventRef)
        if kind == UInt32(kEventHotKeyPressed) {
            guard !isPressed else { return noErr }
            isPressed = true
            RuntimeLogger.log("[hotkey-monitor] carbon pressed")
            onPressed()
            return noErr
        }

        if kind == UInt32(kEventHotKeyReleased) {
            guard isPressed else { return noErr }
            isPressed = false
            RuntimeLogger.log("[hotkey-monitor] carbon released")
            onReleased()
            return noErr
        }

        return noErr
    }

    private func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var modifiers: UInt32 = 0
        if flags.contains(.command) {
            modifiers |= UInt32(cmdKey)
        }
        if flags.contains(.option) {
            modifiers |= UInt32(optionKey)
        }
        if flags.contains(.control) {
            modifiers |= UInt32(controlKey)
        }
        if flags.contains(.shift) {
            modifiers |= UInt32(shiftKey)
        }
        return modifiers
    }

    private static let hotKeyEventHandler: EventHandlerUPP = { _, eventRef, userData in
        guard let eventRef, let userData else {
            return noErr
        }
        let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(userData).takeUnretainedValue()
        return monitor.handleCarbonEvent(eventRef)
    }
}
