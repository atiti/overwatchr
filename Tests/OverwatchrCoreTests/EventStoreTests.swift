import Foundation
import XCTest
@testable import OverwatchrCore

final class EventStoreTests: XCTestCase {
    func testAppendAndReadRoundTrip() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = temporaryDirectory.appendingPathComponent("events.jsonl")
        let store = EventStore(fileURL: fileURL)

        let first = AgentEvent(
            agentID: "copy",
            project: "landing",
            status: .needsInput,
            terminal: "ghostty",
            title: "landing:copy",
            timestamp: 123
        )
        let second = AgentEvent(
            agentID: "copy",
            project: "landing",
            status: .done,
            timestamp: 124
        )

        try store.append(first)
        let partial = try store.readEvents(from: 0)
        try store.append(second)
        let tail = try store.readEvents(from: partial.nextOffset)

        XCTAssertEqual(partial.events, [first])
        XCTAssertEqual(tail.events, [second])
        XCTAssertEqual(try store.loadAll(), [first, second])
    }

    func testReadSkipsMalformedLines() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = temporaryDirectory.appendingPathComponent("events.jsonl")
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)

        let contents = """
        {"agent_id":"one","project":"demo","status":"needs_input","timestamp":1}
        not-json
        {"agent_id":"two","project":"demo","status":"done","timestamp":2}
        """
        try contents.write(to: fileURL, atomically: true, encoding: .utf8)

        let store = EventStore(fileURL: fileURL)
        let batch = try store.readEvents(from: 0)

        XCTAssertEqual(batch.events.map(\.agentID), ["one", "two"])
        XCTAssertEqual(batch.events.map(\.status), [.needsInput, .done])
    }
}
