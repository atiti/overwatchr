#if os(macOS)
import AppKit
import Carbon
import Foundation

struct HotKeyConfiguration: Codable, Equatable, Sendable {
    let keyCode: UInt32
    let modifiers: UInt32
    let keyLabel: String

    static let `default` = HotKeyConfiguration(
        keyCode: UInt32(kVK_ANSI_O),
        modifiers: UInt32(controlKey | optionKey | cmdKey),
        keyLabel: "O"
    )

    init(keyCode: UInt32, modifiers: UInt32, keyLabel: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.keyLabel = keyLabel.uppercased()
    }

    init?(event: NSEvent) {
        guard event.type == .keyDown else {
            return nil
        }

        let modifiers = Self.carbonModifiers(from: event.modifierFlags)
        guard modifiers != 0 else {
            return nil
        }

        let keyCode = UInt32(event.keyCode)
        guard let keyLabel = Self.keyLabel(for: event) else {
            return nil
        }

        self.init(keyCode: keyCode, modifiers: modifiers, keyLabel: keyLabel)
    }

    var displayString: String {
        "\(modifierSymbols)\(keyLabel)"
    }

    private var modifierSymbols: String {
        var symbols: [String] = []
        if modifiers & UInt32(controlKey) != 0 {
            symbols.append("⌃")
        }
        if modifiers & UInt32(optionKey) != 0 {
            symbols.append("⌥")
        }
        if modifiers & UInt32(shiftKey) != 0 {
            symbols.append("⇧")
        }
        if modifiers & UInt32(cmdKey) != 0 {
            symbols.append("⌘")
        }
        return symbols.joined()
    }

    private static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var modifiers: UInt32 = 0
        if flags.contains(.control) {
            modifiers |= UInt32(controlKey)
        }
        if flags.contains(.option) {
            modifiers |= UInt32(optionKey)
        }
        if flags.contains(.shift) {
            modifiers |= UInt32(shiftKey)
        }
        if flags.contains(.command) {
            modifiers |= UInt32(cmdKey)
        }
        return modifiers
    }

    private static func keyLabel(for event: NSEvent) -> String? {
        if let characters = event.charactersIgnoringModifiers?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !characters.isEmpty {
            return characters.uppercased()
        }

        switch Int(event.keyCode) {
        case kVK_Space:
            return "Space"
        case kVK_Return:
            return "Return"
        case kVK_Tab:
            return "Tab"
        case kVK_Delete:
            return "Delete"
        case kVK_Escape:
            return "Esc"
        case kVK_LeftArrow:
            return "←"
        case kVK_RightArrow:
            return "→"
        case kVK_UpArrow:
            return "↑"
        case kVK_DownArrow:
            return "↓"
        case kVK_F1...kVK_F20:
            return "F\(Int(event.keyCode) - Int(kVK_F1) + 1)"
        default:
            return nil
        }
    }
}
#endif
