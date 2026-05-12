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
    private var pressedAction: () -> Void = {}
    private var releasedAction: (() -> Void)?
    private let hotKeyID: EventHotKeyID

    init(id: UInt32) {
        self.hotKeyID = EventHotKeyID(signature: Self.fourCharCode("OWHR"), id: id)
    }

    func register(configuration: HotKeyConfiguration = .default, handler: @escaping () -> Void) throws {
        try register(configuration: configuration, pressed: handler, released: nil)
    }

    func register(
        configuration: HotKeyConfiguration = .default,
        pressed: @escaping () -> Void,
        released: (() -> Void)?
    ) throws {
        unregister()
        pressedAction = pressed
        releasedAction = released

        var eventSpecs = [
            EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyPressed)
            ),
            EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyReleased)
            )
        ]

        let callback: EventHandlerUPP = { _, event, userData in
            guard let userData else {
                return noErr
            }

            let monitor = Unmanaged<GlobalHotKeyMonitor>
                .fromOpaque(userData)
                .takeUnretainedValue()
            guard monitor.matches(event: event) else {
                return noErr
            }
            if let event, GetEventKind(event) == UInt32(kEventHotKeyReleased) {
                monitor.releasedAction?()
            } else {
                monitor.pressedAction()
            }
            return noErr
        }

        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            eventSpecs.count,
            &eventSpecs,
            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            &handlerRef
        )

        guard installStatus == noErr else {
            throw HotKeyError.registrationFailed(installStatus)
        }

        let registerStatus = RegisterEventHotKey(
            configuration.keyCode,
            configuration.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        guard registerStatus == noErr else {
            if let handlerRef {
                RemoveEventHandler(handlerRef)
                self.handlerRef = nil
            }
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

    private func matches(event: EventRef?) -> Bool {
        guard let event else {
            return false
        }

        var incomingID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &incomingID
        )

        guard status == noErr else {
            return false
        }
        return incomingID.signature == hotKeyID.signature && incomingID.id == hotKeyID.id
    }

    private static func fourCharCode(_ string: String) -> FourCharCode {
        string.utf8.reduce(0) { partialResult, byte in
            (partialResult << 8) + FourCharCode(byte)
        }
    }
}
#endif
