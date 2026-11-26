import Foundation

/// One block-level element of a chat message.
public enum MarkdownBlock: Equatable, Sendable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case listItem(marker: String, text: String, depth: Int)
    case quote(String)
    case code(language: String, text: String)
    case table([String])
    case rule
}

/// Splits Markdown into the block types shown in progress cards.
/// Inline styling such as bold, code and links is left in the text for the view to render.
public enum MarkdownBlockParser {
    public static func parse(_ markdown: String) -> [MarkdownBlock] {
        var parser = Parser()
        for line in markdown.split(separator: "\n", omittingEmptySubsequences: false) {
            parser.consume(String(line))
        }
        return parser.finish()
    }

    /// A single line of plain text for the collapsed card.
    public static func previewText(for blocks: [MarkdownBlock]) -> String {
        blocks.map { block -> String in
            switch block {
            case .heading(_, let text), .paragraph(let text), .quote(let text), .code(_, let text):
                return text
            case .listItem(_, let text, _):
                return "• " + text
            case .table(let rows):
                return rows.joined(separator: " ")
            case .rule:
                return ""
            }
        }
        .joined(separator: " ")
        .split(whereSeparator: \.isWhitespace)
        .joined(separator: " ")
    }

    private struct Parser {
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var quote: [String] = []
        var table: [String] = []
        var fence: (language: String, lines: [String])?

        mutating func consume(_ line: String) {
            if var openFence = fence {
                if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    blocks.append(.code(language: openFence.language, text: openFence.lines.joined(separator: "\n")))
                    fence = nil
                } else {
                    openFence.lines.append(line)
                    fence = openFence
                }
                return
            }

            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                flushText()
                fence = (String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces), [])
            } else if trimmed.isEmpty {
                flushText()
            } else if let heading = Self.heading(in: trimmed) {
                flushText()
                blocks.append(heading)
            } else if Self.isRule(trimmed) {
                flushText()
                blocks.append(.rule)
            } else if trimmed.hasPrefix(">") {
                flushParagraph()
                flushTable()
                quote.append(String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces))
            } else if trimmed.hasPrefix("|") {
                flushParagraph()
                flushQuote()
                table.append(trimmed)
            } else if let item = Self.listItem(in: line) {
                flushText()
                blocks.append(item)
            } else if line.hasPrefix(" "), appendToLastListItem(trimmed) {
                return
            } else {
                flushQuote()
                flushTable()
                paragraph.append(trimmed)
            }
        }

        mutating func finish() -> [MarkdownBlock] {
            if let openFence = fence {
                blocks.append(.code(language: openFence.language, text: openFence.lines.joined(separator: "\n")))
                fence = nil
            }
            flushText()
            return blocks
        }

        private mutating func appendToLastListItem(_ text: String) -> Bool {
            guard paragraph.isEmpty, quote.isEmpty, table.isEmpty,
                  case .listItem(let marker, let itemText, let depth)? = blocks.last else { return false }
            blocks[blocks.count - 1] = .listItem(marker: marker, text: itemText + " " + text, depth: depth)
            return true
        }

        private mutating func flushText() {
            flushParagraph()
            flushQuote()
            flushTable()
        }

        private mutating func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            blocks.append(.paragraph(paragraph.joined(separator: "\n")))
            paragraph = []
        }

        private mutating func flushQuote() {
            guard !quote.isEmpty else { return }
            blocks.append(.quote(quote.joined(separator: "\n")))
            quote = []
        }

        private mutating func flushTable() {
            guard !table.isEmpty else { return }
            blocks.append(.table(table))
            table = []
        }

        private static func heading(in line: String) -> MarkdownBlock? {
            let level = line.prefix(while: { $0 == "#" }).count
            guard (1...6).contains(level), line.dropFirst(level).first == " " else { return nil }
            let text = line.dropFirst(level).trimmingCharacters(in: .whitespaces)
            return text.isEmpty ? nil : .heading(level: level, text: text)
        }

        private static func isRule(_ line: String) -> Bool {
            guard line.count >= 3, let first = line.first, "-*_".contains(first) else { return false }
            return line.allSatisfy { $0 == first }
        }

        private static func listItem(in line: String) -> MarkdownBlock? {
            let indentation = line.prefix(while: { $0 == " " }).count
            let content = line.dropFirst(indentation)
            let depth = min(indentation / 2, 4)

            for bullet in ["- ", "* ", "+ "] where content.hasPrefix(bullet) {
                let text = content.dropFirst(bullet.count).trimmingCharacters(in: .whitespaces)
                if text.hasPrefix("[ ] ") { return .listItem(marker: "☐", text: String(text.dropFirst(4)), depth: depth) }
                if text.hasPrefix("[x] ") || text.hasPrefix("[X] ") {
                    return .listItem(marker: "☑", text: String(text.dropFirst(4)), depth: depth)
                }
                return text.isEmpty ? nil : .listItem(marker: "•", text: text, depth: depth)
            }

            let digits = content.prefix(while: \.isNumber)
            let rest = content.dropFirst(digits.count)
            guard !digits.isEmpty, digits.count <= 3, let separator = rest.first, ".)".contains(separator),
                  rest.dropFirst().first == " " else { return nil }
            let text = rest.dropFirst(2).trimmingCharacters(in: .whitespaces)
            return text.isEmpty ? nil : .listItem(marker: "\(digits).", text: text, depth: depth)
        }
    }
}
