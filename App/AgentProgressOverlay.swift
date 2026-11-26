#if os(macOS)
import AppKit
import OverwatchrCore
import SwiftUI

@MainActor
final class AgentProgressOverlay {
    private struct Card {
        let sessionID: String
        let panel: NSPanel
        let content: ClickableHostingView<ProgressCard>
        var update: CodexProgress
        var expiresAt: TimeInterval
        var slot: Int
        var isExpanded = false
        var error: String?
    }

    var onJump: ((CodexProgress) throws -> Void)?
    private let reader = CodexProgressReader()
    private let size = NSSize(width: 340, height: 88)
    private let expandedWidth: CGFloat = 440
    private let expandedMaxHeight: CGFloat = 420
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
            cards[index].update = update
            cards[index].content.rootView = progressCard(for: cards[index])
            cards[index].expiresAt = deadline
            layout()
            return
        }

        if cards.isEmpty {
            screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        }
        let content = ClickableHostingView(rootView: ProgressCard(update: update, isExpanded: false, error: nil, onToggle: {}, onJump: {}, onDismiss: {}))
        let panel = makePanel(content: content)
        var card = Card(
            sessionID: update.sessionID, panel: panel, content: content,
            update: update, expiresAt: deadline, slot: 0
        )
        card.content.rootView = progressCard(for: card)
        if cards.count == 3 {
            let pointer = NSEvent.mouseLocation
            guard let index = cards.indices
                .filter({ !cards[$0].panel.frame.contains(pointer) && !cards[$0].isExpanded })
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
        for index in cards.indices where cards[index].isExpanded {
            cards[index].expiresAt = now + lifetime
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

    private func progressCard(for card: Card) -> ProgressCard {
        ProgressCard(
            update: card.update,
            isExpanded: card.isExpanded,
            error: card.error,
            onToggle: { [weak self, sessionID = card.sessionID] in self?.toggleExpansion(of: sessionID) },
            onJump: { [weak self, sessionID = card.sessionID] in self?.jump(to: sessionID) },
            onDismiss: { [weak self, sessionID = card.sessionID] in self?.dismiss(sessionID) }
        )
    }

    private func dismiss(_ sessionID: String) {
        guard let index = cards.firstIndex(where: { $0.sessionID == sessionID }) else { return }
        cards.remove(at: index).panel.orderOut(nil)
        layout()
    }

    private func jump(to sessionID: String) {
        guard let index = cards.firstIndex(where: { $0.sessionID == sessionID }) else { return }
        do {
            try onJump?(cards[index].update)
            dismiss(sessionID)
        } catch {
            cards[index].error = error.localizedDescription
            cards[index].isExpanded = true
            cards[index].content.rootView = progressCard(for: cards[index])
            layout()
        }
    }

    private func toggleExpansion(of sessionID: String) {
        guard let index = cards.firstIndex(where: { $0.sessionID == sessionID }) else { return }
        cards[index].isExpanded.toggle()
        cards[index].expiresAt = ProcessInfo.processInfo.systemUptime + lifetime
        cards[index].content.rootView = progressCard(for: cards[index])
        layout()
    }

    private func cardSize(_ card: Card, maxHeight: CGFloat) -> NSSize {
        guard card.isExpanded else { return size }
        let lineCount = card.update.body.split(separator: "\n", omittingEmptySubsequences: false)
            .reduce(0) { $0 + max(1, ($1.count + 55) / 56) }
        let height = min(max(size.height, 60 + CGFloat(lineCount) * 16), min(expandedMaxHeight, maxHeight))
        return NSSize(width: expandedWidth, height: height)
    }

    private func layout() {
        guard let frame = (screen ?? NSScreen.main)?.visibleFrame else { return }
        var top = frame.maxY - 14
        for card in cards.sorted(by: { $0.slot < $1.slot }) {
            let cardSize = cardSize(card, maxHeight: frame.height - 40)
            let origin = NSPoint(x: frame.maxX - cardSize.width - 16, y: top - cardSize.height)
            card.panel.setFrame(NSRect(origin: origin, size: cardSize), display: true)
            top = origin.y - 8
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
        panel.ignoresMouseEvents = false

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

/// Delivers the first click to the card even though the panel never becomes key.
private final class ClickableHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private func inlineMarkdown(_ text: String) -> AttributedString {
    let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
    return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
}

private struct ProgressCard: View {
    let update: CodexProgress
    let isExpanded: Bool
    let error: String?
    let onToggle: () -> Void
    let onJump: () -> Void
    let onDismiss: () -> Void

    private var heading: String {
        if let title = update.title { return title }
        return update.project.isEmpty ? "Codex" : update.project
    }

    private var subheading: String {
        let project = update.project.isEmpty || update.title == nil ? "" : update.project + " · "
        return project + "Codex · " + update.sessionID.suffix(4)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "sparkle")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(BrandPalette.accent)
                .frame(width: 27, height: 27)
                .background(.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top, spacing: 6) {
                  VStack(alignment: .leading, spacing: 1) {
                    Text(heading)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    Text(subheading)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                  }
                  Spacer(minLength: 0)
                  Button(action: onJump) {
                      Label("Jump", systemImage: "arrow.up.right")
                  }
                  .buttonStyle(.borderless)
                  .font(.system(size: 11, weight: .semibold))
                  Button(action: onDismiss) { Image(systemName: "xmark") }
                      .buttonStyle(.borderless)
                      .accessibilityLabel("Dismiss notification")
                }
                if let error {
                    Text(error).font(.system(size: 11)).foregroundStyle(.red)
                }
                if isExpanded {
                    ScrollView {
                        MarkdownMessage(blocks: MarkdownBlockParser.parse(update.body))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.bottom, 2)
                    }
                } else {
                    Text(inlineMarkdown(update.message))
                        .font(.system(size: 12))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay {
            RoundedRectangle(cornerRadius: 16).strokeBorder(.primary.opacity(0.10), lineWidth: 1)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onToggle)
        .simultaneousGesture(
            DragGesture(minimumDistance: 30)
                .onEnded { value in
                    if abs(value.translation.width) > 70 &&
                        abs(value.translation.width) > abs(value.translation.height) {
                        onDismiss()
                    }
                }
        )
    }
}

private struct MarkdownMessage: View {
    let blocks: [MarkdownBlock]

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                view(for: block)
            }
        }
    }

    @ViewBuilder
    private func view(for block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(inlineMarkdown(text))
                .font(.system(size: level <= 1 ? 15 : level == 2 ? 14 : 13, weight: .semibold))
                .padding(.top, 2)
        case .paragraph(let text):
            Text(inlineMarkdown(text))
                .font(.system(size: 12.5))
                .lineSpacing(2)
        case .listItem(let marker, let text, let depth):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(marker)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(BrandPalette.accent)
                    .frame(minWidth: 12, alignment: .trailing)
                Text(inlineMarkdown(text))
                    .font(.system(size: 12.5))
                    .lineSpacing(2)
            }
            .padding(.leading, CGFloat(depth) * 14)
        case .quote(let text):
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 1.5).fill(BrandPalette.accent.opacity(0.7)).frame(width: 3)
                Text(inlineMarkdown(text))
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
        case .code(_, let text):
            Text(text)
                .font(.system(size: 11.5, design: .monospaced))
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 8))
        case .table(let rows):
            MarkdownTable(rows: rows)
        case .rule:
            Divider().opacity(0.5)
        }
    }
}

private struct MarkdownTable: View {
    let rows: [String]

    private var cells: [[String]] {
        rows.compactMap { row -> [String]? in
            let parts = row.split(separator: "|", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .dropFirst().dropLast()
            let isSeparator = !parts.isEmpty && parts.allSatisfy { $0.allSatisfy { "-: ".contains($0) } }
            return isSeparator ? nil : Array(parts)
        }
    }

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
            ForEach(Array(cells.enumerated()), id: \.offset) { rowIndex, row in
                GridRow {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                        Text(inlineMarkdown(cell))
                            .font(.system(size: 11.5, weight: rowIndex == 0 ? .semibold : .regular))
                    }
                }
            }
        }
        .padding(8)
        .background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }
}
#endif
