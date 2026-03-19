import XCTest
@testable import OverwatchrCore

final class WindowTitleMatcherTests: XCTestCase {
    func testPrefersNormalizedExactWindowMatches() {
        let candidates = [
            "workspace - zsh",
            "landing copy - codex",
            "landing / copy"
        ]

        let bestIndex = WindowTitleMatcher.bestMatchIndex(for: "landing copy", in: candidates)

        XCTAssertEqual(bestIndex, 2)
    }

    func testReturnsNilWhenThereIsNoReasonableMatch() {
        XCTAssertNil(WindowTitleMatcher.bestMatchIndex(for: "payments", in: ["landing copy", "api bugfix"]))
    }
}
