import Foundation

public enum EventStoreError: Error, LocalizedError {
    case invalidEncoding
    case invalidEventLine(String)

    public var errorDescription: String? {
        switch self {
        case .invalidEncoding:
            return "Could not decode the events file as UTF-8."
        case .invalidEventLine(let line):
            return "Could not decode event line: \(line)"
        }
    }
}

public struct EventReadBatch: Equatable, Sendable {
    public let events: [AgentEvent]
    public let nextOffset: UInt64
}

public struct EventStore: Sendable {
    public static let defaultDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".overwatchr", isDirectory: true)
    public static let defaultFileURL = defaultDirectoryURL.appendingPathComponent("events.jsonl")

    public let fileURL: URL

    public init(fileURL: URL = EventStore.defaultFileURL) {
        self.fileURL = fileURL
    }

    public func ensureStorage() throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            _ = FileManager.default.createFile(atPath: fileURL.path, contents: Data())
        }
    }

    public func append(_ event: AgentEvent) throws {
        try ensureStorage()

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let encoded = try encoder.encode(event)

        guard let lineBreak = "\n".data(using: .utf8) else {
            throw EventStoreError.invalidEncoding
        }

        let handle = try FileHandle(forWritingTo: fileURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: encoded)
        try handle.write(contentsOf: lineBreak)
    }

    public func loadAll() throws -> [AgentEvent] {
        try readEvents(from: 0).events
    }

    public func readEvents(from offset: UInt64) throws -> EventReadBatch {
        try ensureStorage()

        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        let fileSize = try handle.seekToEnd()
        let safeOffset = min(offset, fileSize)
        try handle.seek(toOffset: safeOffset)
        let data = handle.readDataToEndOfFile()
        let nextOffset = safeOffset + UInt64(data.count)

        guard !data.isEmpty else {
            return EventReadBatch(events: [], nextOffset: nextOffset)
        }

        return EventReadBatch(events: try decodeLines(from: data), nextOffset: nextOffset)
    }

    private func decodeLines(from data: Data) throws -> [AgentEvent] {
        guard let string = String(data: data, encoding: .utf8) else {
            throw EventStoreError.invalidEncoding
        }

        let decoder = JSONDecoder()
        var events: [AgentEvent] = []

        for line in string.split(whereSeparator: \.isNewline).map(String.init).filter({ !$0.isEmpty }) {
            guard let lineData = line.data(using: .utf8) else {
                throw EventStoreError.invalidEncoding
            }

            do {
                events.append(try decoder.decode(AgentEvent.self, from: lineData))
            } catch {
                // Keep the watcher resilient if a single line in the append-only log gets corrupted.
                continue
            }
        }

        return events
    }
}
