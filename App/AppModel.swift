#if os(macOS)
import ApplicationServices
import AppKit
import Foundation
import OverwatchrCore
import ServiceManagement

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var alerts: [AgentEvent] = []
    @Published var feedbackMessage: String?
    @Published private(set) var accessibilityTrusted = AXIsProcessTrusted()
    @Published private(set) var lastUpdatedAt = Date()
    @Published private(set) var launchAtLoginEnabled = false
    @Published private(set) var alertChimeEnabled = false
    @Published private(set) var jumpSoundEnabled = true
    @Published private(set) var hotKeyConfiguration = HotKeyConfiguration.default
    @Published private(set) var shellIntegrationStatus: ShellIntegrationStatus?
    @Published var launchAtLoginMessage: String?
    @Published var hotKeyMessage: String?

    let store: EventStore

    private var preferences: AppPreferences
    private let seenStore: SeenAlertStore
    private let focusEngine = FocusEngine()
    private let hotKeyMonitor = GlobalHotKeyMonitor()
    private let shellIntegrationInstaller = ShellIntegrationInstaller()
    private var hasStarted = false
    private var currentAlerts: [AgentEvent] = []
    private var seenLedger: SeenAlertLedger
    private var temporarilySkippedAgentIDs: Set<String> = []
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
        self.hotKeyConfiguration = preferences.hotKeyConfiguration
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
        refreshShellIntegrationStatus()
        watcher.start()
        registerHotKey()
    }

    func focusNextAlert() {
        refreshAccessibilityStatus()
        guard !alerts.isEmpty else {
            return
        }

        var pendingAlerts = alerts.filter { !temporarilySkippedAgentIDs.contains($0.agentID) }
        if pendingAlerts.isEmpty {
            temporarilySkippedAgentIDs.removeAll()
            pendingAlerts = alerts
        }

        var skippedCount = 0
        var lastError: String?

        for alert in pendingAlerts {
            do {
                try focusEngine.focus(event: alert)
                temporarilySkippedAgentIDs.removeAll()
                markSeen(alert)
                playJumpSoundIfEnabled()
                refreshAccessibilityStatus()
                feedbackMessage = focusSuccessMessage(for: alert, skippedCount: skippedCount)
                return
            } catch {
                temporarilySkippedAgentIDs.insert(alert.agentID)
                skippedCount += 1
                lastError = error.localizedDescription
            }
        }

        refreshAccessibilityStatus()
        if let lastError {
            feedbackMessage = "Skipped \(skippedCount) alert\(skippedCount == 1 ? "" : "s"), but none could be focused. Last issue: \(lastError)"
        }
    }

    func focus(_ event: AgentEvent) {
        refreshAccessibilityStatus()
        do {
            try focusEngine.focus(event: event)
            markSeen(event)
            playJumpSoundIfEnabled()
            refreshAccessibilityStatus()
            feedbackMessage = focusSuccessMessage(for: event)
        } catch {
            feedbackMessage = error.localizedDescription
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

    func setHotKeyConfiguration(_ configuration: HotKeyConfiguration) {
        hotKeyConfiguration = configuration
        preferences.hotKeyConfiguration = configuration
        registerHotKey()
    }

    func resetHotKeyConfiguration() {
        setHotKeyConfiguration(.default)
    }

    func clearVisibleAlerts() {
        guard !alerts.isEmpty else {
            return
        }

        let clearedCount = alerts.count
        seenLedger.markSeen(alerts)
        alerts = seenLedger.visibleAlerts(from: currentAlerts)
        temporarilySkippedAgentIDs.removeAll()
        feedbackMessage = "Cleared \(clearedCount) alert\(clearedCount == 1 ? "" : "s") from the queue."

        do {
            try seenStore.save(seenLedger)
        } catch {
            feedbackMessage = "Cleared the queue, but could not save seen-state: \(error.localizedDescription)"
        }
    }

    func quit() {
        NSApp.terminate(nil)
    }

    private func refreshAccessibilityStatus() {
        accessibilityTrusted = AXIsProcessTrusted()
    }

    private func registerHotKey() {
        do {
            try hotKeyMonitor.register(configuration: hotKeyConfiguration) { [weak self] in
                self?.focusNextAlert()
            }
            hotKeyMessage = nil
        } catch {
            hotKeyMessage = error.localizedDescription
            feedbackMessage = error.localizedDescription
        }
    }

    private func refreshLaunchAtLoginStatus() {
        launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
    }

    private func refreshShellIntegrationStatus() {
        guard let shellPath = ProcessInfo.processInfo.environment["SHELL"],
              let shell = ShellProfile(shellPath: shellPath) else {
            shellIntegrationStatus = nil
            return
        }

        shellIntegrationStatus = shellIntegrationInstaller.status(for: shell)
    }

    private func applyAlertUpdate(_ currentAlerts: [AgentEvent], newEvents: [AgentEvent] = []) {
        refreshAccessibilityStatus()
        self.currentAlerts = currentAlerts
        alerts = seenLedger.visibleAlerts(from: currentAlerts)
        temporarilySkippedAgentIDs.formIntersection(Set(alerts.map(\.agentID)))
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
        saveSeenLedger(or: "Focused the alert, but could not save seen-state")
    }

    private func playJumpSoundIfEnabled() {
        guard jumpSoundEnabled else {
            return
        }
        NSSound(named: NSSound.Name("Hero"))?.play()
    }

    private func saveSeenLedger(or prefix: String) {
        do {
            try seenStore.save(seenLedger)
        } catch {
            feedbackMessage = "\(prefix): \(error.localizedDescription)"
        }
    }

    private func focusSuccessMessage(for event: AgentEvent, skippedCount: Int = 0) -> String {
        let target = event.project ?? event.title ?? event.agentID
        let suffix: String
        if alerts.isEmpty {
            suffix = " Queue clear."
        } else {
            suffix = " \(alerts.count) left."
        }

        if skippedCount > 0 {
            return "Jumped to \(target), marked it seen, and skipped \(skippedCount) stale alert\(skippedCount == 1 ? "" : "s").\(suffix)"
        }

        return "Jumped to \(target) and marked it seen.\(suffix)"
    }
}
#endif
