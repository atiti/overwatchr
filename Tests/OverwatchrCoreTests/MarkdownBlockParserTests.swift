import XCTest
@testable import OverwatchrCore

final class MarkdownBlockParserTests: XCTestCase {
    func testParsesHeadingsParagraphsAndLists() {
        let blocks = MarkdownBlockParser.parse("""
        # Result
        Tests passed.
        Merging now.

        - first
          continued
        - second
          - nested
        1. one
        2) two
        - [x] done
        """)
        XCTAssertEqual(blocks, [
            .heading(level: 1, text: "Result"),
            .paragraph("Tests passed.\nMerging now."),
            .listItem(marker: "•", text: "first continued", depth: 0),
            .listItem(marker: "•", text: "second", depth: 0),
            .listItem(marker: "•", text: "nested", depth: 1),
            .listItem(marker: "1.", text: "one", depth: 0),
            .listItem(marker: "2.", text: "two", depth: 0),
            .listItem(marker: "☑", text: "done", depth: 0)
        ])
    }

    func testParsesCodeFencesQuotesTablesAndRules() {
        let blocks = MarkdownBlockParser.parse("""
        > careful
        > now
        ```swift
        let x = 1

        print(x)
        ```
        | a | b |
        | - | - |
        ---
        after
        """)
        XCTAssertEqual(blocks, [
            .quote("careful\nnow"),
            .code(language: "swift", text: "let x = 1\n\nprint(x)"),
            .table(["| a | b |", "| - | - |"]),
            .rule,
            .paragraph("after")
        ])
    }

    func testUnclosedFenceKeepsItsCodeAndPreviewIsOneLine() {
        let blocks = MarkdownBlockParser.parse("Intro\n```\nrun this")
        XCTAssertEqual(blocks, [.paragraph("Intro"), .code(language: "", text: "run this")])
        XCTAssertEqual(MarkdownBlockParser.previewText(for: blocks), "Intro run this")
        XCTAssertEqual(
            MarkdownBlockParser.previewText(for: MarkdownBlockParser.parse("**Done.**\n\n- a\n- b")),
            "**Done.** • a • b"
        )
    }
}
