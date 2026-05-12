#if os(macOS)
import AppKit
import SwiftUI

enum VoiceInteractionDisplayState: Equatable {
    case idle
    case listening
    case processing
    case inserted
    case failed(String)

    var label: String {
        switch self {
        case .idle:
            return ""
        case .listening:
            return "Listening"
        case .processing:
            return "Transcribing"
        case .inserted:
            return "Inserted"
        case .failed:
            return "Voice failed"
        }
    }

    var symbolName: String {
        switch self {
        case .idle:
            return "mic"
        case .listening:
            return "mic.fill"
        case .processing:
            return "waveform"
        case .inserted:
            return "checkmark"
        case .failed:
            return "exclamationmark"
        }
    }
}

@MainActor
final class VoiceIndicatorPanel {
    private var panel: NSPanel?
    private let panelSize = NSSize(width: 218, height: 70)

    func show(state: VoiceInteractionDisplayState) {
        guard state != .idle else {
            hide()
            return
        }

        let content = VoiceIndicatorView(state: state)
        if panel == nil {
            panel = makePanel()
        }

        panel?.contentView = NSHostingView(rootView: content)
        positionPanel()
        panel?.orderFrontRegardless()
    }

    func hide(after delay: TimeInterval = 0) {
        guard delay > 0 else {
            panel?.orderOut(nil)
            return
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            panel?.orderOut(nil)
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        return panel
    }

    private func positionPanel() {
        guard let panel else {
            return
        }

        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let frame = screen?.visibleFrame else {
            return
        }

        let size = panel.frame.size
        let origin = NSPoint(
            x: frame.midX - size.width / 2,
            y: frame.maxY - size.height - 28
        )
        panel.setFrameOrigin(origin)
    }
}

private struct VoiceIndicatorView: View {
    let state: VoiceInteractionDisplayState

    @State private var isAnimating = false

    var body: some View {
        HStack(spacing: 12) {
            stateIcon
                .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(state.label)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                Text(detailText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.68))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(width: 218, height: 70)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(red: 10 / 255, green: 15 / 255, blue: 31 / 255).opacity(0.94))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(symbolColor.opacity(0.28), lineWidth: 1)
                )
        )
        .onAppear {
            isAnimating = false
            withAnimation(activeAnimation) {
                isAnimating = true
            }
        }
    }

    @ViewBuilder
    private var stateIcon: some View {
        ZStack {
            if state == .listening {
                Circle()
                    .stroke(symbolColor.opacity(isAnimating ? 0.02 : 0.34), lineWidth: 2)
                    .scaleEffect(isAnimating ? 1.34 : 0.82)
            }

            Circle()
                .fill(symbolColor.opacity(state == .listening ? 0.22 : 0.16))
                .scaleEffect(state == .listening && isAnimating ? 1.04 : 1.0)

            if state == .processing {
                WaveformBars(color: symbolColor, isAnimating: isAnimating)
                    .frame(width: 24, height: 22)
            } else {
                Image(systemName: state.symbolName)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(symbolColor)
                    .scaleEffect(state == .listening && isAnimating ? 1.08 : 1.0)
            }
        }
    }

    private var activeAnimation: Animation {
        switch state {
        case .listening:
            return .easeInOut(duration: 0.8).repeatForever(autoreverses: true)
        case .processing:
            return .easeInOut(duration: 0.54).repeatForever(autoreverses: true)
        case .idle, .inserted, .failed:
            return .default
        }
    }

    private var symbolColor: Color {
        switch state {
        case .idle:
            return .white
        case .listening, .processing:
            return BrandPalette.accent
        case .inserted:
            return .green
        case .failed:
            return .orange
        }
    }

    private var detailText: String {
        switch state {
        case .idle:
            return ""
        case .listening:
            return "Release to insert"
        case .processing:
            return "Azure Speech"
        case .inserted:
            return "Ready"
        case .failed(let message):
            return message
        }
    }
}

private struct WaveformBars: View {
    let color: Color
    let isAnimating: Bool

    private let baseHeights: [CGFloat] = [8, 15, 22, 14, 9]

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(baseHeights.indices, id: \.self) { index in
                Capsule()
                    .fill(color)
                    .frame(width: 3, height: isAnimating ? animatedHeight(for: index) : baseHeights[index])
                    .opacity(index == 0 || index == baseHeights.count - 1 ? 0.68 : 1)
                    .animation(
                        .easeInOut(duration: 0.48)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.08),
                        value: isAnimating
                    )
            }
        }
    }

    private func animatedHeight(for index: Int) -> CGFloat {
        let shiftedIndex = (index + 2) % baseHeights.count
        return baseHeights[shiftedIndex]
    }
}
#endif
