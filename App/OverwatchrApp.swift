#if os(macOS)
import AppKit
import Carbon
import OverwatchrCore
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !activateExistingInstanceIfNeeded() else {
            NSApp.terminate(nil)
            return
        }
        NSApp.setActivationPolicy(.accessory)
    }

    private func activateExistingInstanceIfNeeded() -> Bool {
        let currentProcessID = ProcessInfo.processInfo.processIdentifier
        let currentExecutablePath = Bundle.main.executableURL?.resolvingSymlinksInPath().path

        let runningPeers = NSWorkspace.shared.runningApplications.filter { app in
            guard app.processIdentifier != currentProcessID else {
                return false
            }

            let sameExecutable = app.executableURL?.resolvingSymlinksInPath().path == currentExecutablePath
            let sameName = app.localizedName == "overwatchr-app"
            return sameExecutable || sameName
        }

        guard let existing = runningPeers.first else {
            return false
        }

        existing.activate(options: [.activateIgnoringOtherApps])
        return true
    }
}

@main
struct OverwatchrMenuBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            StatusMenuView(model: appDelegate.model)
                .frame(width: 380)
        } label: {
            StatusItemLabel(alertCount: appDelegate.model.alertCount)
                .help(appDelegate.model.alertCount == 0 ? "overwatchr is watching quietly" : "overwatchr has \(appDelegate.model.alertCount) active alert(s)")
        }
        .menuBarExtraStyle(.window)
    }
}

private struct StatusMenuView: View {
    @ObservedObject var model: AppModel
    @State private var showingSettings = false
    @State private var appSettingsExpanded = true
    @State private var voiceSettingsExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if showingSettings {
                settingsContent
            } else {
                mainContent
            }
        }
        .padding(16)
        .background(
            LinearGradient(
                colors: [BrandPalette.background, BrandPalette.primary.opacity(0.95)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .frame(width: 380)
        .frame(height: showingSettings ? 620 : nil)
        .animation(.easeInOut(duration: 0.16), value: showingSettings)
    }

    private var mainContent: some View {
        Group {
            header
            queueCard
            footer
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            if let image = BrandAssets.logoImage() {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 42, height: 42)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("overwatchr")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text(model.alertCount == 0 ? "Quietly watching your agent swarm." : "Watching \(model.alertCount) ping\(model.alertCount == 1 ? "" : "s") that need your eyes.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.72))
            }
            Spacer()

            IconButton(systemImage: "gearshape.fill") {
                showingSettings = true
            }
        }
    }

    private var queueCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text(model.alertCount == 0 ? "Queue clear" : "\(model.alertCount) in queue")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.7))

                Spacer()

                if model.alertCount > 0 {
                    Button {
                        model.clearVisibleAlerts()
                    } label: {
                        Label("Clear", systemImage: "checkmark.circle")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.86))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(Color.white.opacity(0.08))
                            )
                    }
                    .buttonStyle(.plain)
                    .help("Mark all visible alerts as seen")
                }
            }

            if model.alerts.isEmpty {
                EmptyQueueCard()
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(spacing: 10) {
                        ForEach(model.alerts) { alert in
                            AlertRow(
                                alert: alert,
                                isNewest: alert.id == model.alerts.first?.id
                            ) {
                                model.focus(alert)
                            }
                            .accessibilityIdentifier("alert-\(alert.agentID)")
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(minHeight: 132, maxHeight: 300)
            }
        }
        .padding(14)
        .background(cardBackground)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let feedbackMessage = model.feedbackMessage {
                Text(feedbackMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.72))
                    .padding(.top, 2)
            }

            HStack {
                Text("Last refresh \(model.lastUpdatedAt.formatted(date: .omitted, time: .shortened))")
                Spacer()
                Text("\(AppVersion.displayString) · Jump: \(model.hotKeyConfiguration.displayString) · Voice: \(model.voiceHotKeyConfiguration.displayString)")
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Color.white.opacity(0.56))
        }
    }

    private var settingsContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                IconButton(systemImage: "chevron.left") {
                    showingSettings = false
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Settings")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("Small knobs for your control tower.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.68))
                }

                Spacer()
            }

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 10) {
                    CollapsibleSettingsSection(
                        title: "App",
                        subtitle: "Queue, launch, sounds, and permissions",
                        systemImage: "switch.2",
                        isExpanded: $appSettingsExpanded
                    ) {
                        appSettingsRows
                    }

                    CollapsibleSettingsSection(
                        title: "Voice",
                        subtitle: model.voiceEnabled ? "Hold-to-talk is enabled" : "Optional dictation support",
                        systemImage: model.voiceEnabled ? "mic.fill" : "mic.slash.fill",
                        isExpanded: $voiceSettingsExpanded
                    ) {
                        voiceSettingsRows
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(maxHeight: .infinity)

            if let launchAtLoginMessage = model.launchAtLoginMessage {
                Text(launchAtLoginMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.68))
            }

            if let hotKeyMessage = model.hotKeyMessage {
                Text(hotKeyMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.orange.opacity(0.88))
            }

            if let voiceMessage = model.voiceMessage {
                Text(voiceMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.68))
            }

            HStack {
                Button("Quit Overwatchr") {
                    model.quit()
                }
                .foregroundStyle(Color.white.opacity(0.86))
                .buttonStyle(.plain)

                Spacer()

                Text(AppVersion.displayString)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.46))
            }
        }
    }

    @ViewBuilder
    private var voiceSettingsRows: some View {
        SettingsRow(
            title: "Voice input",
            subtitle: "Enable hold-to-talk dictation."
        ) {
            Toggle("", isOn: Binding(
                get: { model.voiceEnabled },
                set: { model.setVoiceEnabled($0) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
        }

        SettingsRow(
            title: "Voice shortcut",
            subtitle: "Hold to dictate into the focused app."
        ) {
            ShortcutRecorder(
                configuration: model.voiceHotKeyConfiguration,
                onChange: { model.setVoiceHotKeyConfiguration($0) },
                onReset: { model.resetVoiceHotKeyConfiguration() }
            )
        }

        SettingsRow(
            title: "Azure Speech key",
            subtitle: model.azureSpeechKeyConfigured ? "Saved in Keychain." : "Required for voice transcription."
        ) {
            VoiceKeyField(onSave: { model.saveAzureSpeechKey($0) })
        }

        SettingsRow(
            title: "Azure region",
            subtitle: "Speech resource region, unless using a full endpoint."
        ) {
            VoiceTextField(
                placeholder: "eastus",
                text: Binding(
                    get: { model.azureSpeechRegion },
                    set: { model.setAzureSpeechRegion($0) }
                )
            )
        }

        SettingsRow(
            title: "Azure endpoint",
            subtitle: "Optional custom Speech endpoint."
        ) {
            VoiceTextField(
                placeholder: "https://...",
                text: Binding(
                    get: { model.azureSpeechEndpoint },
                    set: { model.setAzureSpeechEndpoint($0) }
                )
            )
        }

        SettingsRow(
            title: "Voice locales",
            subtitle: "One or more Azure locales, comma-separated for auto-pick."
        ) {
            VoiceTextField(
                placeholder: "en-US,hu-HU",
                text: Binding(
                    get: { model.azureSpeechLanguage },
                    set: { model.setAzureSpeechLanguage($0) }
                )
            )
        }

        SettingsRow(
            title: "Voice submit",
            subtitle: "Handle phrases like press enter."
        ) {
            VoiceSubmitModePicker(
                selection: Binding(
                    get: { model.voiceSubmitMode },
                    set: { model.setVoiceSubmitMode($0) }
                )
            )
        }

        SettingsRow(
            title: "Microphone",
            subtitle: "Needed when holding the voice shortcut."
        ) {
            Button("Open") {
                model.openMicrophoneSettings()
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.white)
        }
    }

    @ViewBuilder
    private var appSettingsRows: some View {
        SettingsRow(
            title: "Jump shortcut",
            subtitle: "Choose the global key combo that teleports you to the next ping."
        ) {
            ShortcutRecorder(
                configuration: model.hotKeyConfiguration,
                onChange: { model.setHotKeyConfiguration($0) },
                onReset: { model.resetHotKeyConfiguration() }
            )
        }

        if let shellStatus = model.shellIntegrationStatus {
            SettingsRow(
                title: "Shell title sync",
                subtitle: shellStatus.installed
                    ? "Installed for \(shellStatus.shell.rawValue). New terminal tabs will export OVERWATCHR_TITLE."
                    : "Not installed for \(shellStatus.shell.rawValue). Ghostty jumps work best with the managed shell snippet."
            ) {
                ShellStatusBadge(installed: shellStatus.installed)
            }
        }

        SettingsRow(
            title: "Launch at login",
            subtitle: "Start overwatchr automatically after you sign in."
        ) {
            Toggle("", isOn: Binding(
                get: { model.launchAtLoginEnabled },
                set: { model.setLaunchAtLoginEnabled($0) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
        }

        SettingsRow(
            title: "Alert chime",
            subtitle: "Play a small Glass chime when a fresh ping arrives."
        ) {
            Toggle("", isOn: Binding(
                get: { model.alertChimeEnabled },
                set: { model.setAlertChimeEnabled($0) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
        }

        SettingsRow(
            title: "Jump sound",
            subtitle: "Play a small hero sound when you teleport into the queue."
        ) {
            Toggle("", isOn: Binding(
                get: { model.jumpSoundEnabled },
                set: { model.setJumpSoundEnabled($0) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
        }

        SettingsRow(
            title: "Accessibility",
            subtitle: model.accessibilityTrusted ? "Window focusing and voice insertion permissions look good." : "Needed for reliable focusing and voice insertion."
        ) {
            Button("Open") {
                model.openAccessibilitySettings()
            }
            .buttonStyle(.borderless)
                .foregroundStyle(.white)
        }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(BrandPalette.card)
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(BrandPalette.border, lineWidth: 1)
            )
    }
}

private struct ShortcutRecorder: View {
    let configuration: HotKeyConfiguration
    let onChange: (HotKeyConfiguration) -> Void
    let onReset: () -> Void

    @State private var isRecording = false
    @State private var eventMonitor: Any?

    var body: some View {
        HStack(spacing: 8) {
            Button(isRecording ? "Press keys..." : configuration.displayString) {
                toggleRecording()
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.92))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                Capsule(style: .continuous)
                    .fill(isRecording ? Color.cyan.opacity(0.26) : Color.white.opacity(0.08))
            )

            Button("Reset") {
                stopRecording()
                onReset()
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.72))

            Spacer(minLength: 0)
        }
        .onDisappear {
            stopRecording()
        }
    }

    private func toggleRecording() {
        if isRecording {
            stopRecording()
            return
        }

        isRecording = true
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            if event.keyCode == UInt16(kVK_Escape) {
                stopRecording()
                return nil
            }

            guard let configuration = HotKeyConfiguration(event: event) else {
                return nil
            }

            onChange(configuration)
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
        isRecording = false
    }
}

private struct ShellStatusBadge: View {
    let installed: Bool

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(installed ? Color.green.opacity(0.9) : Color.orange.opacity(0.9))
                .frame(width: 7, height: 7)

            Text(installed ? "Installed" : "Missing")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.88))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.48))
                .padding(.horizontal, 2)

            VStack(alignment: .leading, spacing: 1) {
                content
            }
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.07))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
            )
        }
    }
}

private struct CollapsibleSettingsSection<Content: View>: View {
    let title: String
    let subtitle: String
    let systemImage: String
    @Binding var isExpanded: Bool
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.14)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: systemImage)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(BrandPalette.accent)
                        .frame(width: 26, height: 26)
                        .background(
                            Circle()
                                .fill(Color.white.opacity(0.08))
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        Text(subtitle)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.56))
                            .lineLimit(1)
                    }

                    Spacer()

                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.5))
                        .rotationEffect(.degrees(isExpanded ? 0 : -90))
                }
                .padding(12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider()
                    .overlay(Color.white.opacity(0.08))
                    .padding(.horizontal, 12)

                VStack(alignment: .leading, spacing: 1) {
                    content
                }
                .padding(.vertical, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }
}

private struct VoiceTextField: View {
    let placeholder: String
    @Binding var text: String

    var body: some View {
        TextField(placeholder, text: $text)
        .textFieldStyle(.plain)
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.white)
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.08))
            )
    }
}

private struct VoiceKeyField: View {
    let onSave: (String) -> Void
    @State private var key = ""

    var body: some View {
        HStack(spacing: 6) {
            SecureField("key", text: $key)
                .textFieldStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 9)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                )

            Button("Save") {
                onSave(key)
                key = ""
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.86))
        }
    }
}

private struct VoiceSubmitModePicker: View {
    @Binding var selection: VoiceSubmitMode

    var body: some View {
        Picker("", selection: $selection) {
            ForEach(VoiceSubmitMode.allCases, id: \.self) { mode in
                Text(label(for: mode)).tag(mode)
            }
        }
        .labelsHidden()
        .frame(maxWidth: .infinity)
    }

    private func label(for mode: VoiceSubmitMode) -> String {
        switch mode {
        case .disabled:
            return "Off"
        case .stripAndSubmit:
            return "Strip + enter"
        case .keepAndSubmit:
            return "Keep + enter"
        }
    }
}

private struct EmptyQueueCard: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "moon.stars.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.72))
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                )

            VStack(alignment: .leading, spacing: 3) {
                Text("Airspace clear")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                Text("When an agent needs input or hits an error, it will land here.")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.66))
            }

            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
    }
}

private struct AlertRow: View {
    let alert: AgentEvent
    let isNewest: Bool
    let action: () -> Void

    var body: some View {
        content
    }

    private var statusColor: Color {
        alert.status == .error ? Color.red.opacity(0.95) : BrandPalette.accent
    }

    private var terminalLabel: String {
        alert.terminal?.capitalized ?? "Terminal"
    }

    private var primaryTitle: String {
        alert.project ?? alert.title ?? alert.agentID
    }

    private var secondaryTitle: String? {
        if let title = alert.title, title != primaryTitle {
            return title
        }
        if let project = alert.project, project != primaryTitle {
            return project
        }
        if alert.agentID != primaryTitle {
            return alert.agentID
        }
        return nil
    }

    private var timestampLabel: String {
        Date(timeIntervalSince1970: alert.timestamp).formatted(.dateTime.hour().minute())
    }

    private var content: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(statusColor.opacity(0.18))
                .frame(width: 34, height: 34)
                .overlay {
                    Image(systemName: alert.status == .error ? "exclamationmark.triangle.fill" : "ellipsis.message.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(statusColor)
                }

            VStack(alignment: .leading, spacing: 6) {
                titleRow
                subtitleRow
                metadataRow
            }

            Spacer(minLength: 8)

            jumpButton
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
    }

    private var titleRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(primaryTitle)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(2)

            if isNewest {
                Text("NEW")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(BrandPalette.accent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        Capsule(style: .continuous)
                            .fill(BrandPalette.accent.opacity(0.14))
                    )
            }

            Spacer(minLength: 6)

            Text(alert.status.label.uppercased())
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(statusColor)
        }
    }

    private var subtitleRow: some View {
        Group {
            if let secondaryTitle {
                Text(secondaryTitle)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.white.opacity(0.74))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    private var metadataRow: some View {
        HStack(spacing: 10) {
            Label(terminalLabel, systemImage: "terminal")
            if let tty = alert.tty {
                Text(tty)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Text(timestampLabel)
            Spacer(minLength: 0)
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(Color.white.opacity(0.5))
    }

    private var jumpButton: some View {
        Button(action: action) {
            Image(systemName: "arrow.up.forward.app.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(BrandPalette.accent.opacity(0.22))
                )
        }
        .buttonStyle(.plain)
        .help("Jump to this terminal")
    }
}

private struct StatusItemLabel: View {
    let alertCount: Int

    var body: some View {
        HStack(spacing: 5) {
            if let image = BrandAssets.toolbarIconImage() {
                Image(nsImage: image)
                    .renderingMode(.original)
                    .interpolation(.high)
                    .frame(width: 18, height: 14)
            }

            if alertCount > 0 {
                Text("\(alertCount)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
            }
        }
        .accessibilityLabel("overwatchr \(alertCount) active alerts")
    }
}

private struct IconButton: View {
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(
                    Circle()
                        .fill(Color.white.opacity(0.08))
                )
        }
        .buttonStyle(.plain)
    }
}

private struct SettingsRow<Accessory: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let accessory: Accessory

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.66))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            accessory
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
    }
}

private struct SettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                if let image = BrandAssets.logoImage() {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("Overwatchr Settings")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                    Text("Tiny controls for your terminal control tower.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }

            Toggle(isOn: Binding(
                get: { model.launchAtLoginEnabled },
                set: { model.setLaunchAtLoginEnabled($0) }
            )) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Launch at login")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Start overwatchr automatically after you sign in.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)

            VStack(alignment: .leading, spacing: 8) {
                Label(model.accessibilityTrusted ? "Accessibility access looks good." : "Accessibility access is still needed for reliable window focusing.", systemImage: model.accessibilityTrusted ? "checkmark.circle.fill" : "hand.raised.fill")
                    .foregroundStyle(model.accessibilityTrusted ? .green : .orange)

                Button("Open Accessibility Settings") {
                    model.openAccessibilitySettings()
                }
            }

            if let launchAtLoginMessage = model.launchAtLoginMessage {
                Text(launchAtLoginMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack {
                Button("Quit Overwatchr") {
                    model.quit()
                }
                Spacer()
            }
        }
        .padding(20)
    }
}
#endif
