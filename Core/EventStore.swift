import Foundation
import Darwin

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
    public static let environmentOverrideKey = "OVERWATCHR_EVENTS_FILE"

    public let fileURL: URL

    public init(
        fileURL: URL? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        if let fileURL {
            self.fileURL = fileURL
        } else if let override = environment[EventStore.environmentOverrideKey], !override.isEmpty {
            self.fileURL = URL(fileURLWithPath: override)
        } else {
            self.fileURL = EventStore.defaultFileURL
        }
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
        var line = try encoder.encode(event)
        guard let lineBreak = "\n".data(using: .utf8) else {
            throw EventStoreError.invalidEncoding
        }
        line.append(lineBreak)

        let descriptor = open(fileURL.path, O_WRONLY | O_APPEND | O_CREAT, S_IRUSR | S_IWUSR | S_IRGRP | S_IROTH)
        guard descriptor >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }

        defer {
            _ = flock(descriptor, LOCK_UN)
            close(descriptor)
        }

        guard flock(descriptor, LOCK_EX) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }

        try line.withUnsafeBytes { buffer in
            guard let baseAddress = buffer.baseAddress else {
                return
            }

            var bytesRemaining = buffer.count
            var offset = 0

            while bytesRemaining > 0 {
                let written = write(descriptor, baseAddress.advanced(by: offset), bytesRemaining)
                if written < 0 {
                    throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
                }

                bytesRemaining -= written
                offset += written
            }
        }
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
