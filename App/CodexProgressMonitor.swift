#if os(macOS)
import CoreServices
import Foundation
import OverwatchrCore

/// Watches local Codex writes without polling the transcript archive.
final class CodexProgressMonitor {
    private let stream: FSEventStreamRef

    init?(
        reader: CodexProgressReader,
        startedAt: Date,
        onUpdates: @escaping @Sendable ([CodexProgress]) -> Void
    ) {
        let directory = reader.canonicalDirectory
        guard FileManager.default.fileExists(atPath: directory.path) else { return nil }
        let consumer = Consumer(reader: reader, startedAt: startedAt, onUpdates: onUpdates)
        var context = FSEventStreamContext()
        context.info = Unmanaged.passUnretained(consumer).toOpaque()
        context.retain = { info in
            guard let info else { return nil }
            return UnsafeRawPointer(Unmanaged<Consumer>.fromOpaque(info).retain().toOpaque())
        }
        context.release = { info in
            if let info { Unmanaged<Consumer>.fromOpaque(info).release() }
        }
        let callback: FSEventStreamCallback = { _, info, count, paths, flags, _ in
            guard let info else { return }
            let names = paths.assumingMemoryBound(to: UnsafePointer<CChar>?.self)
            var files: Set<URL> = []
            var needsRescan = false
            for index in 0..<count {
                if flags[index] & FSEventStreamEventFlags(kFSEventStreamEventFlagMustScanSubDirs) != 0 {
                    needsRescan = true
                }
                let writes = kFSEventStreamEventFlagItemCreated
                    | kFSEventStreamEventFlagItemRenamed | kFSEventStreamEventFlagItemModified
                if flags[index] & FSEventStreamEventFlags(writes) != 0, let name = names[index] {
                    files.insert(URL(fileURLWithPath: String(cString: name)))
                }
            }
            guard needsRescan || !files.isEmpty else { return }
            Unmanaged<Consumer>.fromOpaque(info).takeUnretainedValue().read(needsRescan ? nil : files)
        }
        guard let stream = FSEventStreamCreate(
            nil, callback, &context, [directory.path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.6,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents)
        ) else { return nil }

        FSEventStreamSetDispatchQueue(stream, DispatchQueue(label: "overwatchr.codex-progress", qos: .utility))
        guard FSEventStreamStart(stream) else {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            return nil
        }
        self.stream = stream
    }

    deinit {
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }

    private final class Consumer {
        let reader: CodexProgressReader
        let startedAt: Date
        let onUpdates: @Sendable ([CodexProgress]) -> Void
        // Accessed only on the FSEvents dispatch queue.
        var delivered: [String: Date] = [:]

        init(
            reader: CodexProgressReader, startedAt: Date,
            onUpdates: @escaping @Sendable ([CodexProgress]) -> Void
        ) {
            self.reader = reader
            self.startedAt = startedAt
            self.onUpdates = onUpdates
        }

        func read(_ files: Set<URL>?) {
            let now = Date()
            let cutoff = max(startedAt, now.addingTimeInterval(-30))
            delivered = delivered.filter { $0.value >= cutoff }
            let updates = reader.latestUpdates(since: cutoff, now: now, changedFiles: files)
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
