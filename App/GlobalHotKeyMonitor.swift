#if os(macOS)
import Carbon
import Foundation

enum HotKeyError: Error, LocalizedError {
    case registrationFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .registrationFailed(let status):
            return "Could not register the global shortcut (OSStatus \(status))."
        }
    }
}

@MainActor
final class GlobalHotKeyMonitor {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var action: () -> Void = {}

    func register(
        keyCode: UInt32 = UInt32(kVK_ANSI_A),
        modifiers: UInt32 = UInt32(cmdKey | shiftKey),
        handler: @escaping () -> Void
    ) throws {
        unregister()
        action = handler

        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let callback: EventHandlerUPP = { _, _, userData in
            guard let userData else {
                return noErr
            }

            let monitor = Unmanaged<GlobalHotKeyMonitor>
                .fromOpaque(userData)
                .takeUnretainedValue()
            monitor.action()
            return noErr
        }

        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            1,
            &eventSpec,
            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            &handlerRef
        )

        guard installStatus == noErr else {
            throw HotKeyError.registrationFailed(installStatus)
        }

        let hotKeyID = EventHotKeyID(signature: fourCharCode("OWHR"), id: 1)
        let registerStatus = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        guard registerStatus == noErr else {
            throw HotKeyError.registrationFailed(registerStatus)
        }
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }

        if let handlerRef {
            RemoveEventHandler(handlerRef)
            self.handlerRef = nil
        }
    }
    private func fourCharCode(_ string: String) -> FourCharCode {
        string.utf8.reduce(0) { partialResult, byte in
            (partialResult << 8) + FourCharCode(byte)
        }
    }
}
#endif
