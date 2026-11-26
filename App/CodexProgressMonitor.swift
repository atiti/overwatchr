#if os(macOS)
import Foundation
import OverwatchrCore

/// Polls today's session folders and sweeps the whole archive now and then.
///
/// File system events were not reliably delivered for appends to rollout files,
/// so a cheap timer does the watching.
final class CodexProgressMonitor {
    private static let pollInterval: TimeInterval = 1
    private static let sweepEveryPolls = 15

    private let timer: DispatchSourceTimer

    init?(
        reader: CodexProgressReader,
        startedAt: Date,
        onUpdates: @escaping @Sendable ([CodexProgress]) -> Void
    ) {
        guard FileManager.default.fileExists(atPath: reader.canonicalDirectory.path) else { return nil }
        let consumer = Consumer(reader: reader, startedAt: startedAt, onUpdates: onUpdates)
        let queue = DispatchQueue(label: "overwatchr.codex-progress", qos: .utility)
        timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + Self.pollInterval, repeating: Self.pollInterval)
        timer.setEventHandler { consumer.poll() }
        timer.resume()
    }

    deinit {
        timer.cancel()
    }

    private final class Consumer {
        let reader: CodexProgressReader
        let startedAt: Date
        let onUpdates: @Sendable ([CodexProgress]) -> Void
        // Accessed only on the timer queue.
        var delivered: [String: Date] = [:]
        var pollCount = 0

        init(
            reader: CodexProgressReader, startedAt: Date,
            onUpdates: @escaping @Sendable ([CodexProgress]) -> Void
        ) {
            self.reader = reader
            self.startedAt = startedAt
            self.onUpdates = onUpdates
        }

        func poll() {
            pollCount += 1
            let isSweep = pollCount % CodexProgressMonitor.sweepEveryPolls == 0
            let now = Date()
            let cutoff = max(startedAt, now.addingTimeInterval(-30))
            delivered = delivered.filter { $0.value >= cutoff }
            let updates = reader.latestUpdates(
                since: cutoff, now: now, changedFiles: isSweep ? nil : reader.recentFiles(now: now)
            )
            let fresh = updates.filter { update in
                guard (delivered[update.sessionID] ?? .distantPast) < update.timestamp else { return false }
                delivered[update.sessionID] = update.timestamp
                return true
            }
            if !fresh.isEmpty { onUpdates(fresh) }
        }
    }
}
#endif
