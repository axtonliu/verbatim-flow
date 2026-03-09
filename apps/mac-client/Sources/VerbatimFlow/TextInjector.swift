import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

@MainActor
final class TextInjector {
    struct InsertionTarget {
        let processIdentifier: pid_t
        let bundleIdentifier: String?
        let localizedName: String?
    }

    private var restoreClipboardWorkItem: DispatchWorkItem?

    func isAccessibilityTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    func promptAccessibilityIfNeeded() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    func insert(text: String, preferredTarget: InsertionTarget? = nil) throws {
        guard !text.isEmpty else {
            return
        }

        guard isAccessibilityTrusted() else {
            _ = promptAccessibilityIfNeeded()
            RuntimeLogger.log("[insert] aborted: accessibility is not trusted")
            throw AppError.accessibilityPermissionRequired
        }

        if let preferredTarget {
            focusPreferredTargetIfNeeded(preferredTarget)
        }
        let frontmost = NSWorkspace.shared.frontmostApplication
        if let frontmost {
            RuntimeLogger.log(
                "[insert] frontmost pid=\(frontmost.processIdentifier) bundle=\(frontmost.bundleIdentifier ?? "-") name=\(frontmost.localizedName ?? "-")"
            )
        } else {
            RuntimeLogger.log("[insert] frontmost application unavailable before insertion")
        }

        let frontmostBundleID = frontmost?.bundleIdentifier

        if shouldUseUnicodeTyping(frontmostBundleID) {
            try postUnicodeText(text)
            RuntimeLogger.log("[insert] via unicode typing")
            return
        }

        if shouldSkipAccessibilityInsertion(frontmostBundleID) {
            RuntimeLogger.log("[insert] skip accessibility selected text for bundle=\(frontmostBundleID ?? "-")")
        } else {
            if tryInsertViaAccessibility(text: text) {
                RuntimeLogger.log("[insert] via accessibility selected text")
                return
            }
        }

        restoreClipboardWorkItem?.cancel()

        let pasteboard = NSPasteboard.general
        let previousString = pasteboard.string(forType: .string)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        try postCommandV()
        RuntimeLogger.log("[insert] via command+v paste fallback")

        // Restore previous clipboard text shortly after paste to reduce clipboard side effects.
        let workItem = DispatchWorkItem {
            pasteboard.clearContents()
            if let previousString {
                pasteboard.setString(previousString, forType: .string)
            }
        }
        restoreClipboardWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: workItem)
    }

    func copyToClipboard(text: String) {
        restoreClipboardWorkItem?.cancel()

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    func undoLastInsert(preferredTarget: InsertionTarget? = nil) throws {
        if let preferredTarget {
            focusPreferredTargetIfNeeded(preferredTarget)
        }
        try postCommandZ()
    }

    private func postCommandV() throws {
        try postCommandKey(vKeyCode: 9) // key 'v' in ANSI layout
    }

    private func postCommandZ() throws {
        try postCommandKey(vKeyCode: 6) // key 'z' in ANSI layout
    }

    private func postCommandKey(vKeyCode: CGKeyCode) throws {
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            throw AppError.eventSourceCreationFailed
        }

        guard
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true),
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false)
        else {
            throw AppError.eventCreationFailed
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }

    private func postUnicodeText(_ text: String) throws {
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            throw AppError.eventSourceCreationFailed
        }

        for character in text {
            let chunk = String(character)
            let utf16 = Array(chunk.utf16)

            guard
                let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
            else {
                throw AppError.eventCreationFailed
            }

            utf16.withUnsafeBufferPointer { buffer in
                guard let baseAddress = buffer.baseAddress else { return }
                keyDown.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: baseAddress)
                keyUp.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: baseAddress)
            }

            keyDown.post(tap: .cghidEventTap)
            keyUp.post(tap: .cghidEventTap)
        }
    }

    private func tryInsertViaAccessibility(text: String) -> Bool {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedValue: CFTypeRef?
        let focusedStatus = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedValue
        )
        guard focusedStatus == .success, let focusedValue else {
            RuntimeLogger.log("[insert] accessibility focused element unavailable status=\(focusedStatus.rawValue)")
            return false
        }
        guard CFGetTypeID(focusedValue) == AXUIElementGetTypeID() else {
            RuntimeLogger.log("[insert] focused element type mismatch")
            return false
        }

        let focusedElement = unsafeBitCast(focusedValue, to: AXUIElement.self)
        let setStatus = AXUIElementSetAttributeValue(
            focusedElement,
            kAXSelectedTextAttribute as CFString,
            text as CFString
        )
        if setStatus == .success {
            return true
        }

        RuntimeLogger.log("[insert] accessibility selected text failed status=\(setStatus.rawValue)")
        return false
    }

    private func focusPreferredTargetIfNeeded(_ target: InsertionTarget) {
        let currentFrontmost = NSWorkspace.shared.frontmostApplication
        if currentFrontmost?.processIdentifier == target.processIdentifier {
            return
        }

        let targetApp = NSRunningApplication(processIdentifier: target.processIdentifier)
        let didActivate = targetApp?.activate(options: [.activateIgnoringOtherApps]) ?? false
        RuntimeLogger.log(
            "[insert] activate target pid=\(target.processIdentifier) bundle=\(target.bundleIdentifier ?? "-") name=\(target.localizedName ?? "-") activated=\(didActivate)"
        )

        let deadline = Date().addingTimeInterval(0.4)
        while Date() < deadline {
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier {
                return
            }
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }

        let finalPid = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? -1
        RuntimeLogger.log("[insert] target app not frontmost after activation wait currentPid=\(finalPid)")
    }

    private func isTerminalLike(_ bundleIdentifier: String?) -> Bool {
        guard let bundleIdentifier else {
            return false
        }

        return bundleIdentifier == "com.apple.Terminal"
            || bundleIdentifier == "com.googlecode.iterm2"
            || bundleIdentifier == "com.mitchellh.ghostty"
            || bundleIdentifier.hasSuffix(".ghostty")
    }

    private func shouldUseUnicodeTyping(_ bundleIdentifier: String?) -> Bool {
        guard let bundleIdentifier else {
            return false
        }

        if isTerminalLike(bundleIdentifier) {
            return true
        }

        // Codex chat input can report AX success without visible text mutation.
        // Unicode event typing is more deterministic there than AX/paste fallback.
        return bundleIdentifier == "com.openai.codex" || bundleIdentifier.hasPrefix("com.openai.codex.")
    }

    private func shouldSkipAccessibilityInsertion(_ bundleIdentifier: String?) -> Bool {
        guard let bundleIdentifier else {
            return false
        }

        // Some apps can report AX selected-text success without visible mutation.
        // Prefer paste fallback for deterministic insertion there.
        return bundleIdentifier == "com.apple.MobileSMS"
            || isWeChatLike(bundleIdentifier)
            || isBrowserLike(bundleIdentifier)
    }

    private func isWeChatLike(_ bundleIdentifier: String) -> Bool {
        switch bundleIdentifier {
        case "com.tencent.xinWeChat", "com.tencent.WeChat":
            return true
        default:
            return false
        }
    }

    private func isBrowserLike(_ bundleIdentifier: String) -> Bool {
        if bundleIdentifier.hasPrefix("com.google.Chrome.app.") {
            return true
        }

        switch bundleIdentifier {
        case "com.apple.Safari",
             "com.google.Chrome",
             "com.google.Chrome.canary",
             "com.brave.Browser",
             "com.microsoft.edgemac",
             "org.mozilla.firefox",
             "com.operasoftware.Opera",
             "com.vivaldi.Vivaldi",
             "company.thebrowser.Browser", // Arc
             "company.thebrowser.dia", // Dia
             "com.kagi.kagimacOS": // Orion
            return true
        default:
            return false
        }
    }
}
