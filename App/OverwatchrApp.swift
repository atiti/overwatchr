#if os(macOS)
import AppKit
import OverwatchrCore
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            heroCard

            if !model.alerts.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Attention Queue")
                            .font(.system(size: 13, weight: .semibold))
                        Spacer()
                        Text("\(model.alertCount)")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(BrandPalette.accent)
                    }
                    .foregroundStyle(.white)

                    ScrollView {
                        VStack(spacing: 10) {
                            ForEach(model.alerts) { alert in
                                AlertRow(alert: alert) {
                                    model.focus(alert)
                                }
                                .accessibilityIdentifier("alert-\(alert.agentID)")
                            }
                        }
                    }
                    .frame(maxHeight: 220)
                }
            }

            footer
        }
        .padding(16)
        .background(
            LinearGradient(
                colors: [BrandPalette.background, BrandPalette.primary.opacity(0.95)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
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
                Text(model.alertCount == 0 ? "Quietly watching your agent swarm." : "Your control tower has \(model.alertCount) live ping\(model.alertCount == 1 ? "" : "s").")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.72))
            }
            Spacer()
        }
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.alertCount == 0 ? "Airspace clear" : "Human needed")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(model.alertCount == 0 ? "Nothing is asking for help right now." : "Jump straight to the freshest terminal ping.")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.white.opacity(0.72))
                }
                Spacer()
                StatusPill(count: model.alertCount)
            }

            Button {
                model.focusNextAlert()
            } label: {
                HStack {
                    Image(systemName: "arrow.up.forward.app.fill")
                    Text(model.alertCount == 0 ? "No active ping" : "Jump To Newest Ping")
                    Spacer()
                    Text("Cmd+Shift+A")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.75))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(model.alertCount == 0 ? Color.white.opacity(0.06) : BrandPalette.accent.opacity(0.18))
                )
            }
            .buttonStyle(.plain)
            .disabled(model.alertCount == 0)
        }
        .padding(14)
        .background(cardBackground)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                FooterButton(title: "Reveal Event Log", systemImage: "doc.text.magnifyingglass") {
                    model.revealEventLog()
                }
                FooterButton(title: "Copy CLI Example", systemImage: "terminal") {
                    model.copyCLIExample()
                }
            }

            if !model.accessibilityTrusted {
                FooterButton(title: "Open Accessibility Settings", systemImage: "hand.raised.fill") {
                    model.openAccessibilitySettings()
                }
            }

            if let lastErrorMessage = model.lastErrorMessage {
                Text(lastErrorMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.72))
                    .padding(.top, 2)
            }

            HStack {
                Text("Last refresh \(model.lastUpdatedAt.formatted(date: .omitted, time: .shortened))")
                Spacer()
                Text("Ghostty • iTerm • Terminal")
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Color.white.opacity(0.56))
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

private struct AlertRow: View {
    let alert: AgentEvent
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            content
        }
        .buttonStyle(.plain)
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
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 5) {
                titleRow
                subtitleRow
                metadataRow
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
    }

    private var titleRow: some View {
        HStack {
            Text(alert.displayName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
            Spacer()
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
        HStack {
            Label(terminalLabel, systemImage: "terminal")
            Spacer()
            Text(timestampLabel)
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(Color.white.opacity(0.5))
    }
}

private struct FooterButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                Text(title)
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.07))
            )
        }
        .buttonStyle(.plain)
    }
}

private struct StatusItemLabel: View {
    let alertCount: Int

    var body: some View {
        HStack(spacing: 5) {
            if let image = BrandAssets.statusTemplateImage() {
                Image(nsImage: image)
                    .renderingMode(.template)
            } else {
                Image(systemName: alertCount == 0 ? "eye.fill" : "bolt.fill")
                    .font(.system(size: 12, weight: .semibold))
            }

            if alertCount > 0 {
                Text("\(alertCount)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .monospacedDigit()
            }
        }
        .accessibilityLabel("overwatchr \(alertCount) active alerts")
    }
}

private struct StatusPill: View {
    let count: Int

    var body: some View {
        VStack(spacing: 4) {
            Text("\(count)")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .monospacedDigit()
            Text(count == 1 ? "alert" : "alerts")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.68))
                .textCase(.uppercase)
        }
        .frame(width: 62, height: 62)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(BrandPalette.accent.opacity(count == 0 ? 0.10 : 0.18))
        )
    }
}
#endif
