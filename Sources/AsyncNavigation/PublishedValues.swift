import AsyncAlgorithms
import Foundation

public enum NavigationCancellation: Error, Equatable, Sendable {
    case cancel
}

/// Successive UI outputs. Each iterator receives values published after it subscribes.
/// Publication is synchronous; delivery is buffered, ordered, and never coalesced.
@MainActor
public final class PublishedValues<Element: Sendable>: @MainActor AsyncSequence {
    public typealias Failure = any Error

    private struct Event: Sendable {
        let index: UInt64
        let value: Element
    }

    private let continuation: AsyncThrowingStream<Event, any Error>.Continuation
    private let makeNext: @MainActor () -> (@MainActor () async throws -> Event?)
    private var nextIndex: UInt64 = 0
    private var requests: Set<UUID> = []
    private var subscribers: Set<UUID> = []
    private let requestChanges = MainActorValueSource<Void>()
    private let cancellationChanges = MainActorValueSource<Void>()
    public private(set) var isFinished = false
    public var hasRequest: Bool { !requests.isEmpty }

    public init() {
        let (stream, continuation) = AsyncThrowingStream<Event, any Error>.makeStream(bufferingPolicy: .unbounded)
        self.continuation = continuation
        let shared = stream.share(bufferingPolicy: .unbounded)
        makeNext = {
            var iterator = shared.makeAsyncIterator()
            return { try await iterator.next(isolation: MainActor.shared) }
        }
    }

    isolated deinit { finish() }

    @MainActor
    fileprivate final class Lifetime {
        let end: () -> Void
        init(_ end: @escaping () -> Void) { self.end = end }
        isolated deinit { end() }
    }

    @MainActor
    public struct Iterator: @MainActor AsyncIteratorProtocol {
        private let nextValue: @MainActor () async throws -> Element?
        private let lifetime: Lifetime?

        fileprivate init(lifetime: Lifetime? = nil, _ next: @escaping @MainActor () async throws -> Element?) {
            self.lifetime = lifetime
            nextValue = next
        }

        public mutating func next() async throws -> Element? {
            defer { withExtendedLifetime(lifetime) {} }
            try Task.checkCancellation()
            return try await nextValue()
        }
    }

    public func makeAsyncIterator() -> Iterator {
        guard !isFinished else { return Iterator { throw NavigationCancellation.cancel } }
        let firstIndex = nextIndex
        let next = makeNext()
        let id = UUID()
        subscribers.insert(id)
        let lifetime = Lifetime { [weak self] in
            self?.subscribers.remove(id)
            self?.requests.remove(id)
        }
        return Iterator(lifetime: lifetime) { [weak self] in
            self?.requests.insert(id)
            self?.requestChanges.send(())
            defer { self?.requests.remove(id) }
            while let event = try await next() {
                // share can still hold a slow observer's backlog when a new iterator joins.
                guard event.index >= firstIndex else { continue }
                return event.value
            }
            return nil
        }
    }

    public var values: MainActorSequence<Element> {
        MainActorSequence { [weak self] in
            guard let self else { return { nil } }
            var iterator = self.makeAsyncIterator()
            return { try? await iterator.next() }
        }
    }

    public var cancellation: MainActorSequence<Void> {
        MainActorSequence { [weak self] in
            guard let self, !self.isFinished else {
                var delivered = false
                return {
                    guard !delivered else { return nil }
                    delivered = true
                    return ()
                }
            }
            var iterator = self.cancellationChanges.values.makeAsyncIterator()
            return { await iterator.next() }
        }
    }

    public func waitForRequest() async {
        guard !hasRequest, !isFinished else { return }
        _ = await requestChanges.values.first { _ in true }
    }

    public func send(_ value: Element) {
        guard !isFinished, !subscribers.isEmpty else { return }
        requests.removeAll()
        continuation.yield(Event(index: nextIndex, value: value))
        nextIndex += 1
    }

    public func finish() {
        guard !isFinished else { return }
        isFinished = true
        requests.removeAll()
        continuation.finish(throwing: NavigationCancellation.cancel)
        requestChanges.finish()
        cancellationChanges.send(())
        cancellationChanges.finish()
    }
}
