import XCTest
@testable import OverwatchrCore

final class FocusHintResolverTests: XCTestCase {
    func testGhosttyCodexQueriesIncludeSessionHints() {
        let event = AgentEvent(
            agentID: "codex-019cf0bb-722c-7bf3-9ce3-66bca920e9b9",
            project: "espclaw",
            status: .needsInput,
            terminal: "ghostty",
            title: "espclaw"
        )

        XCTAssertEqual(
            FocusHintResolver.queries(for: event),
            [
                "espclaw",
                "019cf0bb-722c-7bf3-9ce3-66bca920e9b9",
                "codex resume 019cf0bb-722c-7bf3-9ce3-66bca920e9b9"
            ]
        )
    }

    func testNonGhosttyQueriesDoNotAddCodexResumePrefix() {
        let event = AgentEvent(
            agentID: "codex-sess-123",
            project: "landing",
            status: .needsInput,
            terminal: "iTerm2",
            title: "landing"
        )

        XCTAssertEqual(
            FocusHintResolver.queries(for: event),
            ["landing", "sess-123"]
        )
    }
}
