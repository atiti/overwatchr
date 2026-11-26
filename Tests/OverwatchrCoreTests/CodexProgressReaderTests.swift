import Foundation
import XCTest
@testable import OverwatchrCore

final class CodexProgressReaderTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-11-26T10:01:00Z")!

    func testShowsLatestAssistantMessageFromMainSessions() throws {
        try withSessionDirectory { directory in
            try writeRollout("main", source: "vscode", threadSource: "user", lines: [
                message("Older update", time: "2026-11-26T10:00:45.000Z"),
                message("  Build passed.\nChecking the release. ", time: "2026-11-26T10:00:55.100Z"),
            ], in: directory)
            try writeRollout("untagged", source: "vscode", lines: [
                message("Model without a phase tag", phase: nil, time: "2026-11-26T10:00:57Z")
            ], in: directory)
            try writeRollout("finished", source: "vscode", lines: [
                message("Working", time: "2026-11-26T10:00:50Z"),
                message("All done: PR merged.", phase: "final_answer", time: "2026-11-26T10:00:56Z")
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
            XCTAssertEqual(updates.map(\.sessionID), ["main", "finished", "untagged"])
            XCTAssertEqual(updates.first?.project, "overwatchr")
            XCTAssertEqual(updates.first?.message, "Build passed. Checking the release.")
            XCTAssertEqual(updates.map(\.message).suffix(2), ["All done: PR merged.", "Model without a phase tag"])
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

    func testRecentFilesCoversTodayAndYesterdayOnly() throws {
        try withSessionDirectory { directory in
            for day in ["2026/11/26", "2026/11/25", "2026/11/20"] {
                let folder = directory.appendingPathComponent(day)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try Data().write(to: folder.appendingPathComponent("rollout-\(day.suffix(2)).jsonl"))
            }
            let names = CodexProgressReader(sessionsDirectory: directory).recentFiles(now: now)
                .map(\.lastPathComponent).sorted()
            XCTAssertEqual(names, ["rollout-25.jsonl", "rollout-26.jsonl"])
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

    private func message(_ text: String, phase: String? = "commentary", time: String) -> [String: Any] {
        var payload: [String: Any] = [
            "type": "message",
            "role": "assistant",
            "content": [["type": "output_text", "text": text]]
        ]
        payload["phase"] = phase
        return ["type": "response_item", "timestamp": time, "payload": payload]
    }
}
