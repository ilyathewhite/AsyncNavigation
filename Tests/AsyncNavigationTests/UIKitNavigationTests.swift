#if os(iOS)
import SwiftUI
import UIKit
import Testing
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

extension AsyncNavigationTestSuites {
    @MainActor
    @Suite struct UIKitNavigationTests {}
}

extension AsyncNavigationTestSuites.UIKitNavigationTests {
    @Test
    func uiKitNavigationProxyManipulatesNavigationController() {
        let root = TestStringViewModel(name: "root")
        let rootController = HostingController<ViewModelUI<StringNamespace>>(viewModel: root)
        let navigationController = TestNavigationController(rootViewController: rootController)

        let proxy = UIKitNavigationProxy(navigationController)

        #expect(proxy.currentIndex == 0)

        let pushed = TestStringViewModel(name: "pushed")
        let pushIndex = proxy.push(ViewModelUI<StringNamespace>(pushed))

        #expect(pushIndex == 1)
        #expect(proxy.currentIndex == 1)
        #expect((navigationController.topViewController as? HostingController<ViewModelUI<StringNamespace>>)?.viewModel === pushed)

        let replacement = TestStringViewModel(name: "replacement")
        let replaceIndex = proxy.replaceTop(with: ViewModelUI<StringNamespace>(replacement))

        #expect(replaceIndex == 1)
        #expect((navigationController.topViewController as? HostingController<ViewModelUI<StringNamespace>>)?.viewModel === replacement)

        let second = TestStringViewModel(name: "second")
        _ = proxy.push(ViewModelUI<StringNamespace>(second))
        #expect(proxy.currentIndex == 2)

        proxy.pop(to: 1)
        #expect(proxy.currentIndex == 1)
        #expect((navigationController.topViewController as? HostingController<ViewModelUI<StringNamespace>>)?.viewModel === replacement)

        proxy.popToRoot()
        #expect(proxy.currentIndex == 0)
        #expect(navigationController.topViewController === rootController)

        let emptyProxy = UIKitNavigationProxy(UINavigationController())
        #expect(emptyProxy.replaceTop(with: ViewModelUI<StringNamespace>(TestStringViewModel(name: "empty"))) == -1)

        let orphan = TestStringViewModel(name: "orphan")
        let orphanController = HostingController<ViewModelUI<StringNamespace>>(viewModel: orphan)
        orphanController.didMove(toParent: nil)
        #expect(orphan.isCancelled)
    }

    @Test
    func hostedIOSNavigationAndPresentationPathsRender() async {
        let flowRoot = TestStringViewModel(name: "flow-root")
        let flowPushed = TestStringViewModel(name: "flow-pushed")
        var didRunFlow = false
        let flowWindow = hostInWindow(
            NavigationFlow(RootNavigationNode<StringNamespace>(flowRoot)) { _, proxy in
                _ = proxy.push(ViewModelUI<StringNamespace>(flowPushed))
                didRunFlow = true
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
        #expect(await waitUntil { didRunFlow })
        await renderHostedView()
        flowRoot.cancel()

        let uiKitRoot = TestStringViewModel(name: "uikit-root")
        let uiKitPushed = TestStringViewModel(name: "uikit-pushed")
        var didRunUIKitFlow = false
        let uiKitWindow = hostInWindow(
            UIKitNavigationFlow(RootNavigationNode<StringNamespace>(uiKitRoot)) { _, proxy in
                _ = proxy.push(ViewModelUI<StringNamespace>(uiKitPushed))
                didRunUIKitFlow = true
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
        #expect(await waitUntil { didRunUIKitFlow })
        await renderHostedView()
        uiKitRoot.cancel()

        let registryViewModel = TestStringViewModel(name: "registry")
        let registryViewModelUI = ViewModelUI<StringNamespace>(registryViewModel)
        ViewModelUIRegistry.add(registryViewModelUI)

        let storedViewModelUI: ViewModelUI<StringNamespace>? = ViewModelUIRegistry.get(id: registryViewModelUI.id)
        #expect(storedViewModelUI?.viewModel === registryViewModel)

        let windowContent = WindowContentView<ViewModelUI<StringNamespace>>(id: registryViewModelUI.id)
        let missingWindowContent = WindowContentView<ViewModelUI<StringNamespace>>(id: nil)

        #expect(windowContent.viewModelUI?.viewModel === registryViewModel)
        #expect(missingWindowContent.viewModelUI == nil)

        _ = windowContent.body
        _ = missingWindowContent.body
        _ = StringNamespace.windowGroup()

        ViewModelUIRegistry.remove(id: registryViewModelUI.id)

        let removedViewModelUI: ViewModelUI<StringNamespace>? = ViewModelUIRegistry.get(id: registryViewModelUI.id)
        #expect(removedViewModelUI == nil)

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

        #expect(await waitUntil {
            presentationWindow.rootViewController?.presentedViewController != nil
        })

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

        #expect(await waitUntil {
            sheetWindow.rootViewController?.presentedViewController != nil
        })

        sheetState.viewModelUI = nil
        await renderHostedView()
    }
}
#endif
