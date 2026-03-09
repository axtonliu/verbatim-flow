import AppKit
import Carbon.HIToolbox
import Foundation

final class HotkeyMonitor {
    private let hotkey: Hotkey
    private let onPressed: () -> Bool
    private let onReleased: () -> Void
    private let releaseWatchdogInterval: TimeInterval = 0.12
    private let releaseWatchdogMismatchThreshold = 3

    private var keyDownMonitor: Any?
    private var keyUpMonitor: Any?
    private var flagsChangedMonitor: Any?
    private var eventHandlerRef: EventHandlerRef?
    private var hotKeyRef: EventHotKeyRef?
    private var retainedSelfForCarbonHandler: Unmanaged<HotkeyMonitor>?
    private static var nextID: UInt32 = 1
    private let hotKeyID: EventHotKeyID
    private var isPressed = false
    private var releaseWatchdog: DispatchSourceTimer?
    private var releaseWatchdogMismatchCount = 0

    init(hotkey: Hotkey, onPressed: @escaping () -> Bool, onReleased: @escaping () -> Void) {
        let id = Self.nextID
        Self.nextID += 1
        self.hotKeyID = EventHotKeyID(signature: OSType(0x56464B59), id: id) // "VFKY"
        self.hotkey = hotkey
        self.onPressed = onPressed
        self.onReleased = onReleased
    }

    func start() {
        RuntimeLogger.log("[hotkey-monitor] start combo=\(hotkey.display) keyCode=\(String(describing: hotkey.keyCode))")
        stopReleaseWatchdog()

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
        stopReleaseWatchdog()
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

        transitionToPressed(source: "NSEvent keyDown keyCode=\(event.keyCode)")
    }

    private func handleKeyUp(_ event: NSEvent) {
        guard let keyCode = hotkey.keyCode else {
            return
        }

        guard event.keyCode == keyCode else {
            return
        }

        transitionToReleased(source: "NSEvent keyUp keyCode=\(event.keyCode)")
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        guard hotkey.keyCode == nil else {
            return
        }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let requiredDown = flags.isSuperset(of: hotkey.modifiers)

        if requiredDown {
            transitionToPressed(source: "NSEvent flagsChanged")
        } else {
            transitionToReleased(source: "NSEvent flagsChanged")
        }
    }

    private func installCarbonHotkey(keyCode: UInt16) -> Bool {
        var eventTypes = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyReleased))
        ]

        if retainedSelfForCarbonHandler == nil {
            retainedSelfForCarbonHandler = Unmanaged.passRetained(self)
        }
        let userData = UnsafeMutableRawPointer(retainedSelfForCarbonHandler!.toOpaque())
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
            releaseRetainedCarbonHandlerIfNeeded()
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
        releaseRetainedCarbonHandlerIfNeeded()
    }

    private func releaseRetainedCarbonHandlerIfNeeded() {
        retainedSelfForCarbonHandler?.release()
        retainedSelfForCarbonHandler = nil
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
            return OSStatus(eventNotHandledErr)
        }

        let kind = GetEventKind(eventRef)
        if kind == UInt32(kEventHotKeyPressed) {
            transitionToPressed(source: "carbon")
            return noErr
        }

        if kind == UInt32(kEventHotKeyReleased) {
            transitionToReleased(source: "carbon")
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

    private func transitionToPressed(source: String) {
        guard !isPressed else {
            return
        }
        let accepted = onPressed()
        guard accepted else {
            RuntimeLogger.log("[hotkey-monitor] \(source) pressed ignored by consumer")
            return
        }

        isPressed = true
        releaseWatchdogMismatchCount = 0
        RuntimeLogger.log("[hotkey-monitor] \(source) pressed")
        startReleaseWatchdogIfNeeded()
    }

    private func transitionToReleased(source: String) {
        guard isPressed else {
            return
        }
        isPressed = false
        releaseWatchdogMismatchCount = 0
        RuntimeLogger.log("[hotkey-monitor] \(source) released")
        stopReleaseWatchdog()
        onReleased()
    }

    private func startReleaseWatchdogIfNeeded() {
        guard releaseWatchdog == nil else {
            return
        }
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + releaseWatchdogInterval, repeating: releaseWatchdogInterval)
        timer.setEventHandler { [weak self] in
            self?.runReleaseWatchdogTick()
        }
        releaseWatchdog = timer
        timer.resume()
    }

    private func stopReleaseWatchdog() {
        releaseWatchdog?.cancel()
        releaseWatchdog = nil
        releaseWatchdogMismatchCount = 0
    }

    private func runReleaseWatchdogTick() {
        guard isPressed else {
            stopReleaseWatchdog()
            return
        }

        let downByFlags = isHotkeyCurrentlyDownByFlags()
        let downByPhysical = isHotkeyCurrentlyDownByPhysicalState()

        if downByFlags == downByPhysical {
            releaseWatchdogMismatchCount = 0
            guard !downByFlags else {
                return
            }

            RuntimeLogger.log("[hotkey-monitor] watchdog forced release for \(hotkey.display) (flags=up physical=up)")
            transitionToReleased(source: "watchdog")
            return
        }

        releaseWatchdogMismatchCount += 1
        guard releaseWatchdogMismatchCount >= releaseWatchdogMismatchThreshold else {
            return
        }

        RuntimeLogger.log(
            "[hotkey-monitor] watchdog mismatch combo=\(hotkey.display) flagsDown=\(downByFlags) physicalDown=\(downByPhysical) ticks=\(releaseWatchdogMismatchCount)"
        )

        guard !downByPhysical else {
            // Physical state still reports pressed; keep listening and avoid log spam.
            releaseWatchdogMismatchCount = 0
            return
        }

        RuntimeLogger.log("[hotkey-monitor] watchdog forced release for \(hotkey.display) (physical-up override)")
        transitionToReleased(source: "watchdog-physical")
    }

    private func isHotkeyCurrentlyDownByFlags() -> Bool {
        let modifiers = currentModifierFlags()
        guard modifiers.isSuperset(of: hotkey.modifiers) else {
            return false
        }

        // When using Carbon hotkeys, skip the key code check — Carbon
        // consumes the key event so CGEventSource.keyState returns false
        // even while the key is physically held.  Carbon's own
        // kEventHotKeyReleased handles key-code release detection.
        guard hotKeyRef == nil, let keyCode = hotkey.keyCode else {
            return true
        }

        return CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(keyCode))
    }

    private func isHotkeyCurrentlyDownByPhysicalState() -> Bool {
        guard areRequiredModifiersPhysicallyDown() else {
            return false
        }

        // Same rationale as isHotkeyCurrentlyDownByFlags — skip key code
        // check for Carbon hotkeys.
        guard hotKeyRef == nil, let keyCode = hotkey.keyCode else {
            return true
        }

        return CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(keyCode))
    }

    private func areRequiredModifiersPhysicallyDown() -> Bool {
        if hotkey.modifiers.contains(.shift),
           !isAnyKeyDown([CGKeyCode(56), CGKeyCode(60)]) {
            return false
        }

        if hotkey.modifiers.contains(.control),
           !isAnyKeyDown([CGKeyCode(59), CGKeyCode(62)]) {
            return false
        }

        if hotkey.modifiers.contains(.option),
           !isAnyKeyDown([CGKeyCode(58), CGKeyCode(61)]) {
            return false
        }

        if hotkey.modifiers.contains(.command),
           !isAnyKeyDown([CGKeyCode(55), CGKeyCode(54)]) {
            return false
        }

        return true
    }

    private func isAnyKeyDown(_ keyCodes: [CGKeyCode]) -> Bool {
        for keyCode in keyCodes where CGEventSource.keyState(.combinedSessionState, key: keyCode) {
            return true
        }
        return false
    }

    private func currentModifierFlags() -> NSEvent.ModifierFlags {
        let cgFlags = CGEventSource.flagsState(.combinedSessionState)
        var flags: NSEvent.ModifierFlags = []

        if cgFlags.contains(.maskShift) {
            flags.insert(.shift)
        }
        if cgFlags.contains(.maskControl) {
            flags.insert(.control)
        }
        if cgFlags.contains(.maskAlternate) {
            flags.insert(.option)
        }
        if cgFlags.contains(.maskCommand) {
            flags.insert(.command)
        }

        return flags
    }
}
