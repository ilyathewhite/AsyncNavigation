import Combine
import Foundation

// Compatibility for callers that are still using Combine. Navigation consumes the native sequences directly.
public extension BasicViewModel {
    typealias ValuePublisher = AnyPublisher<PublishedValue, NavigationCancellation>

    var value: ValuePublisher {
        Deferred { [publishedValue] in
            // Register UI subscriptions immediately. Combine can also subscribe from a background executor.
            let subscription = Thread.isMainThread
                ? MainActor.assumeIsolated { publishedValue.makeAsyncIterator() }
                : nil
            let subject = PassthroughSubject<PublishedValue, NavigationCancellation>()
            let task = Task { @MainActor in
                var iterator = subscription ?? publishedValue.makeAsyncIterator()
                do {
                    while let value = try await iterator.next() {
                        guard !Task.isCancelled else { return }
                        subject.send(value)
                    }
                    subject.send(completion: .finished)
                }
                catch {
                    guard !Task.isCancelled else { return }
                    subject.send(completion: .failure(.cancel))
                }
            }
            return subject.handleEvents(receiveCancel: { task.cancel() }).eraseToAnyPublisher()
        }
        .eraseToAnyPublisher()
    }

    var valueResult: AnyPublisher<Result<PublishedValue, NavigationCancellation>, Never> {
        value.map { .success($0) }.catch { Just(.failure($0)) }.eraseToAnyPublisher()
    }

    var isCancelledPublisher: AnyPublisher<Void, Never> {
        Deferred { [publishedValue] in
            let subject = PassthroughSubject<Void, Never>()
            let task = Task { @MainActor in
                for await _ in publishedValue.cancellation {
                    guard !Task.isCancelled else { return }
                    subject.send(())
                }
                subject.send(completion: .finished)
            }
            return subject.handleEvents(receiveCancel: { task.cancel() }).eraseToAnyPublisher()
        }
        .eraseToAnyPublisher()
    }
}
