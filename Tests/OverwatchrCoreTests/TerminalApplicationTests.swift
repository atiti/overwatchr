import XCTest
@testable import OverwatchrCore

final class TerminalApplicationTests: XCTestCase {
    func testGhosttyWorkingDirectoryFocusScriptMatchesBasename() {
        let script = TerminalApplication.ghostty.appleScriptWindowFocusCommand(
            matchingWorkingDirectoryBasename: "espclaw"
        )

        XCTAssertNotNil(script)
        XCTAssertTrue(script?.contains(#"working directory of t"#) == true)
        XCTAssertTrue(script?.contains(#"ends with ("/" & query)"#) == true)
        XCTAssertTrue(script?.contains(#"focus t"#) == true)
    }

    func testITermDoesNotExposeGhosttyWorkingDirectoryScript() {
        XCTAssertNil(TerminalApplication.iTerm.appleScriptWindowFocusCommand(
            matchingWorkingDirectoryBasename: "espclaw"
        ))
    }
}
