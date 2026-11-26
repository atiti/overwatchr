import Foundation

public struct HerdrTarget: Equatable, Sendable {
    public let socketPath: String
    public let paneID: String
}

/// Jumps to a pane in a running Herdr session through Herdr's socket API.
public enum HerdrFocus {
    public typealias Request = (_ socketPath: String, _ method: String, _ params: [String: Any]) throws -> [String: Any]

    /// Sockets worth asking, most specific first.
    public static func socketPaths(
        event: AgentEvent,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [String] {
        let root = home.appendingPathComponent(".config/herdr")
        let sessions = (try? FileManager.default.contentsOfDirectory(
            at: root.appendingPathComponent("sessions"), includingPropertiesForKeys: nil
        )) ?? []
        let candidates = [event.herdrSocketPath, environment["HERDR_SOCKET_PATH"]].compactMap { $0 }
            + sessions.map { $0.appendingPathComponent("herdr.sock").path }.sorted()
            + [root.appendingPathComponent("herdr.sock").path]
        var seen = Set<String>()
        return candidates.filter { !$0.isEmpty && seen.insert($0).inserted
            && FileManager.default.fileExists(atPath: $0) }
    }

    /// The chat's ID as Herdr reports it, taken from an agent ID such as `codex-<uuid>`.
    public static func agentSessionID(from agentID: String) -> String? {
        guard let dash = agentID.firstIndex(of: "-") else { return nil }
        let raw = String(agentID[agentID.index(after: dash)...])
        return raw.isEmpty ? nil : raw
    }

    public static func locate(
        event: AgentEvent, socketPaths: [String], request: Request
    ) -> HerdrTarget? {
        let sessionID = agentSessionID(from: event.agentID)?.lowercased()
        for socketPath in socketPaths {
            guard let result = try? request(socketPath, "pane.list", [:]),
                  let panes = result["panes"] as? [[String: Any]] else { continue }
            func paneID(_ pane: [String: Any]) -> String? { pane["pane_id"] as? String }
            func owner(_ pane: [String: Any]) -> String? {
                ((pane["agent_session"] as? [String: Any])?["value"] as? String)?.lowercased()
            }

            if let sessionID, let pane = panes.first(where: { owner($0) == sessionID }), let id = paneID(pane) {
                return HerdrTarget(socketPath: socketPath, paneID: id)
            }
            // A hook that ran inside the pane knows its address. Trust it unless
            // the pane now belongs to a different chat.
            if let recorded = event.herdrPaneID, socketPath == event.herdrSocketPath,
               let pane = panes.first(where: { paneID($0) == recorded }),
               owner(pane) == nil || owner(pane) == sessionID {
                return HerdrTarget(socketPath: socketPath, paneID: recorded)
            }
        }
        return nil
    }

    /// Focuses the alert's pane. Returns false when no Herdr pane belongs to the alert.
    public static func focus(event: AgentEvent) throws -> Bool {
        guard let target = locate(
            event: event, socketPaths: socketPaths(event: event), request: send
        ) else { return false }
        _ = try send(socketPath: target.socketPath, method: "pane.focus", params: ["pane_id": target.paneID])
        return true
    }

    public static func send(socketPath: String, method: String, params: [String: Any]) throws -> [String: Any] {
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw FocusError.activationFailed("Cannot open a Herdr connection.") }
        defer { close(descriptor) }

        var timeout = timeval(tv_sec: 2, tv_usec: 0)
        setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(descriptor, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard socketPath.utf8.count < capacity else {
            throw FocusError.activationFailed("The Herdr socket path is too long.")
        }
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            buffer.copyBytes(from: Array(socketPath.utf8) + [0])
        }
        let connected = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else { throw FocusError.activationFailed("Herdr is not reachable on \(socketPath).") }

        let body = try JSONSerialization.data(withJSONObject: ["id": "overwatchr", "method": method, "params": params])
        let line = body + Data([10])
        let written = line.withUnsafeBytes { write(descriptor, $0.baseAddress, line.count) }
        guard written == line.count else { throw FocusError.activationFailed("Cannot send the request to Herdr.") }

        var response = Data()
        var chunk = [UInt8](repeating: 0, count: 65_536)
        while !response.contains(10), response.count < 8_000_000 {
            let count = read(descriptor, &chunk, chunk.count)
            if count <= 0 { break }
            response.append(contentsOf: chunk[0..<count])
        }
        guard let reply = try JSONSerialization.jsonObject(
            with: response.prefix(while: { $0 != 10 })
        ) as? [String: Any] else {
            throw FocusError.activationFailed("Herdr sent an unreadable reply.")
        }
        if let error = reply["error"] as? [String: Any] {
            throw FocusError.activationFailed(error["message"] as? String ?? "Herdr rejected the request.")
        }
        return reply["result"] as? [String: Any] ?? [:]
    }
}
