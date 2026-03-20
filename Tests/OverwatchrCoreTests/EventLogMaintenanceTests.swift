import Foundation
import XCTest
@testable import OverwatchrCore

final class EventLogMaintenanceTests: XCTestCase {
    func testStatsReportValidMalformedAndActiveCounts() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let fileURL = root.appendingPathComponent("events.jsonl")
        let contents = """
        {"agent_id":"copy","project":"landing","status":"needs_input","timestamp":100}
        not-json
        {"agent_id":"copy","project":"landing","status":"done","timestamp":101}
        {"agent_id":"api","project":"backend","status":"error","timestamp":102}
        """
        try contents.write(to: fileURL, atomically: true, encoding: .utf8)

        let stats = try EventLogMaintenance(store: EventStore(fileURL: fileURL)).stats()

        XCTAssertEqual(stats.totalEvents, 3)
        XCTAssertEqual(stats.malformedLines, 1)
        XCTAssertEqual(stats.uniqueAgents, 2)
        XCTAssertEqual(stats.activeAlerts, 1)
        XCTAssertEqual(stats.oldestTimestamp, 100)
        XCTAssertEqual(stats.newestTimestamp, 102)
        XCTAssertGreaterThan(stats.fileSizeBytes, 0)
    }

    func testCompactKeepsOnlyLatestEventPerAgentAndWritesBackup() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let fileURL = root.appendingPathComponent("events.jsonl")
        let store = EventStore(fileURL: fileURL)
        try store.append(AgentEvent(agentID: "copy", project: "landing", status: .needsInput, timestamp: 100))
        try store.append(AgentEvent(agentID: "copy", project: "landing", status: .done, timestamp: 101))
        try store.append(AgentEvent(agentID: "api", project: "backend", status: .error, timestamp: 102))

        let result = try EventLogMaintenance(store: store).compact()
        let retained = try store.loadAll()

        XCTAssertEqual(result.originalCount, 3)
        XCTAssertEqual(result.retainedCount, 2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.backupFileURL.path))
        XCTAssertEqual(retained.map(\.agentID), ["copy", "api"])
        XCTAssertEqual(retained.map(\.status), [.done, .error])
    }

    func testPruneDropsOldHistoryButKeepsLatestEventPerAgent() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let fileURL = root.appendingPathComponent("events.jsonl")
        let store = EventStore(fileURL: fileURL)
        try store.append(AgentEvent(agentID: "old-agent", project: "legacy", status: .needsInput, timestamp: 100))
        try store.append(AgentEvent(agentID: "recent-agent", project: "fresh", status: .needsInput, timestamp: 190))
        try store.append(AgentEvent(agentID: "recent-agent", project: "fresh", status: .done, timestamp: 195))

        let result = try EventLogMaintenance(store: store).prune(
            olderThan: 20,
            now: Date(timeIntervalSince1970: 200)
        )
        let retained = try store.loadAll()

        XCTAssertEqual(result.originalCount, 3)
        XCTAssertEqual(result.retainedCount, 3)
        XCTAssertEqual(retained.map(\.agentID), ["old-agent", "recent-agent", "recent-agent"])
        XCTAssertEqual(retained.map(\.timestamp), [100, 190, 195])
    }

    func testParseAgeSupportsCommonSuffixes() {
        XCTAssertEqual(EventLogMaintenance.parseAge("30d"), 30 * 86_400)
        XCTAssertEqual(EventLogMaintenance.parseAge("12h"), 12 * 3_600)
        XCTAssertEqual(EventLogMaintenance.parseAge("15m"), 15 * 60)
        XCTAssertEqual(EventLogMaintenance.parseAge("45s"), 45)
        XCTAssertEqual(EventLogMaintenance.parseAge("7"), 7 * 86_400)
        XCTAssertNil(EventLogMaintenance.parseAge("abc"))
    }

    private func makeTemporaryDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}
