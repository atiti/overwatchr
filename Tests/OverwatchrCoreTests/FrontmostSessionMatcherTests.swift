import XCTest
@testable import OverwatchrCore

final class FrontmostSessionMatcherTests: XCTestCase {
    func testMatchesExactTTYWithinSameTerminal() {
        let event = AgentEvent(
            agentID: "codex-session-1",
            project: "workspace",
            status: .needsInput,
            terminal: "iTerm2",
            tty: "/dev/ttys099",
            title: "workspace · ttys099",
            timestamp: 1
        )

        let context = FrontmostSessionContext(
            terminalName: "iTerm2",
            ttyPath: "/dev/ttys099",
            title: "workspace · ttys101"
        )

        XCTAssertTrue(FrontmostSessionMatcher.matches(event: event, context: context))
    }

    func testMatchesTitleWhenTTYUnavailable() {
        let event = AgentEvent(
            agentID: "codex-session-1",
            project: "workspace",
            status: .needsInput,
            terminal: "ghostty",
            title: "workspace · ttys099",
            timestamp: 1
        )

        let context = FrontmostSessionContext(
            terminalName: "ghostty",
            title: "workspace · ttys099"
        )

        XCTAssertTrue(FrontmostSessionMatcher.matches(event: event, context: context))
    }

    func testGhosttyFallsBackToWorkingDirectoryOnlyWhenNeeded() {
        let event = AgentEvent(
            agentID: "codex-session-1",
            project: "workspace",
            status: .needsInput,
            terminal: "ghostty",
            title: nil,
            timestamp: 1
        )

        let context = FrontmostSessionContext(
            terminalName: "ghostty",
            workingDirectoryBasename: "workspace"
        )

        XCTAssertTrue(FrontmostSessionMatcher.matches(event: event, context: context))
    }

    func testDoesNotMatchDifferentTerminalEvenWithSameTitle() {
        let event = AgentEvent(
            agentID: "codex-session-1",
            project: "workspace",
            status: .needsInput,
            terminal: "Terminal",
            title: "workspace · ttys099",
            timestamp: 1
        )

        let context = FrontmostSessionContext(
            terminalName: "ghostty",
            title: "workspace · ttys099"
        )

        XCTAssertFalse(FrontmostSessionMatcher.matches(event: event, context: context))
    }
}
