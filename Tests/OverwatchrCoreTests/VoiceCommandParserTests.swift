import XCTest
@testable import OverwatchrCore

final class VoiceCommandParserTests: XCTestCase {
    func testPlainDictationDoesNotSubmit() {
        let result = VoiceCommandParser.parse("Looks good to me", submitMode: .stripAndSubmit)

        XCTAssertEqual(result.insertionText, "Looks good to me")
        XCTAssertFalse(result.shouldSubmit)
    }

    func testPressEnterAtEndSubmitsAndStripsPhrase() {
        let result = VoiceCommandParser.parse("Looks good press enter", submitMode: .stripAndSubmit)

        XCTAssertEqual(result.insertionText, "Looks good")
        XCTAssertTrue(result.shouldSubmit)
    }

    func testPressEnterWithPunctuationAndCasingSubmits() {
        let result = VoiceCommandParser.parse("Ship it, PRESS ENTER.", submitMode: .stripAndSubmit)

        XCTAssertEqual(result.insertionText, "Ship it")
        XCTAssertTrue(result.shouldSubmit)
    }

    func testDisabledSubmitModeKeepsCommandPhrase() {
        let result = VoiceCommandParser.parse("Looks good press enter", submitMode: .disabled)

        XCTAssertEqual(result.insertionText, "Looks good press enter")
        XCTAssertFalse(result.shouldSubmit)
    }

    func testTerminalCommandPhraseAloneDoesNotSubmitByDefault() {
        let result = VoiceCommandParser.parse("Press enter", submitMode: .stripAndSubmit)

        XCTAssertEqual(result.insertionText, "Press enter")
        XCTAssertFalse(result.shouldSubmit)
    }

    func testFalsePositiveKeepsLiteralPhraseInMiddle() {
        let result = VoiceCommandParser.parse("Can you literally write press enter in the docs", submitMode: .stripAndSubmit)

        XCTAssertEqual(result.insertionText, "Can you literally write press enter in the docs")
        XCTAssertFalse(result.shouldSubmit)
    }

    func testKeepAndSubmitModePreservesCommandPhrase() {
        let result = VoiceCommandParser.parse("Looks good press enter", submitMode: .keepAndSubmit)

        XCTAssertEqual(result.insertionText, "Looks good press enter")
        XCTAssertTrue(result.shouldSubmit)
    }
}
