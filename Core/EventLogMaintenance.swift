import Foundation

public struct EventLogStats: Equatable, Sendable {
    public let totalEvents: Int
    public let malformedLines: Int
    public let uniqueAgents: Int
    public let activeAlerts: Int
    public let fileSizeBytes: UInt64
    public let oldestTimestamp: TimeInterval?
    public let newestTimestamp: TimeInterval?
}

public struct EventLogRewriteResult: Equatable, Sendable {
    public let originalCount: Int
    public let retainedCount: Int
    public let malformedLinesDropped: Int
    public let backupFileURL: URL

    public var droppedCount: Int {
        originalCount - retainedCount + malformedLinesDropped
    }
}

public struct EventLogMaintenance: Sendable {
    public let store: EventStore

    public init(store: EventStore = EventStore()) {
        self.store = store
    }

    public func stats() throws -> EventLogStats {
        let report = try store.loadReport()
        var queue = AlertQueue()
        queue.apply(report.events)

        return EventLogStats(
            totalEvents: report.events.count,
            malformedLines: report.malformedLineCount,
            uniqueAgents: Set(report.events.map(\.agentID)).count,
            activeAlerts: queue.count,
            fileSizeBytes: try store.fileSizeBytes(),
            oldestTimestamp: report.events.map(\.timestamp).min(),
            newestTimestamp: report.events.map(\.timestamp).max()
        )
    }

    public func compact() throws -> EventLogRewriteResult {
        let snapshot = try snapshotData()
        let report = try store.loadReport()

        var latestIndexByAgentID: [String: Int] = [:]
        for (index, event) in report.events.enumerated() {
            latestIndexByAgentID[event.agentID] = index
        }

        let retainedEvents = report.events.enumerated().compactMap { index, event in
            latestIndexByAgentID[event.agentID] == index ? event : nil
        }
        let backupURL = try writeBackup(snapshot)
        try store.replaceAll(with: retainedEvents)

        return EventLogRewriteResult(
            originalCount: report.events.count,
            retainedCount: retainedEvents.count,
            malformedLinesDropped: report.malformedLineCount,
            backupFileURL: backupURL
        )
    }

    public func prune(olderThan age: TimeInterval, now: Date = Date()) throws -> EventLogRewriteResult {
        let snapshot = try snapshotData()
        let report = try store.loadReport()
        let cutoff = now.timeIntervalSince1970 - age

        var latestIndexByAgentID: [String: Int] = [:]
        for (index, event) in report.events.enumerated() {
            latestIndexByAgentID[event.agentID] = index
        }

        let retainedEvents = report.events.enumerated().compactMap { index, event in
            (event.timestamp >= cutoff || latestIndexByAgentID[event.agentID] == index) ? event : nil
        }

        let backupURL = try writeBackup(snapshot)
        try store.replaceAll(with: retainedEvents)

        return EventLogRewriteResult(
            originalCount: report.events.count,
            retainedCount: retainedEvents.count,
            malformedLinesDropped: report.malformedLineCount,
            backupFileURL: backupURL
        )
    }

    public static func parseAge(_ rawValue: String) -> TimeInterval? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else {
            return nil
        }

        let suffix = trimmed.last!
        let multiplier: TimeInterval
        let numberString: String

        switch suffix {
        case "d":
            multiplier = 86_400
            numberString = String(trimmed.dropLast())
        case "h":
            multiplier = 3_600
            numberString = String(trimmed.dropLast())
        case "m":
            multiplier = 60
            numberString = String(trimmed.dropLast())
        case "s":
            multiplier = 1
            numberString = String(trimmed.dropLast())
        default:
            multiplier = 86_400
            numberString = trimmed
        }

        guard let value = Double(numberString), value > 0 else {
            return nil
        }
        return value * multiplier
    }

    private func snapshotData() throws -> Data {
        try store.ensureStorage()
        return try Data(contentsOf: store.fileURL)
    }

    private func writeBackup(_ data: Data) throws -> URL {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss"

        let backupURL = store.fileURL.deletingLastPathComponent()
            .appendingPathComponent("events.backup-\(formatter.string(from: Date())).jsonl")
        try data.write(to: backupURL, options: .atomic)
        return backupURL
    }
}
