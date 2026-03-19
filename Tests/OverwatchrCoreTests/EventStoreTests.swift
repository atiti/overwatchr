import Foundation
import XCTest
@testable import OverwatchrCore

final class EventStoreTests: XCTestCase {
    func testAppendAndReadRoundTrip() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = temporaryDirectory.appendingPathComponent("events.jsonl")
        let store = EventStore(fileURL: fileURL)

        let first = AgentEvent(
            agentID: "copy",
            project: "landing",
            status: .needsInput,
            terminal: "ghostty",
            title: "landing:copy",
            timestamp: 123
        )
        let second = AgentEvent(
            agentID: "copy",
            project: "landing",
            status: .done,
            timestamp: 124
        )

        try store.append(first)
        let partial = try store.readEvents(from: 0)
        try store.append(second)
        let tail = try store.readEvents(from: partial.nextOffset)

        XCTAssertEqual(partial.events, [first])
        XCTAssertEqual(tail.events, [second])
        XCTAssertEqual(try store.loadAll(), [first, second])
    }

    func testReadSkipsMalformedLines() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = temporaryDirectory.appendingPathComponent("events.jsonl")
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)

        let contents = """
        {"agent_id":"one","project":"demo","status":"needs_input","timestamp":1}
        not-json
        {"agent_id":"two","project":"demo","status":"done","timestamp":2}
        """
        try contents.write(to: fileURL, atomically: true, encoding: .utf8)

        let store = EventStore(fileURL: fileURL)
        let batch = try store.readEvents(from: 0)

        XCTAssertEqual(batch.events.map(\.agentID), ["one", "two"])
        XCTAssertEqual(batch.events.map(\.status), [.needsInput, .done])
    }

    func testConcurrentAppendsDoNotCorruptTheLog() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = temporaryDirectory.appendingPathComponent("events.jsonl")
        let storeA = EventStore(fileURL: fileURL)
        let group = DispatchGroup()
        let queue = DispatchQueue(label: "event-store-test", attributes: .concurrent)
        let lock = NSLock()
        var errors: [Error] = []
        let packageRootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let cliURL = packageRootURL.appendingPathComponent(".build/debug/overwatchr")

        for index in 0..<20 {
            group.enter()
            queue.async {
                defer { group.leave() }
                do {
                    try self.runCLIAppend(
                        executableURL: cliURL,
                        fileURL: fileURL,
                        arguments: [
                            "alert",
                            "--agent", "a-\(index)",
                            "--project", "concurrency",
                            "--timestamp", "\(index)"
                        ]
                    )
                } catch {
                    lock.lock()
                    errors.append(error)
                    lock.unlock()
                }
            }

            group.enter()
            queue.async {
                defer { group.leave() }
                do {
                    try self.runCLIAppend(
                        executableURL: cliURL,
                        fileURL: fileURL,
                        arguments: [
                            "done",
                            "--agent", "b-\(index)",
                            "--project", "concurrency",
                            "--timestamp", "\(100 + index)"
                        ]
                    )
                } catch {
                    lock.lock()
                    errors.append(error)
                    lock.unlock()
                }
            }
        }

        group.wait()

        XCTAssertTrue(errors.isEmpty)
        let events = try storeA.loadAll()
        XCTAssertEqual(events.count, 40)
        XCTAssertEqual(Set(events.map(\.agentID)).count, 40)
    }

    private func runCLIAppend(executableURL: URL, fileURL: URL, arguments: [String]) throws {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.environment = {
            var environment = ProcessInfo.processInfo.environment
            environment[EventStore.environmentOverrideKey] = fileURL.path
            return environment
        }()

        let errorPipe = Pipe()
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorOutput = String(data: errorData, encoding: .utf8) ?? "unknown error"
            throw NSError(domain: "EventStoreTests", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: errorOutput])
        }
    }
}
