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
}

