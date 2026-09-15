import Foundation

/// A sequence whose iterator and elements remain on the main actor.
/// Each iterator represents an independent subscription.
@MainActor
public struct MainActorSequence<Element>: @MainActor AsyncSequence {
    public typealias Failure = Never
    private let makeIterator: @MainActor () -> Iterator

    public init(_ makeNext: @escaping @MainActor () -> (@MainActor () async -> Element?)) {
        makeIterator = { Iterator(next: makeNext()) }
    }

    @MainActor
    public struct Iterator: @MainActor AsyncIteratorProtocol {
        public typealias Failure = Never
        private let nextValue: @MainActor () async -> Element?

        fileprivate init(next: @escaping @MainActor () async -> Element?) {
            nextValue = next
        }

        public mutating func next() async -> Element? {
            guard !Task.isCancelled else { return nil }
            let value = await nextValue()
            guard !Task.isCancelled else { return nil }
            return value
        }
    }

    public func makeAsyncIterator() -> Iterator { makeIterator() }

    public func first(where predicate: (Element) -> Bool) async -> Element? {
        for await element in self {
            if predicate(element) { return element }
        }
        return nil
    }

    public func map<Value>(_ transform: @escaping @MainActor (Element) -> Value) -> MainActorSequence<Value> {
        MainActorSequence<Value> {
            var iterator = makeAsyncIterator()
            return { await iterator.next().map(transform) }
        }
    }
}

/// Buffers every value for each active iterator without transferring the payload off the main actor.
@MainActor
public final class MainActorValueSource<Element> {
    @MainActor
    private final class Value {
        let element: Element
        init(_ element: Element) { self.element = element }
    }

    @MainActor
    private final class Subscription {
        var iterator: AsyncStream<Value>.Iterator
        let cancel: () -> Void

        init(_ stream: AsyncStream<Value>, cancel: @escaping () -> Void) {
            iterator = stream.makeAsyncIterator()
            self.cancel = cancel
        }

        isolated deinit { cancel() }

        func next() async -> Element? {
            // Copying the iterator avoids overlapping access when cancellation removes the subscription.
            var iterator = iterator
            let value = await iterator.next(isolation: MainActor.shared)
            self.iterator = iterator
            return value?.element
        }
    }

    private var continuations: [UUID: AsyncStream<Value>.Continuation] = [:]
    private var latest: [Element]
    private let replayLatest: Bool
    public private(set) var isFinished = false

    public init() {
        latest = []
        replayLatest = false
    }

    public init(initialValue: Element) {
        latest = [initialValue]
        replayLatest = true
    }

    isolated deinit { finish() }

    public var values: MainActorSequence<Element> {
        MainActorSequence { [weak self] in
            let (stream, continuation) = AsyncStream<Value>.makeStream(bufferingPolicy: .unbounded)
            let id = UUID()
            if let self, !self.isFinished {
                self.continuations[id] = continuation
                for element in self.latest { continuation.yield(Value(element)) }
            }
            else {
                continuation.finish()
            }
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in self?.continuations.removeValue(forKey: id) }
            }
            let subscription = Subscription(stream) { [weak self] in
                self?.continuations.removeValue(forKey: id)?.finish()
            }
            return { await subscription.next() }
        }
    }

    public func send(_ element: Element) {
        guard !isFinished else { return }
        if replayLatest { latest = [element] }
        let value = Value(element)
        for continuation in continuations.values { continuation.yield(value) }
    }

    public func finish() {
        guard !isFinished else { return }
        isFinished = true
        latest.removeAll()
        let active = continuations.values
        continuations.removeAll()
        for continuation in active { continuation.finish() }
    }
}
