import Foundation

public enum AgentStatus: String, Codable, CaseIterable, Sendable {
    case needsInput = "needs_input"
    case done
    case error

    public var requiresAttention: Bool {
        switch self {
        case .needsInput, .error:
            return true
        case .done:
            return false
        }
    }

    public var label: String {
        switch self {
        case .needsInput:
            return "Needs Input"
        case .done:
            return "Done"
        case .error:
            return "Error"
        }
    }
}

public struct AgentEvent: Codable, Equatable, Identifiable, Sendable {
    public let agentID: String
    public let project: String?
    public let status: AgentStatus
    public let terminal: String?
    public let tty: String?
    public let title: String?
    public let timestamp: TimeInterval

    public init(
        agentID: String,
        project: String? = nil,
        status: AgentStatus,
        terminal: String? = nil,
        tty: String? = nil,
        title: String? = nil,
        timestamp: TimeInterval = Date().timeIntervalSince1970
    ) {
        self.agentID = agentID
        self.project = project?.nilIfBlank
        self.status = status
        self.terminal = terminal?.nilIfBlank
        self.tty = tty?.nilIfBlank
        self.title = title?.nilIfBlank
        self.timestamp = timestamp
    }

    public var id: String {
        "\(agentID)-\(timestamp)-\(status.rawValue)"
    }

    public var displayName: String {
        if let project {
            return "\(project) / \(agentID)"
        }
        return agentID
    }

    public var displaySubtitle: String {
        if let title {
            return title
        }
        if let terminal {
            return terminal
        }
        return status.label
    }

    enum CodingKeys: String, CodingKey {
        case agentID = "agent_id"
        case project
        case status
        case terminal
        case tty
        case title
        case timestamp
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
