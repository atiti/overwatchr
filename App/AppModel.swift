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
    @Published private(set) var voiceEnabled = false
    @Published private(set) var voiceHotKeyConfiguration = HotKeyConfiguration.defaultVoice
    @Published private(set) var azureSpeechRegion = ""
    @Published private(set) var azureSpeechEndpoint = ""
    @Published private(set) var azureSpeechLanguage = "en-US"
    @Published private(set) var voiceSubmitMode: VoiceSubmitMode = .stripAndSubmit
    @Published private(set) var azureSpeechKeyConfigured = false
    @Published private(set) var voiceState: VoiceInteractionDisplayState = .idle
    @Published private(set) var shellIntegrationStatus: ShellIntegrationStatus?
    @Published var launchAtLoginMessage: String?
    @Published var hotKeyMessage: String?
    @Published var voiceMessage: String?

    let store: EventStore

    private var preferences: AppPreferences
    private let seenStore: SeenAlertStore
    private let focusEngine = FocusEngine()
    private let hotKeyMonitor = GlobalHotKeyMonitor(id: 1)
    private let voiceCarbonHotKeyMonitor = GlobalHotKeyMonitor(id: 2)
    private let voiceHotKeyMonitor = VoiceHoldKeyMonitor()
    private let shellIntegrationInstaller = ShellIntegrationInstaller()
    private let voiceKeychainStore = VoiceKeychainStore()
    private let azureSpeechKeyAccount = "azureSpeechKey"
    private var hasStarted = false
    private var currentAlerts: [AgentEvent] = []
    private var seenLedger: SeenAlertLedger
    private var temporarilySkippedAgentIDs: Set<String> = []
    private lazy var watcher = EventWatcher(store: store) { [weak self] update in
        self?.applyAlertUpdate(update.currentAlerts, newEvents: update.newEvents)
    }
    private lazy var voiceController = VoiceInteractionController(
        configurationProvider: { [weak self] in
            guard let self else {
                throw AzureSpeechProviderError.missingKey
            }
            return try self.azureSpeechProviderConfiguration()
        },
        submitModeProvider: { [weak self] in
            self?.voiceSubmitMode ?? .stripAndSubmit
        }
    )

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
        self.voiceEnabled = preferences.voiceEnabled
        self.voiceHotKeyConfiguration = preferences.voiceHotKeyConfiguration
        self.azureSpeechRegion = preferences.azureSpeechRegion
        self.azureSpeechEndpoint = preferences.azureSpeechEndpoint
        self.azureSpeechLanguage = preferences.azureSpeechLanguage
        self.voiceSubmitMode = preferences.voiceSubmitMode
        self.azureSpeechKeyConfigured = voiceKeychainStore.exists(account: azureSpeechKeyAccount)
        self.voiceController.onStateChange = { [weak self] state, message in
            self?.voiceState = state
            self?.voiceMessage = message
        }
        VoiceDiagnosticLog.write("appModelInit")
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
        registerVoiceHotKey()
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

    func openMicrophoneSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
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

    func setVoiceHotKeyConfiguration(_ configuration: HotKeyConfiguration) {
        voiceHotKeyConfiguration = configuration
        preferences.voiceHotKeyConfiguration = configuration
        registerVoiceHotKey()
    }

    func setVoiceEnabled(_ enabled: Bool) {
        voiceEnabled = enabled
        preferences.voiceEnabled = enabled
        if enabled {
            registerVoiceHotKey()
            voiceMessage = "Voice input enabled. Checking microphone access..."
            Task { @MainActor in
                let granted = await AudioCaptureService.requestMicrophoneAccess()
                VoiceDiagnosticLog.write("microphonePermissionRequested granted=\(granted)")
                guard voiceEnabled else {
                    return
                }
                voiceMessage = granted
                    ? "Voice input enabled."
                    : "Voice input enabled, but microphone access is denied."
            }
        } else {
            unregisterVoiceHotKey()
            voiceController.cancel()
            voiceMessage = "Voice input disabled."
        }
    }

    func resetVoiceHotKeyConfiguration() {
        setVoiceHotKeyConfiguration(.defaultVoice)
    }

    func setAzureSpeechRegion(_ value: String) {
        azureSpeechRegion = value
        preferences.azureSpeechRegion = value
    }

    func setAzureSpeechEndpoint(_ value: String) {
        azureSpeechEndpoint = value
        preferences.azureSpeechEndpoint = value
    }

    func setAzureSpeechLanguage(_ value: String) {
        azureSpeechLanguage = value
        preferences.azureSpeechLanguage = value
    }

    func setVoiceSubmitMode(_ mode: VoiceSubmitMode) {
        voiceSubmitMode = mode
        preferences.voiceSubmitMode = mode
    }

    func saveAzureSpeechKey(_ value: String) {
        do {
            try voiceKeychainStore.write(value, account: azureSpeechKeyAccount)
            azureSpeechKeyConfigured = !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            voiceMessage = azureSpeechKeyConfigured ? "Azure Speech key saved." : "Azure Speech key cleared."
        } catch {
            voiceMessage = error.localizedDescription
        }
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

    private func registerVoiceHotKey() {
        guard voiceEnabled else {
            unregisterVoiceHotKey()
            VoiceDiagnosticLog.write("voiceHotKeyDisabled")
            return
        }

        do {
            try voiceCarbonHotKeyMonitor.register(
                configuration: voiceHotKeyConfiguration,
                pressed: { [weak self] in
                    VoiceDiagnosticLog.write("voiceCarbonPressed")
                    self?.voiceController.beginCapture()
                },
                released: { [weak self] in
                    VoiceDiagnosticLog.write("voiceCarbonReleased")
                    self?.voiceController.finishCapture()
                }
            )
            VoiceDiagnosticLog.write("voiceCarbonHotKeyRegistered key=\(voiceHotKeyConfiguration.displayString)")
            voiceHotKeyMonitor.unregister()
        } catch {
            VoiceDiagnosticLog.write("voiceCarbonHotKeyRegistrationFailed error=\(error.localizedDescription)")
            voiceHotKeyMonitor.register(
                configuration: voiceHotKeyConfiguration,
                pressed: { [weak self] in
                    self?.voiceController.beginCapture()
                },
                released: { [weak self] in
                    self?.voiceController.finishCapture()
                }
            )
        }
    }

    private func unregisterVoiceHotKey() {
        voiceCarbonHotKeyMonitor.unregister()
        voiceHotKeyMonitor.unregister()
    }

    private func azureSpeechProviderConfiguration() throws -> AzureSpeechProviderConfiguration {
        let environment = ProcessInfo.processInfo.environment
        let key = try voiceKeychainStore.read(account: azureSpeechKeyAccount)
            ?? environment["AZURE_SPEECH_KEY"]
            ?? ""
        let region = azureSpeechRegion.nilIfBlank
            ?? environment["AZURE_SPEECH_REGION"]
            ?? ""
        let endpoint = azureSpeechEndpoint.nilIfBlank
            ?? environment["AZURE_SPEECH_ENDPOINT"]
        return AzureSpeechProviderConfiguration(
            key: key,
            region: region,
            endpoint: endpoint,
            language: azureSpeechLanguage.nilIfBlank ?? "en-US"
        )
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
        let incomingAttention = newEvents.filter(\.status.requiresAttention)
        autoAcknowledgeFrontmostAttention(incomingAttention)

        alerts = seenLedger.visibleAlerts(from: currentAlerts)
        temporarilySkippedAgentIDs.formIntersection(Set(alerts.map(\.agentID)))
        lastUpdatedAt = Date()

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

    private func autoAcknowledgeFrontmostAttention(_ events: [AgentEvent]) {
        let matchingEvents = events.filter { event in
            guard let terminal = event.terminal,
                  let context = focusEngine.frontmostContext(for: terminal) else {
                return false
            }
            return FrontmostSessionMatcher.matches(event: event, context: context)
        }

        guard !matchingEvents.isEmpty else {
            return
        }

        seenLedger.markSeen(matchingEvents)
        saveSeenLedger(or: "Auto-acknowledged the frontmost alert, but could not save seen-state")
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

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
#endif
