import Testing
@testable import AsyncNavigation

extension AsyncNavigationTestSuites {
    @MainActor
    @Suite struct BasicViewModelTests {}
}

extension AsyncNavigationTestSuites.BasicViewModelTests {
    @Test
    func firstValueWaitsForRequestAndCancelsAfterReturning() async throws {
        let viewModel = TestStringViewModel(name: "root")
        let task = Task { @MainActor in
            try await viewModel.firstValue()
        }

        await viewModel.getRequest()

        #expect(viewModel.hasRequest)

        viewModel.publish("done")

        let receivedValue = try await task.value

        #expect(receivedValue == "done")
        #expect(!viewModel.hasRequest)
        #expect(viewModel.isCancelled)
        #expect(viewModel.cancelCallCount == 1)
    }

    @Test
    func firstValueWithoutCancellingPreservesOptionalOutputsAndAllowsRepeatedWaits() async throws {
        let viewModel = BaseViewModel<Int?>()
        for value: Int? in [nil, 7, 7] {
            let task = Task { @MainActor in
                try await viewModel.firstValueWithoutCancelling()
            }
            await viewModel.publishOnRequest(value)
            #expect(try await task.value == value)
            #expect(!viewModel.isCancelled)
            #expect(!viewModel.hasRequest)
        }
    }

    @Test(arguments: [false, true])
    func cancellingValueWaitLeavesViewModelReusable(waitForRequest: Bool) async throws {
        let viewModel = TestStringViewModel(name: "reusable")
        let task = Task { @MainActor in
            try await viewModel.firstValueWithoutCancelling()
        }
        if waitForRequest { await viewModel.getRequest() }
        task.cancel()
        await #expect(throws: (any Error).self) { _ = try await task.value }
        #expect(!viewModel.isCancelled)
        #expect(viewModel.cancelCallCount == 0)
        #expect(!viewModel.hasRequest)

        let next = Task { @MainActor in
            try await viewModel.firstValueWithoutCancelling()
        }
        await viewModel.publishOnRequest("next")
        #expect(try await next.value == "next")
        #expect(viewModel.cancelCallCount == 0)
    }

    @Test
    func firstValueWithoutCancellingPropagatesSourceCancellation() async {
        let viewModel = TestStringViewModel(name: "cancelled source")
        let task = Task { @MainActor in
            try await viewModel.firstValueWithoutCancelling()
        }
        await viewModel.cancelOnRequest()
        await #expect(throws: NavigationCancellation.cancel) { _ = try await task.value }
        #expect(viewModel.isCancelled)
        #expect(viewModel.cancelCallCount == 1)
        #expect(!viewModel.hasRequest)
    }

    @Test
    func cancelOnRequestThrowsAndMarksViewModelCancelled() async {
        let viewModel = TestStringViewModel(name: "cancellable")
        let task = Task { @MainActor in
            try await viewModel.firstValue()
        }

        await viewModel.cancelOnRequest()

        do {
            _ = try await task.value
            Issue.record("Expected cancellation to throw")
        } catch {
            #expect(viewModel.isCancelled)
        }
    }

    @Test
    func getFirstReceivesPublishedValue() async throws {
        let viewModel = TestStringViewModel(name: "sheet")
        var receivedValue: String?

        let task = Task { @MainActor in
            await viewModel.getFirst { value in
                receivedValue = value
            }
        }

        await viewModel.publishOnRequest("accepted")
        await task.value

        #expect(receivedValue == "accepted")
    }

    @Test
    func runAddsAndRemovesChildViewModel() async throws {
        let parent = TestStringViewModel(name: "parent")
        let child = TestIntViewModel(seed: 42)
        var addedKey: String?

        let task = Task { @MainActor in
            try await parent.run(child) { _, key in
                addedKey = key
            }
        }

        await child.publishOnRequest(42)
        let receivedValue = try await task.value

        await flushMainQueue()

        let storedChild: TestIntViewModel? = parent.child()

        #expect(receivedValue == 42)
        #expect(addedKey == TestIntViewModel.viewModelDefaultKey)
        #expect(storedChild == nil)
        #expect(child.isCancelled)
    }

    @Test
    func addChildIfNeededAvoidsConstructingDuplicateChild() async {
        let parent = TestStringViewModel(name: "container")
        var constructionCount = 0

        parent.addChildIfNeeded({
            constructionCount += 1
            return TestIntViewModel(seed: 1)
        }())
        parent.addChildIfNeeded({
            constructionCount += 1
            return TestIntViewModel(seed: 2)
        }())

        let child: TestIntViewModel? = parent.child()
        let anyChild = parent.anyChild(key: TestIntViewModel.viewModelDefaultKey)

        #expect(constructionCount == 1)
        #expect(child?.seed == 1)
        #expect(anyChild === child)

        parent.removeChild(nil, delay: false)
        parent.removeChild(child, delay: false)

        let removedChild: TestIntViewModel? = parent.child()

        #expect(removedChild == nil)
        #expect(child?.isCancelled == true)
    }

    @Test
    func defaultProtocolHelpersPublishCancelAndCompareIdentity() async throws {
        let first = DefaultStringViewModel()
        let second = DefaultStringViewModel()
        let optionalFirst: DefaultStringViewModel? = first

        #expect(first == first)
        #expect(first != second)
        #expect(first.hashValue == first.hashValue)
        #expect(DefaultStringViewModel.viewModelDefaultKey == "DefaultStringViewModel")

        let firstValueTask = Task { @MainActor in
            try await first.firstValue()
        }

        await first.publishOnRequest("value")
        let firstValue = try await firstValueTask.value
        #expect(firstValue == "value")

        let cancelTask = Task { @MainActor in
            try await second.firstValue()
        }

        await second.cancelOnRequest()

        do {
            _ = try await cancelTask.value
            Issue.record("Expected default cancellation to throw")
        } catch {
            #expect(!second.hasRequest)
        }

        #expect(optionalFirst != nil)
    }

    @Test
    func publishedValueHelperVariantsProduceExpectedResults() async throws {
        let throwingViewModel = DefaultStringViewModel()
        let throwingTask = Task { @MainActor in
            var iterator = throwingViewModel.throwingAsyncValues.makeAsyncIterator()
            return try await iterator.next()
        }

        await throwingViewModel.publishOnRequest("throwing")
        let throwingValue = try await throwingTask.value
        #expect(throwingValue == "throwing")

        let getFirstViewModel = DefaultStringViewModel()
        let failureTask = Task { @MainActor in
            try await getFirstViewModel.getFirst { value in
                #expect(value == "failure")
                throw TestError.boom
            }
        }

        await getFirstViewModel.publishOnRequest("failure")
        do {
            try await failureTask.value
            Issue.record("Expected getFirst to surface the callback error")
        } catch {
            #expect(error as? TestError == .boom)
        }

        let getViewModel = DefaultStringViewModel()
        let getTask = Task { @MainActor in
            try await getViewModel.get { value in
                #expect(value == "ignored")
                throw TestError.boom
            }
        }

        await getViewModel.publishOnRequest("ignored")
        do {
            _ = try await getTask.value
            Issue.record("Expected get to surface the callback error")
        } catch {
            #expect(error as? TestError == .boom)
        }
    }
}
