#if os(macOS)
import AppKit
import Foundation

@MainActor
final class VoiceHoldKeyMonitor {
    private var localKeyDownMonitor: Any?
    private var localKeyUpMonitor: Any?
    private var globalKeyDownMonitor: Any?
    private var globalKeyUpMonitor: Any?
    private var isPressed = false
    private var configuration = HotKeyConfiguration.defaultVoice
    private var pressedAction: () -> Void = {}
    private var releasedAction: () -> Void = {}

    func register(
        configuration: HotKeyConfiguration,
        pressed: @escaping () -> Void,
        released: @escaping () -> Void
    ) {
        unregister()
        self.configuration = configuration
        self.pressedAction = pressed
        self.releasedAction = released

        localKeyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            self?.handle(event: event, isKeyDown: true)
            return event
        }
        localKeyUpMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyUp]) { [weak self] event in
            self?.handle(event: event, isKeyDown: false)
            return event
        }
        globalKeyDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            Task { @MainActor in
                self?.handle(event: event, isKeyDown: true)
            }
        }
        globalKeyUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyUp]) { [weak self] event in
            Task { @MainActor in
                self?.handle(event: event, isKeyDown: false)
            }
        }

        VoiceDiagnosticLog.write("voiceHoldMonitorRegistered key=\(configuration.displayString)")
    }

    func unregister() {
        for monitor in [localKeyDownMonitor, localKeyUpMonitor, globalKeyDownMonitor, globalKeyUpMonitor].compactMap({ $0 }) {
            NSEvent.removeMonitor(monitor)
        }
        localKeyDownMonitor = nil
        localKeyUpMonitor = nil
        globalKeyDownMonitor = nil
        globalKeyUpMonitor = nil
        isPressed = false
    }

    private func handle(event: NSEvent, isKeyDown: Bool) {
        if isKeyDown {
            guard !isPressed, configuration.matches(event: event) else {
                return
            }
            isPressed = true
            VoiceDiagnosticLog.write("voiceHoldPressed")
            pressedAction()
            return
        }

        guard isPressed, UInt32(event.keyCode) == configuration.keyCode else {
            return
        }
        isPressed = false
        VoiceDiagnosticLog.write("voiceHoldReleased")
        releasedAction()
    }
}
#endif
