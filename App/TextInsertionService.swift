#if os(macOS)
import AppKit
import ApplicationServices
import Carbon
import Foundation

enum TextInsertionError: Error, LocalizedError {
    case accessibilityPermissionRequired
    case eventCreationFailed

    var errorDescription: String? {
        switch self {
        case .accessibilityPermissionRequired:
            return "Accessibility access is required to insert voice text."
        case .eventCreationFailed:
            return "Could not create keyboard events for text insertion."
        }
    }
}

struct TextInsertionService {
    @MainActor
    func insert(_ text: String, submit: Bool) async throws {
        let trusted = AXIsProcessTrusted()
        VoiceDiagnosticLog.write("accessibilityTrusted=\(trusted)")
        guard trusted else {
            promptForAccessibilityAccess()
            throw TextInsertionError.accessibilityPermissionRequired
        }

        let pasteboard = NSPasteboard.general
        let previousString = pasteboard.string(forType: .string)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        try postKey(UInt16(kVK_ANSI_V), flags: .maskCommand)
        try await Task.sleep(nanoseconds: 120_000_000)

        if submit {
            try postKey(UInt16(kVK_Return), flags: [])
        }

        if pasteboard.string(forType: .string) == text {
            pasteboard.clearContents()
            if let previousString {
                pasteboard.setString(previousString, forType: .string)
            }
        }
    }

    private func postKey(_ keyCode: UInt16, flags: CGEventFlags) throws {
        guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false) else {
            throw TextInsertionError.eventCreationFailed
        }

        keyDown.flags = flags
        keyUp.flags = flags
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }

    private func promptForAccessibilityAccess() {
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
}
#endif
