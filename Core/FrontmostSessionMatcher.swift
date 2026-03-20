import Foundation

public struct FrontmostSessionContext: Equatable, Sendable {
    public let terminalName: String
    public let ttyPath: String?
    public let title: String?
    public let workingDirectoryBasename: String?

    public init(
        terminalName: String,
        ttyPath: String? = nil,
        title: String? = nil,
        workingDirectoryBasename: String? = nil
    ) {
        self.terminalName = terminalName
        self.ttyPath = ttyPath?.trimmedNilIfBlank
        self.title = title?.trimmedNilIfBlank
        self.workingDirectoryBasename = workingDirectoryBasename?.trimmedNilIfBlank
    }
}

public enum FrontmostSessionMatcher {
    public static func matches(event: AgentEvent, context: FrontmostSessionContext) -> Bool {
        let eventTerminal = TerminalApplication(name: event.terminal ?? "")
        let contextTerminal = TerminalApplication(name: context.terminalName)

        guard eventTerminal == contextTerminal else {
            return false
        }

        if let eventTTY = event.tty?.trimmedNilIfBlank,
           let contextTTY = context.ttyPath?.trimmedNilIfBlank {
            return eventTTY == contextTTY
        }

        if let eventTitle = event.title?.trimmedNilIfBlank,
           let contextTitle = context.title?.trimmedNilIfBlank,
           WindowTitleMatcher.score(candidate: contextTitle, query: eventTitle) != nil {
            return true
        }

        if eventTerminal == .ghostty,
           let project = event.project?.trimmedNilIfBlank,
           let workingDirectoryBasename = context.workingDirectoryBasename?.trimmedNilIfBlank,
           project.caseInsensitiveCompare(workingDirectoryBasename) == .orderedSame {
            return true
        }

        return false
    }
}

private extension String {
    var trimmedNilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
