import Foundation

enum FocusHintResolver {
    static func queries(for event: AgentEvent) -> [String] {
        var queries: [String] = []

        append(event.title, to: &queries)
        append(event.project, to: &queries)

        guard let sessionIdentifier = sessionIdentifier(from: event.agentID) else {
            return queries
        }

        append(sessionIdentifier, to: &queries)

        if TerminalApplication(name: event.terminal ?? "") == .ghostty,
           event.agentID.hasPrefix("codex-") {
            append("codex resume \(sessionIdentifier)", to: &queries)
        }

        return queries
    }

    private static func sessionIdentifier(from agentID: String) -> String? {
        for prefix in ["codex-", "claude-", "opencode-"] where agentID.hasPrefix(prefix) {
            let suffix = String(agentID.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            return suffix.isEmpty ? nil : suffix
        }

        return nil
    }

    private static func append(_ value: String?, to queries: inout [String]) {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty,
              !queries.contains(trimmed) else {
            return
        }

        queries.append(trimmed)
    }
}
