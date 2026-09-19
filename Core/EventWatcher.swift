import Foundation

public struct EventWatcherUpdate: Sendable {
    public let newEvents: [AgentEvent]
    public let currentAlerts: [AgentEvent]
}

@MainActor
public final class EventWatcher: NSObject {
    private let store: EventStore
    private let interval: TimeInterval
    private let minimumEventTimestamp: TimeInterval
    private let onUpdate: (EventWatcherUpdate) -> Void

    private var timer: Timer?
    private var readOffset: UInt64 = 0
    private var queue = AlertQueue()

    public init(
        store: EventStore = EventStore(),
        interval: TimeInterval = 1.0,
        minimumEventTimestamp: TimeInterval = SystemBootTime.timestamp(),
        onUpdate: @escaping (EventWatcherUpdate) -> Void
    ) {
        self.store = store
        self.interval = interval
        self.minimumEventTimestamp = minimumEventTimestamp
        self.onUpdate = onUpdate
    }

    public func start() {
        stop()
        bootstrap()
        timer = Timer.scheduledTimer(
            timeInterval: interval,
            target: self,
            selector: #selector(poll),
            userInfo: nil,
            repeats: true
        )
        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func bootstrap() {
        do {
            let batch = try store.readEvents(from: 0)
            readOffset = batch.nextOffset
            queue = AlertQueue()
            queue.apply(currentSessionEvents(from: batch.events))
            emit(newEvents: [])
        } catch {
            emit(newEvents: [])
        }
    }

    @objc
    private func poll() {
        do {
            let batch = try store.readEvents(from: readOffset)
            guard batch.nextOffset != readOffset else {
                emit(newEvents: [])
                return
            }

            readOffset = batch.nextOffset
            guard !batch.events.isEmpty else {
                emit(newEvents: [])
                return
            }

            let newEvents = currentSessionEvents(from: batch.events)
            queue.apply(newEvents)
            emit(newEvents: newEvents)
        } catch {
            emit(newEvents: [])
        }
    }

    private func emit(newEvents: [AgentEvent]) {
        onUpdate(EventWatcherUpdate(newEvents: newEvents, currentAlerts: queue.alerts))
    }

    private func currentSessionEvents(from events: [AgentEvent]) -> [AgentEvent] {
        events.filter { $0.timestamp >= minimumEventTimestamp }
    }
}
