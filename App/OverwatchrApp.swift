#if os(macOS)
import AppKit
import OverwatchrCore
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
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
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            StatusMenuView(model: model)
                .frame(width: 380)
        } label: {
            StatusItemLabel(alertCount: model.alertCount)
                .help(model.alertCount == 0 ? "overwatchr is watching quietly" : "overwatchr has \(model.alertCount) active alert(s)")
        }
        .menuBarExtraStyle(.window)
    }
}

private struct StatusMenuView: View {
    @ObservedObject var model: AppModel
    @State private var showingSettings = false

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
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Attention Queue")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(model.alertCount == 0 ? "Nothing is asking for help right now." : "Newest pings stay at the top. Tap the arrow to jump in.")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.white.opacity(0.7))
                }

                Spacer()

                Text("\(model.alertCount)")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(model.alertCount == 0 ? Color.white.opacity(0.56) : BrandPalette.accent)
            }

            if model.alerts.isEmpty {
                EmptyQueueCard()
            } else {
                ScrollView {
                    VStack(spacing: 10) {
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
                .frame(minHeight: 96, maxHeight: 220)
            }
        }
        .padding(14)
        .background(cardBackground)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let lastErrorMessage = model.lastErrorMessage {
                Text(lastErrorMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.72))
                    .padding(.top, 2)
            }

            HStack {
                Text("Last refresh \(model.lastUpdatedAt.formatted(date: .omitted, time: .shortened))")
                Spacer()
                Text("\(AppVersion.displayString) · Jump: Ctrl+Option+Cmd+O")
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

            settingsCard

            VStack(alignment: .leading, spacing: 10) {
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
                    subtitle: model.accessibilityTrusted ? "Window focusing permissions look good." : "Needed for reliable terminal focusing."
                ) {
                    Button("Open") {
                        model.openAccessibilitySettings()
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.white)
                }
            }
            .padding(14)
            .background(cardBackground)

            if let launchAtLoginMessage = model.launchAtLoginMessage {
                Text(launchAtLoginMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.68))
            }

            Spacer()

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

    private var settingsCard: some View {
        HStack(spacing: 12) {
            if let image = BrandAssets.logoImage() {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("overwatchr")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("Tracks agent pings and brings the right terminal forward.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.white.opacity(0.7))
            }

            Spacer()
        }
        .padding(14)
        .background(cardBackground)
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
            Text(alert.displayName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)

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
        Text(alert.displaySubtitle)
            .font(.system(size: 12))
            .foregroundStyle(Color.white.opacity(0.74))
            .lineLimit(2)
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
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.66))
            }
            Spacer()
            accessory
        }
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
