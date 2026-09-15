import Testing
@testable import AsyncNavigation

extension AsyncNavigationTestSuites {
    @MainActor
    @Suite struct AsyncValueTests {}
}

extension AsyncNavigationTestSuites.AsyncValueTests {
    @Test
    func publishedBurstReachesEverySubscriberIncludingNilAndDuplicates() async throws {
        let source = PublishedValues<Int?>()
        var first = source.makeAsyncIterator()
        var second = source.makeAsyncIterator()
        let expected: [Int?] = [1, nil, nil, 2, 2, 3]
        for value in expected { source.send(value) }
        source.finish()
        for value in expected { #expect(try await first.next() == .some(value)) }
        for value in expected { #expect(try await second.next() == .some(value)) }
        await #expect(throws: NavigationCancellation.cancel) { _ = try await first.next() }
        await #expect(throws: NavigationCancellation.cancel) { _ = try await second.next() }
    }

    @Test
    func lateSubscriberSkipsAnotherSubscribersBacklog() async throws {
        let source = PublishedValues<Int>()
        var slow = source.makeAsyncIterator()
        source.send(1)
        source.send(2)
        var late = source.makeAsyncIterator()
        source.send(3)
        source.finish()
        #expect(try await late.next() == 3)
        #expect(try await slow.next() == 1)
        #expect(try await slow.next() == 2)
        #expect(try await slow.next() == 3)
    }

    @Test
    func publicationsWithoutSubscribersAreNotReplayed() async throws {
        let source = PublishedValues<Int>()
        source.send(1)
        var iterator = source.makeAsyncIterator()
        source.send(2)
        #expect(try await iterator.next() == 2)
    }

    @Test
    func cancellingOneConsumerKeepsOtherConsumerAlive() async throws {
        let source = PublishedValues<Int>()
        var survivor = source.makeAsyncIterator()
        let consumer = Task { @MainActor in
            var iterator = source.makeAsyncIterator()
            return try await iterator.next()
        }
        await source.waitForRequest()
        consumer.cancel()
        _ = try? await consumer.value
        source.send(7)
        #expect(try await survivor.next() == 7)
        #expect(!source.isFinished)
        #expect(!source.hasRequest)
    }

    @Test
    func earlyExitAllowsLaterSubscription() async throws {
        let source = PublishedValues<Int>()
        do {
            var iterator = source.makeAsyncIterator()
            source.send(1)
            #expect(try await iterator.next() == 1)
        }
        source.send(2)
        var later = source.makeAsyncIterator()
        source.send(3)
        #expect(try await later.next() == 3)
    }

    @Test
    func cancellationIsRememberedForLateConsumers() async throws {
        let source = PublishedValues<Int>()
        let cancellationValues = source.cancellation
        source.finish()
        var iterator = source.makeAsyncIterator()
        await #expect(throws: NavigationCancellation.cancel) { _ = try await iterator.next() }
        var cancellation = cancellationValues.makeAsyncIterator()
        #expect(await cancellation.next() != nil)
        #expect(await cancellation.next() == nil)
        var values = source.values.makeAsyncIterator()
        #expect(await values.next() == nil)
        await source.waitForRequest()
    }

    @Test
    func requestWaitCanBeCancelled() async {
        let source = PublishedValues<Int>()
        let task = Task { @MainActor in await source.waitForRequest() }
        task.cancel()
        await task.value
        #expect(!source.hasRequest)
    }

    @Test
    func releasingViewModelEndsPendingIteration() async {
        var viewModel: BaseViewModel<Int>? = BaseViewModel()
        weak var weakViewModel = viewModel
        let values = viewModel!.publishedValue
        let task = Task { @MainActor in
            var iterator = values.makeAsyncIterator()
            return try await iterator.next()
        }
        await values.waitForRequest()
        viewModel = nil
        #expect(weakViewModel == nil)
        await #expect(throws: NavigationCancellation.cancel) { _ = try await task.value }
    }

    @Test
    func cancellingPendingIterationSkipsMappedValue() async {
        var resume: CheckedContinuation<Int?, Never>?
        let (started, continuation) = AsyncStream<Void>.makeStream()
        let source = MainActorSequence<Int> {
            {
                await withCheckedContinuation {
                    resume = $0
                    continuation.yield(())
                }
            }
        }
        var mappedValues: [Int] = []
        let values = source.map { value in
            mappedValues.append(value)
            return value
        }
        let task = Task { @MainActor in
            var iterator = values.makeAsyncIterator()
            return await iterator.next()
        }
        var startedIterator = started.makeAsyncIterator()
        await startedIterator.next()

        task.cancel()
        resume?.resume(returning: 42)
        #expect(await task.value == nil)
        #expect(mappedValues.isEmpty)
    }

    @Test
    func stateSequenceKeepsNonSendableValuesOnMainActor() async {
        final class MutableValue { var count = 0 }
        let value = MutableValue()
        let source = MainActorValueSource<MutableValue?>(initialValue: value)
        var first = source.values.makeAsyncIterator()
        var second = source.values.makeAsyncIterator()
        source.send(nil)
        source.send(value)
        source.finish()
        #expect(await first.next()! === value)
        #expect(await second.next()! === value)
        let nilValue = await first.next()
        #expect(nilValue != nil)
        #expect(nilValue! == nil)
        #expect(await first.next()! === value)
        #expect(await first.next() == nil)
    }
}
