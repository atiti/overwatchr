import XCTest
@testable import OverwatchrCore

@MainActor
final class EventWatcherTests: XCTestCase {
    func testBootstrapIgnoresAlertsFromBeforeCurrentBoot() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = EventStore(fileURL: root.appendingPathComponent("events.jsonl"))
        try store.append(AgentEvent(agentID: "stale", status: .needsInput, timestamp: 99))
        try store.append(AgentEvent(agentID: "current", status: .error, timestamp: 101))

        var receivedUpdate: EventWatcherUpdate?
        let watcher = EventWatcher(
            store: store,
            interval: 60,
            minimumEventTimestamp: 100
        ) { update in
            receivedUpdate = update
        }

        watcher.start()
        defer { watcher.stop() }

        XCTAssertEqual(receivedUpdate?.newEvents, [])
        XCTAssertEqual(receivedUpdate?.currentAlerts.map(\.agentID), ["current"])
    }

    func testSystemBootFallbackUsesWallClockAndUptime() {
        let now = Date(timeIntervalSince1970: 1_000)

        XCTAssertEqual(SystemBootTime.fallbackTimestamp(now: now, systemUptime: 250), 750)
    }
}
