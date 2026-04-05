import Combine
import XCTest
@testable import AsyncNavigation

final class BasicViewModelTests: XCTestCase {
    @MainActor
    func testFirstValueWaitsForRequestAndCancelsAfterReturning() async throws {
        let viewModel = TestStringViewModel(name: "root")
        let task = Task { @MainActor in
            try await viewModel.firstValue()
        }

        await viewModel.getRequest()

        XCTAssertTrue(viewModel.hasRequest)

        viewModel.publish("done")

        let receivedValue = try await task.value

        XCTAssertEqual(receivedValue, "done")
        XCTAssertFalse(viewModel.hasRequest)
        XCTAssertTrue(viewModel.isCancelled)
        XCTAssertEqual(viewModel.cancelCallCount, 1)
    }

    @MainActor
    func testCancelOnRequestThrowsAndMarksViewModelCancelled() async {
        let viewModel = TestStringViewModel(name: "cancellable")
        let task = Task { @MainActor in
            try await viewModel.firstValue()
        }

        await viewModel.cancelOnRequest()

        do {
            _ = try await task.value
            XCTFail("Expected cancellation to throw")
        }
        catch {
            XCTAssertTrue(viewModel.isCancelled)
        }
    }

    @MainActor
    func testGetFirstReceivesPublishedValue() async throws {
        let viewModel = TestStringViewModel(name: "sheet")
        var receivedValue: String?

        let task = Task { @MainActor in
            await viewModel.getFirst { value in
                receivedValue = value
            }
        }

        await viewModel.publishOnRequest("accepted")
        await task.value

        XCTAssertEqual(receivedValue, "accepted")
    }

    @MainActor
    func testRunAddsAndRemovesChildViewModel() async throws {
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

        XCTAssertEqual(receivedValue, 42)
        XCTAssertEqual(addedKey, TestIntViewModel.viewModelDefaultKey)
        XCTAssertNil(storedChild)
        XCTAssertTrue(child.isCancelled)
    }

    @MainActor
    func testAddChildIfNeededAvoidsConstructingDuplicateChild() async {
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

        XCTAssertEqual(constructionCount, 1)
        XCTAssertEqual(child?.seed, 1)
        XCTAssertTrue(anyChild === child)

        parent.removeChild(nil, delay: false)
        parent.removeChild(child, delay: false)

        let removedChild: TestIntViewModel? = parent.child()

        XCTAssertNil(removedChild)
        XCTAssertTrue(child?.isCancelled ?? false)
    }

    @MainActor
    func testIsCancelledPublisherEmitsWhenCancelled() async {
        let viewModel = TestStringViewModel(name: "publisher")
        let expectation = expectation(description: "cancellation event")
        var cancellable: AnyCancellable?

        cancellable = viewModel.isCancelledPublisher.sink {
            expectation.fulfill()
        }

        viewModel.cancel()

        await fulfillment(of: [expectation], timeout: 1)
        withExtendedLifetime(cancellable) {}
    }

    @MainActor
    func testDefaultProtocolHelpersPublishCancelAndCompareIdentity() async throws {
        let first = DefaultStringViewModel()
        let second = DefaultStringViewModel()
        let optionalFirst: DefaultStringViewModel? = first

        XCTAssertEqual(first, first)
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(first.hashValue, first.hashValue)
        XCTAssertEqual(DefaultStringViewModel.viewModelDefaultKey, "DefaultStringViewModel")

        let firstValueTask = Task { @MainActor in
            try await first.firstValue()
        }

        await first.publishOnRequest("value")
        let firstValue = try await firstValueTask.value
        XCTAssertEqual(firstValue, "value")

        let cancelTask = Task { @MainActor in
            try await second.firstValue()
        }

        await second.cancelOnRequest()

        do {
            _ = try await cancelTask.value
            XCTFail("Expected default cancellation to throw")
        }
        catch {
            XCTAssertTrue(second.hasRequest)
        }

        XCTAssertNotNil(optionalFirst)
    }

    @MainActor
    func testPublishedValueHelperVariantsProduceExpectedResults() async throws {
        let throwingViewModel = DefaultStringViewModel()
        let throwingTask = Task { @MainActor in
            var iterator = throwingViewModel.throwingAsyncValues.makeAsyncIterator()
            return try await iterator.next()
        }

        await throwingViewModel.publishOnRequest("throwing")
        let throwingValue = try await throwingTask.value
        XCTAssertEqual(throwingValue, "throwing")

        let successViewModel = DefaultStringViewModel()
        let resultExpectation = expectation(description: "value result success")
        var receivedSuccess: String?
        let successCancellable = successViewModel.valueResult.sink { result in
            if case .success(let value) = result {
                receivedSuccess = value
                resultExpectation.fulfill()
            }
        }

        await successViewModel.publishOnRequest("success")
        await fulfillment(of: [resultExpectation], timeout: 1)
        XCTAssertEqual(receivedSuccess, "success")
        withExtendedLifetime(successCancellable) {}

        let failureResultViewModel = DefaultStringViewModel()
        let failureExpectation = expectation(description: "value result failure")
        var receivedFailure = false
        let failureCancellable = failureResultViewModel.valueResult.sink { result in
            if case .failure = result {
                receivedFailure = true
                failureExpectation.fulfill()
            }
        }

        await failureResultViewModel.cancelOnRequest()
        await fulfillment(of: [failureExpectation], timeout: 1)
        XCTAssertTrue(receivedFailure)
        withExtendedLifetime(failureCancellable) {}

        let getFirstViewModel = DefaultStringViewModel()
        let failureTask = Task { @MainActor in
            try await getFirstViewModel.getFirst { value in
                XCTAssertEqual(value, "failure")
                throw TestError.boom
            }
        }

        await getFirstViewModel.publishOnRequest("failure")
        do {
            try await failureTask.value
            XCTFail("Expected getFirst to surface the callback error")
        }
        catch {
            XCTAssertEqual(error as? TestError, .boom)
        }

        let getViewModel = DefaultStringViewModel()
        let getTask = Task { @MainActor in
            try await getViewModel.get { value in
                XCTAssertEqual(value, "ignored")
                throw TestError.boom
            }
        }

        await getViewModel.publishOnRequest("ignored")
        do {
            _ = try await getTask.value
            XCTFail("Expected get to surface the callback error")
        }
        catch {
            XCTAssertEqual(error as? TestError, .boom)
        }
    }
}
