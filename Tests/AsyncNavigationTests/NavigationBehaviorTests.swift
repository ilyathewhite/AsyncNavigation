import SwiftUI
import Testing
@testable import AsyncNavigation

extension AsyncNavigationTestSuites {
    @MainActor
    @Suite struct NavigationBehaviorTests {}
}

extension AsyncNavigationTestSuites.NavigationBehaviorTests {
    @Test
    func navigationNodeThenPushesViewModelAndPassesPublishedValue() async throws {
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
            Issue.record("Expected the callback error to escape")
        } catch {
            #expect(error as? TestError == .boom)
        }

        #expect(receivedValue == "open")
        #expect(receivedIndex == 0)
        #expect(proxy.currentIndex == 0)
        #expect(proxy.stack.last?.anyViewModel === viewModel)
    }

    @Test
    func navigationNodeThenReplacingTopCancelsPreviousViewModel() async {
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

        #expect(original.isCancelled)
        #expect(receivedValue == "next")
        #expect(receivedIndex == 0)
        #expect(proxy.stack.count == 1)
        #expect(proxy.stack.last?.anyViewModel === replacement)
    }

    @Test
    func testNavigationProxyPublishesViewModelsByTimeIndexAndSupportsBackAction() async throws {
        let proxy = TestNavigationProxy()
        let first = TestStringViewModel(name: "first")
        let second = TestIntViewModel(seed: 2)

        _ = proxy.push(ViewModelUI<StringNamespace>(first))
        _ = proxy.push(ViewModelUI<IntNamespace>(second))

        #expect(proxy.currentIndex == 1)

        proxy.backAction()

        #expect(proxy.currentIndex == 0)
        #expect(second.isCancelled)

        let currentTimeIndex = proxy.currentViewModelPublisher.value.timeIndex
        var timeIndex = currentTimeIndex
        let currentViewModel = try await proxy.getViewModel(StringNamespace.self, &timeIndex)

        #expect(currentViewModel === first)
        #expect(timeIndex == currentTimeIndex + 1)

        var mismatchIndex = currentTimeIndex

        do {
            _ = try await proxy.getViewModel(TestIntViewModel.self, &mismatchIndex)
            Issue.record("Expected a type mismatch error")
        } catch {
            #expect(error as? TestNavigationProxy.CurrentViewModelError == .typeMismatch)
        }
    }

    @Test
    func navigationPathContainerPushReplacePopAndExternalPathChangesCancelViewModels() {
        let container = NavigationPathContainer()
        let first = TestStringViewModel(name: "first")
        let second = TestStringViewModel(name: "second")
        let third = TestStringViewModel(name: "third")
        let replacement = TestStringViewModel(name: "replacement")

        #expect(container.currentIndex == -1)

        _ = container.push(ViewModelUI<StringNamespace>(first))
        _ = container.push(ViewModelUI<StringNamespace>(second))

        #expect(container.currentIndex == 1)
        #expect(container.path.count == 2)

        _ = container.replaceTop(with: ViewModelUI<StringNamespace>(third))

        #expect(second.isCancelled)
        #expect(container.currentIndex == 1)
        #expect(container.stack.last?.anyViewModel === third)

        container.pop(to: 0)

        #expect(third.isCancelled)
        #expect(container.currentIndex == 0)
        #expect(container.path.count == 1)

        _ = container.push(ViewModelUI<StringNamespace>(replacement))
        container.path = NavigationPath()

        #expect(first.isCancelled)
        #expect(replacement.isCancelled)
        #expect(container.stack.count == 0)
        #expect(container.path.count == 0)

        _ = container.push(ViewModelUI<StringNamespace>(TestStringViewModel(name: "root")))
        container.popToRoot()
        #expect(container.stack.count == 0)
    }

    @Test
    func navigationProxyPopUsesCurrentIndex() {
        let proxy = TestNavigationProxy()
        let first = TestStringViewModel(name: "first")
        let second = TestStringViewModel(name: "second")

        _ = proxy.push(ViewModelUI<StringNamespace>(first))
        _ = proxy.push(ViewModelUI<StringNamespace>(second))

        proxy.pop()

        #expect(second.isCancelled)
        #expect(proxy.currentIndex == 0)
        #expect(proxy.stack.last?.anyViewModel === first)
    }

    @Test
    func navigationNodeNonThrowingVariantsAndPopToRoot() async {
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
            Issue.record("Expected callback error to escape")
        } catch {
            #expect(error as? TestError == .boom)
        }

        proxy.popToRoot()

        #expect(firstReceived?.0 == "value")
        #expect(firstReceived?.1 == 1)
        #expect(secondReceived?.0 == "replacement")
        #expect(secondReceived?.1 == 1)
        #expect(proxy.currentIndex == 0)
        #expect(proxy.stack.last?.anyViewModel === root)
    }

    @Test
    func testNavigationProxyPlaceholderAndTypedLookupBranches() async throws {
        let placeholder = TestNavigationProxy.PlaceholderViewModel()
        placeholder.publish(())
        placeholder.cancel()

        #expect(placeholder.isCancelled)

        let proxy = TestNavigationProxy()
        let viewModel = TestStringViewModel(name: "tracked")
        _ = proxy.push(ViewModelUI<StringNamespace>(viewModel))

        let currentTimeIndex = proxy.currentViewModelPublisher.value.timeIndex
        var typedTimeIndex = currentTimeIndex
        let typedViewModel = try await proxy.getViewModel(TestStringViewModel.self, &typedTimeIndex)

        #expect(typedViewModel === viewModel)
        #expect(typedTimeIndex == currentTimeIndex + 1)

        var mismatchTimeIndex = currentTimeIndex
        do {
            _ = try await proxy.getViewModel(IntNamespace.self, &mismatchTimeIndex)
            Issue.record("Expected type mismatch for namespace lookup")
        } catch {
            #expect(error as? TestNavigationProxy.CurrentViewModelError == .typeMismatch)
        }
    }
}
