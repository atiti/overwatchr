#if os(macOS)
import AppKit
import OverwatchrCore
import SwiftUI

@MainActor
final class AgentProgressOverlay {
    private struct Card {
        let sessionID: String
        let panel: NSPanel
        let content: NSHostingView<ProgressCard>
        var expiresAt: TimeInterval
        var slot: Int
    }

    private let reader = CodexProgressReader()
    private let size = NSSize(width: 340, height: 88)
    private let lifetime: TimeInterval = 9
    private var monitor: CodexProgressMonitor?
    private var startMonitor: Task<Void, Never>?
    private var streamID = UUID()
    private var expiration: Task<Void, Never>?
    private var cards: [Card] = []
    private var screen: NSScreen?

    func setEnabled(_ enabled: Bool) {
        startMonitor?.cancel()
        startMonitor = nil
        monitor = nil
        streamID = UUID()
        clear()
        guard enabled else { return }

        let streamID = self.streamID
        let startedAt = Date()
        startMonitor = Task { [weak self, reader] in
            while !Task.isCancelled {
                guard let self else { return }
                self.monitor = CodexProgressMonitor(reader: reader, startedAt: startedAt) { updates in
                    Task { @MainActor [weak self] in
                        guard let self, self.streamID == streamID else { return }
                        for update in updates { self.show(update) }
                    }
                }
                if self.monitor != nil { return }
                // Codex may not have created its sessions directory yet.
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    private func show(_ update: CodexProgress) {
        let deadline = ProcessInfo.processInfo.systemUptime + lifetime
        if let index = cards.firstIndex(where: { $0.sessionID == update.sessionID }) {
            cards[index].content.rootView = ProgressCard(update: update)
            cards[index].expiresAt = deadline
            return
        }

        if cards.isEmpty {
            screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        }
        let content = NSHostingView(rootView: ProgressCard(update: update))
        let panel = makePanel(content: content)
        var card = Card(sessionID: update.sessionID, panel: panel, content: content, expiresAt: deadline, slot: 0)
        if cards.count == 3 {
            let pointer = NSEvent.mouseLocation
            guard let index = cards.indices
                .filter({ !cards[$0].panel.frame.contains(pointer) })
                .min(by: { cards[$0].expiresAt < cards[$1].expiresAt }) else { return }
            cards[index].panel.orderOut(nil)
            card.slot = cards[index].slot
            cards[index] = card
        } else {
            let occupied = Set(cards.map(\.slot))
            card.slot = (0..<3).first { !occupied.contains($0) } ?? 0
            cards.append(card)
        }
        layout()
        panel.orderFrontRegardless()
        if expiration == nil {
            expiration = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(100))
                    guard !Task.isCancelled, let self else { return }
                    self.expireCards()
                    if self.cards.isEmpty {
                        self.expiration = nil
                        return
                    }
                }
            }
        }
    }

    private func expireCards() {
        let pointer = NSEvent.mouseLocation
        let now = ProcessInfo.processInfo.systemUptime
        let hovered = cards.firstIndex { $0.panel.frame.contains(pointer) }
        if let hovered {
            cards[hovered].expiresAt = max(cards[hovered].expiresAt, now + 1)
        }
        cards.removeAll { card in
            guard card.expiresAt <= now else { return false }
            card.panel.orderOut(nil)
            return true
        }

        // Close gaps only after the pointer leaves, keeping the hovered card still.
        if hovered == nil {
            cards.sort { $0.slot < $1.slot }
            var moved = false
            for index in cards.indices where cards[index].slot != index {
                cards[index].slot = index
                moved = true
            }
            if moved { layout() }
        }
    }

    private func clear() {
        expiration?.cancel()
        expiration = nil
        for card in cards { card.panel.orderOut(nil) }
        cards.removeAll()
        screen = nil
    }

    private func layout() {
        guard let frame = (screen ?? NSScreen.main)?.visibleFrame else { return }
        for card in cards {
            card.panel.setFrameOrigin(NSPoint(
                x: frame.maxX - size.width - 16,
                y: frame.maxY - size.height - 14 - CGFloat(card.slot) * (size.height + 8)
            ))
        }
    }

    private func makePanel(content: NSView) -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
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
        panel.ignoresMouseEvents = true

        let glass = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        glass.material = .popover
        glass.blendingMode = .behindWindow
        glass.state = .active
        glass.wantsLayer = true
        glass.layer?.cornerRadius = 16
        glass.layer?.masksToBounds = true
        content.frame = glass.bounds
        content.autoresizingMask = [.width, .height]
        glass.addSubview(content)
        panel.contentView = glass
        return panel
    }
}

private struct ProgressCard: View {
    let update: CodexProgress

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "sparkle")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(BrandPalette.accent)
                .frame(width: 27, height: 27)
                .background(.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(update.project.isEmpty ? "Codex" : update.project)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(update.project.isEmpty
                         ? String(update.sessionID.suffix(4))
                         : "Codex · \(update.sessionID.suffix(4))")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .fixedSize()
                }
                Text(update.message)
                    .font(.system(size: 12))
                    .foregroundStyle(.primary)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay {
            RoundedRectangle(cornerRadius: 16).strokeBorder(.primary.opacity(0.10), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }
}
#endif
