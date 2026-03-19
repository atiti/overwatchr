#if os(macOS)
import ApplicationServices
import AppKit
import Foundation
import OverwatchrCore

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var alerts: [AgentEvent] = []
    @Published var lastErrorMessage: String?
    @Published private(set) var accessibilityTrusted = AXIsProcessTrusted()
    @Published private(set) var lastUpdatedAt = Date()

    let store: EventStore

    private let focusEngine = FocusEngine()
    private let hotKeyMonitor = GlobalHotKeyMonitor()
    private var hasStarted = false
    private lazy var watcher = EventWatcher(store: store) { [weak self] update in
        self?.alerts = update.currentAlerts
        self?.lastUpdatedAt = Date()
    }

    init(store: EventStore = EventStore()) {
        self.store = store
        start()
    }

    var alertCount: Int {
        alerts.count
    }

    func start() {
        guard !hasStarted else {
            return
        }
        hasStarted = true
        refreshAccessibilityStatus()
        watcher.start()

        do {
            try hotKeyMonitor.register { [weak self] in
                self?.focusNextAlert()
            }
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func focusNextAlert() {
        guard let alert = alerts.first else {
            return
        }

        focus(alert)
    }

    func focus(_ event: AgentEvent) {
        do {
            try focusEngine.focus(event: event)
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
            refreshAccessibilityStatus()
        }
    }

    func revealEventLog() {
        NSWorkspace.shared.activateFileViewerSelecting([store.fileURL])
    }

    func openAccessibilitySettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    func copyCLIExample() {
        let example = """
        overwatchr alert --agent copy --project landing --terminal ghostty --title "landing:copy"
        """

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(example, forType: .string)
    }

    private func refreshAccessibilityStatus() {
        accessibilityTrusted = AXIsProcessTrusted()
    }
}
#endif
