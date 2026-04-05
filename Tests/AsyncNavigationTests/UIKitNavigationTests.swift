#if os(iOS)
import SwiftUI
import UIKit
import XCTest
@testable import AsyncNavigation

private final class TestNavigationController: UINavigationController {
    override func pushViewController(_ viewController: UIViewController, animated: Bool) {
        viewControllers.append(viewController)
    }

    override func popToViewController(_ viewController: UIViewController, animated: Bool) -> [UIViewController]? {
        guard let index = viewControllers.firstIndex(of: viewController) else { return nil }
        let popped = Array(viewControllers[(index + 1)...])
        viewControllers = Array(viewControllers[...index])
        return popped
    }

    override func popToRootViewController(animated: Bool) -> [UIViewController]? {
        guard let root = viewControllers.first else { return nil }
        let popped = Array(viewControllers.dropFirst())
        viewControllers = [root]
        return popped
    }
}

final class UIKitNavigationTests: XCTestCase {
    @MainActor
    func testUIKitNavigationProxyManipulatesNavigationController() {
        let root = TestStringViewModel(name: "root")
        let rootController = HostingController<ViewModelUI<StringNamespace>>(viewModel: root)
        let navigationController = TestNavigationController(rootViewController: rootController)

        let proxy = UIKitNavigationProxy(navigationController)

        XCTAssertEqual(proxy.currentIndex, 0)

        let pushed = TestStringViewModel(name: "pushed")
        let pushIndex = proxy.push(ViewModelUI<StringNamespace>(pushed))

        XCTAssertEqual(pushIndex, 1)
        XCTAssertEqual(proxy.currentIndex, 1)
        XCTAssertTrue((navigationController.topViewController as? HostingController<ViewModelUI<StringNamespace>>)?.viewModel === pushed)

        let replacement = TestStringViewModel(name: "replacement")
        let replaceIndex = proxy.replaceTop(with: ViewModelUI<StringNamespace>(replacement))

        XCTAssertEqual(replaceIndex, 1)
        XCTAssertTrue((navigationController.topViewController as? HostingController<ViewModelUI<StringNamespace>>)?.viewModel === replacement)

        let second = TestStringViewModel(name: "second")
        _ = proxy.push(ViewModelUI<StringNamespace>(second))
        XCTAssertEqual(proxy.currentIndex, 2)

        proxy.pop(to: 1)
        XCTAssertEqual(proxy.currentIndex, 1)
        XCTAssertTrue((navigationController.topViewController as? HostingController<ViewModelUI<StringNamespace>>)?.viewModel === replacement)

        proxy.popToRoot()
        XCTAssertEqual(proxy.currentIndex, 0)
        XCTAssertTrue(navigationController.topViewController === rootController)

        let emptyProxy = UIKitNavigationProxy(UINavigationController())
        XCTAssertEqual(emptyProxy.replaceTop(with: ViewModelUI<StringNamespace>(TestStringViewModel(name: "empty"))), -1)

        let orphan = TestStringViewModel(name: "orphan")
        let orphanController = HostingController<ViewModelUI<StringNamespace>>(viewModel: orphan)
        orphanController.didMove(toParent: nil)
        XCTAssertTrue(orphan.isCancelled)
    }

    @MainActor
    func testHostedIOSNavigationAndPresentationPathsRender() async {
        let flowRoot = TestStringViewModel(name: "flow-root")
        let flowPushed = TestStringViewModel(name: "flow-pushed")
        let flowExpectation = expectation(description: "navigation flow run")
        let flowWindow = hostInWindow(
            NavigationFlow(RootNavigationNode<StringNamespace>(flowRoot)) { _, proxy in
                _ = proxy.push(ViewModelUI<StringNamespace>(flowPushed))
                flowExpectation.fulfill()
            }
        )

        defer {
            flowWindow.isHidden = true
            flowWindow.rootViewController = nil
        }

        await renderHostedView()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            flowRoot.publish("go")
        }
        await fulfillment(of: [flowExpectation], timeout: 1)
        await renderHostedView()
        flowRoot.cancel()

        let uiKitRoot = TestStringViewModel(name: "uikit-root")
        let uiKitPushed = TestStringViewModel(name: "uikit-pushed")
        let uiKitExpectation = expectation(description: "uikit flow run")
        let uiKitWindow = hostInWindow(
            UIKitNavigationFlow(RootNavigationNode<StringNamespace>(uiKitRoot)) { _, proxy in
                _ = proxy.push(ViewModelUI<StringNamespace>(uiKitPushed))
                uiKitExpectation.fulfill()
            }
        )

        defer {
            uiKitWindow.isHidden = true
            uiKitWindow.rootViewController = nil
        }

        _ = UIKitNavigationFlowImpl<StringNamespace>(root: TestStringViewModel(name: "unused"))

        await renderHostedView()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            uiKitRoot.publish("go")
        }
        await fulfillment(of: [uiKitExpectation], timeout: 1)
        await renderHostedView()
        uiKitRoot.cancel()

        let registryViewModel = TestStringViewModel(name: "registry")
        let registryViewModelUI = ViewModelUI<StringNamespace>(registryViewModel)
        ViewModelUIRegistry.add(registryViewModelUI)

        let storedViewModelUI: ViewModelUI<StringNamespace>? = ViewModelUIRegistry.get(id: registryViewModelUI.id)
        XCTAssertTrue(storedViewModelUI?.viewModel === registryViewModel)

        let windowContent = WindowContentView<ViewModelUI<StringNamespace>>(id: registryViewModelUI.id)
        let missingWindowContent = WindowContentView<ViewModelUI<StringNamespace>>(id: nil)

        XCTAssertTrue(windowContent.viewModelUI?.viewModel === registryViewModel)
        XCTAssertNil(missingWindowContent.viewModelUI)

        _ = windowContent.body
        _ = missingWindowContent.body
        _ = StringNamespace.windowGroup()

        ViewModelUIRegistry.remove(id: registryViewModelUI.id)

        let removedViewModelUI: ViewModelUI<StringNamespace>? = ViewModelUIRegistry.get(id: registryViewModelUI.id)
        XCTAssertNil(removedViewModelUI)

        let hostedWindowViewModel = TestStringViewModel(name: "window-content")
        let hostedWindowViewModelUI = ViewModelUI<StringNamespace>(hostedWindowViewModel)
        ViewModelUIRegistry.add(hostedWindowViewModelUI)
        let contentWindow = hostInWindow(
            WindowContentView<ViewModelUI<StringNamespace>>(id: hostedWindowViewModelUI.id)
        )

        defer {
            contentWindow.isHidden = true
            contentWindow.rootViewController = nil
            ViewModelUIRegistry.remove(id: hostedWindowViewModelUI.id)
        }

        await renderHostedView()
        hostedWindowViewModel.cancel()
        await renderHostedView()

        let presentationState = HostedPresentationState()
        let presentationWindow = hostInWindow(HostedPresentationView(state: presentationState))

        defer {
            presentationWindow.isHidden = true
            presentationWindow.rootViewController = nil
        }

        await renderHostedView()
        presentationState.viewModelUI = ViewModelUI<StringNamespace>(TestStringViewModel(name: "modal"))
        presentationState.isPresented = true
        await renderHostedView()

        XCTAssertNotNil(presentationWindow.rootViewController?.presentedViewController)

        presentationState.isPresented = false
        presentationState.viewModelUI = nil
        await renderHostedView()

        let sheetState = HostedPresentationState()
        let sheetWindow = hostInWindow(HostedSheetView(state: sheetState))

        defer {
            sheetWindow.isHidden = true
            sheetWindow.rootViewController = nil
        }

        await renderHostedView()
        sheetState.viewModelUI = ViewModelUI<StringNamespace>(TestStringViewModel(name: "sheet"))
        await renderHostedView()

        XCTAssertNotNil(sheetWindow.rootViewController?.presentedViewController)

        sheetState.viewModelUI = nil
        await renderHostedView()
    }
}
#endif
