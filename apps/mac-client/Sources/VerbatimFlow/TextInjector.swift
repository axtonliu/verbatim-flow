import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

@MainActor
final class TextInjector {
    private var restoreClipboardWorkItem: DispatchWorkItem?

    func promptAccessibilityIfNeeded() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    func insert(text: String) throws {
        guard !text.isEmpty else {
            return
        }

        restoreClipboardWorkItem?.cancel()

        let pasteboard = NSPasteboard.general
        let previousString = pasteboard.string(forType: .string)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        try postCommandV()

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

    func undoLastInsert() throws {
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
}
