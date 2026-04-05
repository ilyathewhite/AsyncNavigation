import SwiftUI
import XCTest
@testable import AsyncNavigation

final class NavigationBehaviorTests: XCTestCase {
    @MainActor
    func testNavigationNodeThenPushesViewModelAndPassesPublishedValue() async throws {
        let proxy = TestNavigationProxy()
        let viewModel = TestStringViewModel(name: "details")
        let node = NavigationNode<StringNamespace>(viewModel, proxy)
        var receivedValue = ""
        var receivedIndex = -1

        let task = Task { @MainActor in
            try await node.then { value, index in
                receivedValue = value
                receivedIndex = index
                throw TestError.boom
            }
        }

        await viewModel.publishOnRequest("open")

        do {
            try await task.value
            XCTFail("Expected the callback error to escape")
        }
        catch {
            XCTAssertEqual(error as? TestError, .boom)
        }

        XCTAssertEqual(receivedValue, "open")
        XCTAssertEqual(receivedIndex, 0)
        XCTAssertEqual(proxy.currentIndex, 0)
        XCTAssertTrue(proxy.stack.last?.anyViewModel === viewModel)
    }

    @MainActor
    func testNavigationNodeThenReplacingTopCancelsPreviousViewModel() async {
        let proxy = TestNavigationProxy()
        let original = TestStringViewModel(name: "original")
        let replacement = TestStringViewModel(name: "replacement")
        _ = proxy.push(ViewModelUI<StringNamespace>(original))
        let node = NavigationNode<StringNamespace>(replacement, proxy)
        var receivedValue = ""
        var receivedIndex = -1

        let task = Task { @MainActor in
            await node.thenReplacingTop { value, index in
                receivedValue = value
                receivedIndex = index
                replacement.cancel()
            }
        }

        await replacement.publishOnRequest("next")
        await task.value

        XCTAssertTrue(original.isCancelled)
        XCTAssertEqual(receivedValue, "next")
        XCTAssertEqual(receivedIndex, 0)
        XCTAssertEqual(proxy.stack.count, 1)
        XCTAssertTrue(proxy.stack.last?.anyViewModel === replacement)
    }

    @MainActor
    func testTestNavigationProxyPublishesViewModelsByTimeIndexAndSupportsBackAction() async throws {
        let proxy = TestNavigationProxy()
        let first = TestStringViewModel(name: "first")
        let second = TestIntViewModel(seed: 2)

        _ = proxy.push(ViewModelUI<StringNamespace>(first))
        _ = proxy.push(ViewModelUI<IntNamespace>(second))

        XCTAssertEqual(proxy.currentIndex, 1)

        proxy.backAction()

        XCTAssertEqual(proxy.currentIndex, 0)
        XCTAssertTrue(second.isCancelled)

        let currentTimeIndex = proxy.currentViewModelPublisher.value.timeIndex
        var timeIndex = currentTimeIndex
        let currentViewModel = try await proxy.getViewModel(StringNamespace.self, &timeIndex)

        XCTAssertTrue(currentViewModel === first)
        XCTAssertEqual(timeIndex, currentTimeIndex + 1)

        var mismatchIndex = currentTimeIndex

        do {
            _ = try await proxy.getViewModel(TestIntViewModel.self, &mismatchIndex)
            XCTFail("Expected a type mismatch error")
        }
        catch {
            XCTAssertEqual(error as? TestNavigationProxy.CurrentViewModelError, .typeMismatch)
        }
    }

    @MainActor
    func testNavigationPathContainerPushReplacePopAndExternalPathChangesCancelViewModels() {
        let container = NavigationPathContainer()
        let first = TestStringViewModel(name: "first")
        let second = TestStringViewModel(name: "second")
        let third = TestStringViewModel(name: "third")
        let replacement = TestStringViewModel(name: "replacement")

        XCTAssertEqual(container.currentIndex, -1)

        _ = container.push(ViewModelUI<StringNamespace>(first))
        _ = container.push(ViewModelUI<StringNamespace>(second))

        XCTAssertEqual(container.currentIndex, 1)
        XCTAssertEqual(container.path.count, 2)

        _ = container.replaceTop(with: ViewModelUI<StringNamespace>(third))

        XCTAssertTrue(second.isCancelled)
        XCTAssertEqual(container.currentIndex, 1)
        XCTAssertTrue(container.stack.last?.anyViewModel === third)

        container.pop(to: 0)

        XCTAssertTrue(third.isCancelled)
        XCTAssertEqual(container.currentIndex, 0)
        XCTAssertEqual(container.path.count, 1)

        _ = container.push(ViewModelUI<StringNamespace>(replacement))
        container.path = NavigationPath()

        XCTAssertTrue(first.isCancelled)
        XCTAssertTrue(replacement.isCancelled)
        XCTAssertEqual(container.stack.count, 0)
        XCTAssertEqual(container.path.count, 0)

        _ = container.push(ViewModelUI<StringNamespace>(TestStringViewModel(name: "root")))
        container.popToRoot()
        XCTAssertEqual(container.stack.count, 0)
    }

    @MainActor
    func testNavigationProxyPopUsesCurrentIndex() {
        let proxy = TestNavigationProxy()
        let first = TestStringViewModel(name: "first")
        let second = TestStringViewModel(name: "second")

        _ = proxy.push(ViewModelUI<StringNamespace>(first))
        _ = proxy.push(ViewModelUI<StringNamespace>(second))

        proxy.pop()

        XCTAssertTrue(second.isCancelled)
        XCTAssertEqual(proxy.currentIndex, 0)
        XCTAssertTrue(proxy.stack.last?.anyViewModel === first)
    }

    @MainActor
    func testNavigationNodeNonThrowingVariantsAndPopToRoot() async throws {
        let proxy = TestNavigationProxy()
        let first = TestStringViewModel(name: "first")
        let second = TestStringViewModel(name: "second")
        let root = TestStringViewModel(name: "root")
        _ = proxy.push(ViewModelUI<StringNamespace>(root))

        var firstReceived: (String, Int)?
        let firstTask = Task { @MainActor in
            await NavigationNode<StringNamespace>(first, proxy).then { value, index in
                firstReceived = (value, index)
                first.cancel()
            }
        }

        await first.publishOnRequest("value")
        await firstTask.value

        var secondReceived: (String, Int)?
        let secondTask = Task { @MainActor in
            try await NavigationNode<StringNamespace>(second, proxy).thenReplacingTop { value, index in
                secondReceived = (value, index)
                throw TestError.boom
            }
        }

        await second.publishOnRequest("replacement")

        do {
            try await secondTask.value
            XCTFail("Expected callback error to escape")
        }
        catch {
            XCTAssertEqual(error as? TestError, .boom)
        }

        proxy.popToRoot()

        XCTAssertEqual(firstReceived?.0, "value")
        XCTAssertEqual(firstReceived?.1, 1)
        XCTAssertEqual(secondReceived?.0, "replacement")
        XCTAssertEqual(secondReceived?.1, 1)
        XCTAssertEqual(proxy.currentIndex, 0)
        XCTAssertTrue(proxy.stack.last?.anyViewModel === root)
    }

    @MainActor
    func testTestNavigationProxyPlaceholderAndTypedLookupBranches() async throws {
        let placeholder = TestNavigationProxy.PlaceholderViewModel()
        placeholder.publish(())
        placeholder.cancel()

        XCTAssertTrue(placeholder.isCancelled)

        let proxy = TestNavigationProxy()
        let viewModel = TestStringViewModel(name: "tracked")
        _ = proxy.push(ViewModelUI<StringNamespace>(viewModel))

        let currentTimeIndex = proxy.currentViewModelPublisher.value.timeIndex
        var typedTimeIndex = currentTimeIndex
        let typedViewModel = try await proxy.getViewModel(TestStringViewModel.self, &typedTimeIndex)

        XCTAssertTrue(typedViewModel === viewModel)
        XCTAssertEqual(typedTimeIndex, currentTimeIndex + 1)

        var mismatchTimeIndex = currentTimeIndex
        do {
            _ = try await proxy.getViewModel(IntNamespace.self, &mismatchTimeIndex)
            XCTFail("Expected type mismatch for namespace lookup")
        }
        catch {
            XCTAssertEqual(error as? TestNavigationProxy.CurrentViewModelError, .typeMismatch)
        }
    }
}
