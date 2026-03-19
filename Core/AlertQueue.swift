import Foundation

public struct AlertQueue: Sendable {
    private var latestByAgentID: [String: AgentEvent] = [:]

    public init() {}

    public mutating func apply(_ event: AgentEvent) {
        if event.status.requiresAttention {
            latestByAgentID[event.agentID] = event
        } else {
            latestByAgentID.removeValue(forKey: event.agentID)
        }
    }

    public mutating func apply<S: Sequence>(_ events: S) where S.Element == AgentEvent {
        for event in events {
            apply(event)
        }
    }

    public var alerts: [AgentEvent] {
        latestByAgentID.values.sorted { lhs, rhs in
            lhs.timestamp > rhs.timestamp
        }
    }

    public var count: Int {
        latestByAgentID.count
    }

    public var nextAlert: AgentEvent? {
        alerts.first
    }
}

