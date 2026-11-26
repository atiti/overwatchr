import Foundation
import XCTest
@testable import OverwatchrCore

final class CodexProgressReaderTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-11-26T10:01:00Z")!

    func testShowsOnlyLatestNamedCommentaryFromMainSessions() throws {
        try withSessionDirectory { directory in
            try writeRollout("main", source: "vscode", threadSource: "user", lines: [
                message("Older update", time: "2026-11-26T10:00:45.000Z"),
                message("  Build passed.\nChecking the release. ", time: "2026-11-26T10:00:55.100Z"),
                message("Final answer", phase: "final_answer", time: "2026-11-26T10:00:56Z")
            ], in: directory)
            try writeRollout("child", source: ["subagent": "review"], lines: [
                message("Child commentary", time: "2026-11-26T10:00:58Z")
            ], in: directory)
            try writeRollout("guardian", source: "vscode", threadSource: "guardian_review", lines: [
                message("Guardian commentary", time: "2026-11-26T10:00:58Z")
            ], in: directory)
            try writeRollout("stale", source: "cli", lines: [
                message("Old commentary", time: "2026-11-26T09:50:00Z")
            ], in: directory)

            let updates = CodexProgressReader(sessionsDirectory: directory)
                .latestUpdates(since: now.addingTimeInterval(-30), now: now)
            XCTAssertEqual(updates.map(\.sessionID), ["main"])
            XCTAssertEqual(updates.first?.project, "overwatchr")
            XCTAssertEqual(updates.first?.message, "Build passed. Checking the release.")
        }
    }

    func testReadsRecentCommentaryFromLongRunningSessionAndIgnoresPartialWrite() throws {
        try withSessionDirectory { directory in
            let olderDirectory = directory.appendingPathComponent("2026/10/01")
            try FileManager.default.createDirectory(at: olderDirectory, withIntermediateDirectories: true)
            let update = message("Latest complete update", time: "2026-11-26T10:00:56Z")
            try writeRollout("resumed", source: "cli", lines: [
                ["type": "tool", "payload": String(repeating: "x", count: 300_000)],
                update
            ], partial: "{\"type\":", in: olderDirectory)

            let updates = CodexProgressReader(sessionsDirectory: directory)
                .latestUpdates(since: now.addingTimeInterval(-30), now: now)
            XCTAssertEqual(updates.map(\.message), ["Latest complete update"])
        }
    }

    private func withSessionDirectory(_ body: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory)
    }

    private func writeRollout(
        _ id: String,
        source: Any,
        threadSource: String? = nil,
        lines: [[String: Any]],
        partial: String = "",
        in directory: URL
    ) throws {
        var metadata: [String: Any] = ["id": id, "cwd": "/test/overwatchr", "source": source]
        metadata["thread_source"] = threadSource
        let url = directory.appendingPathComponent("rollout-\(id).jsonl")
        var data = Data()
        for line in [["type": "session_meta", "payload": metadata]] + lines {
            data.append(try JSONSerialization.data(withJSONObject: line))
            data.append(10)
        }
        data.append(contentsOf: partial.utf8)
        try data.write(to: url)
        try FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: url.path)
    }

    private func message(_ text: String, phase: String = "commentary", time: String) -> [String: Any] {
        [
            "type": "response_item",
            "timestamp": time,
            "payload": [
                "type": "message",
                "role": "assistant",
                "phase": phase,
                "content": [["type": "output_text", "text": text]]
            ]
        ]
    }
}
