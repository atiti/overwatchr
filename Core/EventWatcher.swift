import Foundation

public struct EventWatcherUpdate: Sendable {
    public let newEvents: [AgentEvent]
    public let currentAlerts: [AgentEvent]
}

@MainActor
public final class EventWatcher: NSObject {
    private let store: EventStore
    private let interval: TimeInterval
    private let onUpdate: (EventWatcherUpdate) -> Void

    private var timer: Timer?
    private var readOffset: UInt64 = 0
    private var queue = AlertQueue()

    public init(
        store: EventStore = EventStore(),
        interval: TimeInterval = 1.0,
        onUpdate: @escaping (EventWatcherUpdate) -> Void
    ) {
        self.store = store
        self.interval = interval
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
            queue.apply(batch.events)
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

            queue.apply(batch.events)
            emit(newEvents: batch.events)
        } catch {
            emit(newEvents: [])
        }
    }

    private func emit(newEvents: [AgentEvent]) {
        onUpdate(EventWatcherUpdate(newEvents: newEvents, currentAlerts: queue.alerts))
    }
}
