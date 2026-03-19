#if os(macOS)
import ApplicationServices
import AppKit
import Foundation
import OverwatchrCore
import ServiceManagement

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var alerts: [AgentEvent] = []
    @Published var lastErrorMessage: String?
    @Published private(set) var accessibilityTrusted = AXIsProcessTrusted()
    @Published private(set) var lastUpdatedAt = Date()
    @Published private(set) var launchAtLoginEnabled = false
    @Published private(set) var alertChimeEnabled = false
    @Published private(set) var jumpSoundEnabled = true
    @Published var launchAtLoginMessage: String?

    let store: EventStore

    private var preferences: AppPreferences
    private let seenStore: SeenAlertStore
    private let focusEngine = FocusEngine()
    private let hotKeyMonitor = GlobalHotKeyMonitor()
    private var hasStarted = false
    private var currentAlerts: [AgentEvent] = []
    private var seenLedger: SeenAlertLedger
    private lazy var watcher = EventWatcher(store: store) { [weak self] update in
        self?.applyAlertUpdate(update.currentAlerts, newEvents: update.newEvents)
    }

    init(
        store: EventStore = EventStore(),
        seenStore: SeenAlertStore = SeenAlertStore(),
        preferences: AppPreferences = AppPreferences()
    ) {
        self.store = store
        self.seenStore = seenStore
        self.preferences = preferences
        self.seenLedger = (try? seenStore.load()) ?? SeenAlertLedger()
        self.alertChimeEnabled = preferences.alertChimeEnabled
        self.jumpSoundEnabled = preferences.jumpSoundEnabled
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
        refreshLaunchAtLoginStatus()
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
        refreshAccessibilityStatus()
        let pendingAlerts = alerts
        guard !pendingAlerts.isEmpty else {
            return
        }

        var skippedCount = 0
        var lastError: String?

        for alert in pendingAlerts {
            do {
                try focusEngine.focus(event: alert)
                markSeen(alert)
                playJumpSoundIfEnabled()
                refreshAccessibilityStatus()
                lastErrorMessage = skippedCount == 0 ? nil : "Skipped \(skippedCount) stale alert\(skippedCount == 1 ? "" : "s") before jumping."
                return
            } catch {
                markSeen(alert)
                skippedCount += 1
                lastError = error.localizedDescription
            }
        }

        refreshAccessibilityStatus()
        if let lastError {
            lastErrorMessage = "Skipped \(skippedCount) alert\(skippedCount == 1 ? "" : "s"), but none could be focused. Last issue: \(lastError)"
        }
    }

    func focus(_ event: AgentEvent) {
        refreshAccessibilityStatus()
        do {
            try focusEngine.focus(event: event)
            markSeen(event)
            playJumpSoundIfEnabled()
            refreshAccessibilityStatus()
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
            refreshAccessibilityStatus()
        }
    }

    func openAccessibilitySettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    func setLaunchAtLoginEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
                launchAtLoginMessage = "Overwatchr will try to launch when you log in."
            } else {
                try SMAppService.mainApp.unregister()
                launchAtLoginMessage = "Launch at login disabled."
            }
            refreshLaunchAtLoginStatus()
        } catch {
            launchAtLoginMessage = error.localizedDescription
            refreshLaunchAtLoginStatus()
        }
    }

    func setAlertChimeEnabled(_ enabled: Bool) {
        alertChimeEnabled = enabled
        preferences.alertChimeEnabled = enabled
    }

    func setJumpSoundEnabled(_ enabled: Bool) {
        jumpSoundEnabled = enabled
        preferences.jumpSoundEnabled = enabled
    }

    func quit() {
        NSApp.terminate(nil)
    }

    private func refreshAccessibilityStatus() {
        accessibilityTrusted = AXIsProcessTrusted()
    }

    private func refreshLaunchAtLoginStatus() {
        launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
    }

    private func applyAlertUpdate(_ currentAlerts: [AgentEvent], newEvents: [AgentEvent] = []) {
        refreshAccessibilityStatus()
        self.currentAlerts = currentAlerts
        alerts = seenLedger.visibleAlerts(from: currentAlerts)
        lastUpdatedAt = Date()

        let incomingAttention = newEvents.filter(\.status.requiresAttention)
        let unseenIncomingAttention = seenLedger.visibleAlerts(from: incomingAttention)
        if alertChimeEnabled, !unseenIncomingAttention.isEmpty {
            NSSound(named: NSSound.Name("Glass"))?.play()
        }
    }

    private func markSeen(_ event: AgentEvent) {
        seenLedger.markSeen(event)
        alerts = seenLedger.visibleAlerts(from: currentAlerts)

        do {
            try seenStore.save(seenLedger)
        } catch {
            lastErrorMessage = "Focused the alert, but could not save seen-state: \(error.localizedDescription)"
        }
    }

    private func playJumpSoundIfEnabled() {
        guard jumpSoundEnabled else {
            return
        }
        NSSound(named: NSSound.Name("Hero"))?.play()
    }
}
#endif
