import Foundation

public struct SeenAlertLedger: Codable, Equatable, Sendable {
    private var lastSeenTimestampByAgentID: [String: TimeInterval]

    public init(lastSeenTimestampByAgentID: [String: TimeInterval] = [:]) {
        self.lastSeenTimestampByAgentID = lastSeenTimestampByAgentID
    }

    public func isSeen(_ event: AgentEvent) -> Bool {
        guard let seenTimestamp = lastSeenTimestampByAgentID[event.agentID] else {
            return false
        }

        return seenTimestamp >= event.timestamp
    }

    public func visibleAlerts<S: Sequence>(from alerts: S) -> [AgentEvent] where S.Element == AgentEvent {
        alerts.filter { !isSeen($0) }
    }

    public mutating func markSeen(_ event: AgentEvent) {
        let currentTimestamp = lastSeenTimestampByAgentID[event.agentID] ?? .zero
        lastSeenTimestampByAgentID[event.agentID] = max(currentTimestamp, event.timestamp)
    }

    public mutating func markSeen<S: Sequence>(_ events: S) where S.Element == AgentEvent {
        for event in events {
            markSeen(event)
        }
    }
}
