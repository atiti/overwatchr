import Foundation

public struct CodexProgress: Equatable, Sendable {
    public let sessionID: String
    public let project: String
    public let message: String
    /// The complete message with its original line breaks and Markdown.
    public let body: String
    public let timestamp: Date
    /// The chat's name from Codex, when it has one.
    public var title: String?
}

public struct CodexProgressReader: Sendable {
    public let sessionsDirectory: URL
    public let sessionIndexURL: URL

    public init(sessionsDirectory: URL? = nil, sessionIndexURL: URL? = nil) {
        let codexHome = ProcessInfo.processInfo.environment["CODEX_HOME"]
            .flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
        self.sessionsDirectory = sessionsDirectory ?? codexHome.appendingPathComponent("sessions")
        self.sessionIndexURL = sessionIndexURL ?? codexHome.appendingPathComponent("session_index.jsonl")
    }

    /// Looks up the chat's current name. Codex appends a line to its index on every rename.
    public func attachingTitle(to progress: CodexProgress) -> CodexProgress {
        var titled = progress
        titled.title = title(forSessionID: progress.sessionID)
        return titled
    }

    private func title(forSessionID sessionID: String) -> String? {
        guard let index = try? Data(contentsOf: sessionIndexURL, options: .mappedIfSafe),
              let idBytes = sessionID.data(using: .utf8) else { return nil }
        let entries = index.split(separator: 10)
            .filter { $0.range(of: idBytes) != nil }
            .compactMap { record($0) }
            .filter { $0["id"] as? String == sessionID }
        guard let name = (entries.last?["thread_name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty, !["New chat", "Guardian review"].contains(name) else { return nil }
        return name
    }

    public var canonicalDirectory: URL {
        canonicalURL(sessionsDirectory) ?? sessionsDirectory
    }

    /// Rollout files in today's and yesterday's day folders, for both local and UTC dates.
    public func recentFiles(now: Date = Date()) -> Set<URL> {
        var local = Calendar(identifier: .gregorian)
        local.timeZone = .current
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC") ?? .current
        let days = [now, now.addingTimeInterval(-86_400)]
        let folders = Set(days.flatMap { day in
            [local, utc].map { calendar -> URL in
                let parts = calendar.dateComponents([.year, .month, .day], from: day)
                return canonicalDirectory
                    .appendingPathComponent(String(format: "%04d", parts.year ?? 0))
                    .appendingPathComponent(String(format: "%02d", parts.month ?? 0))
                    .appendingPathComponent(String(format: "%02d", parts.day ?? 0))
            }
        })
        return Set(folders.flatMap { folder in
            (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        })
    }

    public func latestUpdates(
        since cutoff: Date, now: Date = Date(), changedFiles: Set<URL>? = nil
    ) -> [CodexProgress] {
        guard now >= cutoff else { return [] }
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .isRegularFileKey]
        // Recover recent messages after a stream overflow without replaying older history.
        let directory = canonicalDirectory
        let files = changedFiles ?? Set(FileManager.default.enumerator(
            at: directory, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles]
        )?.compactMap { $0 as? URL } ?? [])
        return files.compactMap { url -> CodexProgress? in
            guard url.lastPathComponent.hasPrefix("rollout-"), url.pathExtension == "jsonl",
                  let resolved = canonicalURL(url), resolved.pathComponents.starts(with: directory.pathComponents),
                  let values = try? url.resourceValues(forKeys: keys), values.isRegularFile == true,
                  let modified = values.contentModificationDate, modified >= cutoff else { return nil }
            return try? latestUpdate(in: resolved, since: cutoff, now: now)
        }
        .sorted { $0.timestamp < $1.timestamp }
    }

    private func canonicalURL(_ url: URL) -> URL? {
        url.withUnsafeFileSystemRepresentation { path in
            guard let path, let resolved = realpath(path, nil) else { return nil }
            defer { free(resolved) }
            return URL(fileURLWithPath: String(cString: resolved))
        }
    }

    private func latestUpdate(in url: URL, since cutoff: Date, now: Date) throws -> CodexProgress? {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        let size = try file.seekToEnd()
        let head = try read(file, offset: 0, count: Int(min(size, 128 * 1024)))
        guard let end = head.firstIndex(of: 10),
              let metadata = record(head[..<end]), metadata["type"] as? String == "session_meta",
              let payload = metadata["payload"] as? [String: Any],
              let source = payload["source"] as? String,
              ["cli", "vscode", "exec", "appServer", "app_server", "desktop"].contains(source),
              payload["thread_source"] == nil || payload["thread_source"] as? String == "user",
              let sessionID = payload["id"] as? String, !sessionID.isEmpty else { return nil }

        let tailSize = min(size, 256 * 1024)
        let tail = try read(file, offset: size - tailSize, count: Int(tailSize))
        var lines = tail.split(separator: 10, omittingEmptySubsequences: false).dropLast()
        if size > tailSize { lines = lines.dropFirst() }

        let timestampFormat = ISO8601DateFormatter()
        timestampFormat.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let wholeSeconds = ISO8601DateFormatter()
        for line in lines.reversed() where line.count < 64 * 1024 {
            guard let item = record(line), item["type"] as? String == "response_item",
                  let message = item["payload"] as? [String: Any],
                  message["type"] as? String == "message", message["role"] as? String == "assistant",
                  let rawTimestamp = item["timestamp"] as? String,
                  let timestamp = timestampFormat.date(from: rawTimestamp) ?? wholeSeconds.date(from: rawTimestamp),
                  timestamp >= cutoff, timestamp <= now,
                  let content = message["content"] as? [[String: Any]] else { continue }

            let rawText = content.compactMap { part in
                part["type"] as? String == "output_text" ? part["text"] as? String : nil
            }.joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
            let text = MarkdownBlockParser.previewText(for: MarkdownBlockParser.parse(rawText))
            guard !text.isEmpty else { continue }
            let project = (payload["cwd"] as? String).map { URL(fileURLWithPath: $0).lastPathComponent }
            let preview = text.count > 300 ? String(text.prefix(299)) + "…" : text
            let body = rawText.count > 20_000 ? String(rawText.prefix(19_999)) + "…" : rawText
            return CodexProgress(sessionID: sessionID, project: project ?? "", message: preview, body: body, timestamp: timestamp)
        }
        return nil
    }

    private func read(_ file: FileHandle, offset: UInt64, count: Int) throws -> Data {
        try file.seek(toOffset: offset)
        return try file.read(upToCount: count) ?? Data()
    }

    private func record(_ line: Data.SubSequence) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: Data(line))) as? [String: Any]
    }
}
