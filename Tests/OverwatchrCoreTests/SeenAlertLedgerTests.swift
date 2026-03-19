import XCTest
@testable import OverwatchrCore

final class SeenAlertLedgerTests: XCTestCase {
    func testSeenAlertIsHiddenUntilNewerEventArrives() {
        var ledger = SeenAlertLedger()
        let original = AgentEvent(agentID: "copy", project: "landing", status: .needsInput, timestamp: 100)
        let newer = AgentEvent(agentID: "copy", project: "landing", status: .error, timestamp: 200)

        ledger.markSeen(original)

        XCTAssertTrue(ledger.visibleAlerts(from: [original]).isEmpty)
        XCTAssertEqual(ledger.visibleAlerts(from: [newer]), [newer])
    }

    func testSeenStateOnlyAppliesToMatchingAgent() {
        var ledger = SeenAlertLedger()
        let copyAlert = AgentEvent(agentID: "copy", project: "landing", status: .needsInput, timestamp: 100)
        let apiAlert = AgentEvent(agentID: "api", project: "backend", status: .error, timestamp: 100)

        ledger.markSeen(copyAlert)

        XCTAssertTrue(ledger.visibleAlerts(from: [copyAlert]).isEmpty)
        XCTAssertEqual(ledger.visibleAlerts(from: [apiAlert]), [apiAlert])
    }
}
