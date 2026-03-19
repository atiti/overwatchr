import XCTest
@testable import OverwatchrCore

final class AlertQueueTests: XCTestCase {
    func testLatestAlertWinsPerAgent() {
        var queue = AlertQueue()

        queue.apply(
            AgentEvent(
                agentID: "copy",
                project: "landing",
                status: .needsInput,
                terminal: "ghostty",
                title: "landing:copy",
                timestamp: 100
            )
        )
        queue.apply(
            AgentEvent(
                agentID: "copy",
                project: "landing",
                status: .error,
                terminal: "ghostty",
                title: "landing:copy",
                timestamp: 200
            )
        )

        XCTAssertEqual(queue.count, 1)
        XCTAssertEqual(queue.nextAlert?.status, .error)
        XCTAssertEqual(queue.nextAlert?.timestamp, 200)
    }

    func testDoneRemovesAlert() {
        var queue = AlertQueue()

        queue.apply(AgentEvent(agentID: "copy", project: "landing", status: .needsInput, timestamp: 100))
        queue.apply(AgentEvent(agentID: "copy", project: "landing", status: .done, timestamp: 200))

        XCTAssertEqual(queue.count, 0)
        XCTAssertNil(queue.nextAlert)
    }
}

