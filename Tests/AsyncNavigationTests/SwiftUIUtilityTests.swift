import SwiftUI
import XCTest
@testable import AsyncNavigation

final class SwiftUIUtilityTests: XCTestCase {
    @MainActor
    func testViewModelUIMirrorsViewModelIdentityAndCancellation() {
        let viewModel = TestStringViewModel(name: "screen")
        let viewModelUI = ViewModelUI<StringNamespace>(viewModel)
        let duplicate = ViewModelUI<StringNamespace>(viewModel)
        let different = ViewModelUI<StringNamespace>(TestStringViewModel(name: "other"))
        let optionalViewModel: TestStringViewModel? = viewModel

        XCTAssertEqual(viewModelUI.id, viewModel.id)
        XCTAssertEqual(viewModelUI, duplicate)
        XCTAssertNotEqual(viewModelUI, different)
        XCTAssertTrue(viewModelUI.anyViewModel === viewModel)
        _ = viewModelUI.value

        _ = viewModelUI.makeView()
        _ = viewModelUI.makeAnyView()

        viewModelUI.cancel()

        XCTAssertTrue(viewModel.isCancelled)
        XCTAssertNotNil(ViewModelUI<StringNamespace>(optionalViewModel))
        XCTAssertNil(ViewModelUI<StringNamespace>(nil))
    }

    @MainActor
    func testNavigationEnvironmentValuesAndPreferenceKeyBehaveAsExpected() {
        let first = ViewModelUI<StringNamespace>(TestStringViewModel(name: "first"))
        let sameIdentity = ViewModelUI<StringNamespace>(first.viewModel)
        let different = ViewModelUI<StringNamespace>(TestStringViewModel(name: "different"))
        let expectedStack = NavigationPathStack(value: [first])
        let sameStack = NavigationPathStack(value: [sameIdentity])
        let differentStack = NavigationPathStack(value: [different])
        var reducedValue: NavigationPathStack?
        var environment = EnvironmentValues()
        var didCallBack = false

        XCTAssertEqual(expectedStack, sameStack)
        XCTAssertNotEqual(expectedStack, differentStack)

        NavigationPathStackKey.reduce(value: &reducedValue) { expectedStack }
        NavigationPathStackKey.reduce(value: &reducedValue) { differentStack }

        XCTAssertEqual(reducedValue, expectedStack)

        environment.backAction = {
            didCallBack = true
        }
        environment.backAction?()

        XCTAssertTrue(didCallBack)

#if os(macOS)
        var didDismissWindow = false
        environment.dismissModalWindowAction = {
            didDismissWindow = true
        }
        environment.dismissModalWindowAction?()

        XCTAssertTrue(didDismissWindow)
#endif
    }

    @MainActor
    func testPresentationHelpersCanBeConstructedAndShowUICancelsOnDismiss() {
        let viewModel = TestStringViewModel(name: "sheet")
        let viewModelUI = ViewModelUI<StringNamespace>(viewModel)
        let hostView = TestHostView(childUI: viewModelUI)
        let binding = hostView.showUI(\.childUI)
        let noChildBinding = TestHostView(childUI: nil).showUI(\.childUI)
        var continuation: CheckedContinuation<String, Error>?
        let continuationBinding = Binding<CheckedContinuation<String, Error>?>(
            get: { continuation },
            set: { continuation = $0 }
        )

        XCTAssertTrue(binding.wrappedValue)
        XCTAssertFalse(noChildBinding.wrappedValue)

        binding.wrappedValue = false

        XCTAssertTrue(viewModel.isCancelled)

        _ = Text("Root").sheet(hostView, \.childUI) { viewModelUI in
            viewModelUI.makeView()
        }
        _ = Text("Root").taskAlert(
            "Alert",
            continuationBinding,
            actions: { complete in
                Button("OK") {
                    complete("done")
                }
            },
            message: {
                Text("Message")
            }
        )
        _ = Text("Root").fullScreenOrWindow(hostView, \.childUI) {
            Text("Presented")
        }
    }

    @MainActor
    func testNavigationFlowsAndWindowHelpersBuildViews() {
        let root = TestStringViewModel(name: "root")
        let rootNode = RootNavigationNode<StringNamespace>(root)
        let flow = NavigationFlow(rootNode) { _, _ in }

        _ = flow.addNavigation(ViewModelUI<StringNamespace>(root))
        _ = flow.body
        _ = Text("Root").addNavigation(StringNamespace.self)

#if os(macOS)
        let modalViewModel = TestStringViewModel(name: "modal")
        let modalViewModelUI = ViewModelUI<StringNamespace>(modalViewModel)
        let customFlow = CustomNavigationFlow(rootNode) { _, _ in }

        ViewModelUIRegistry.add(modalViewModelUI)
        let storedViewModelUI: ViewModelUI<StringNamespace>? = ViewModelUIRegistry.get(id: modalViewModelUI.id)

        XCTAssertTrue(storedViewModelUI?.viewModel === modalViewModel)

        let windowContent = WindowContentView<ViewModelUI<StringNamespace>>(id: modalViewModelUI.id)
        let missingWindowContent = WindowContentView<ViewModelUI<StringNamespace>>(id: nil)

        XCTAssertTrue(windowContent.viewModelUI?.viewModel === modalViewModel)
        XCTAssertNil(missingWindowContent.viewModelUI)

        _ = customFlow.body
        _ = windowContent.body
        _ = missingWindowContent.body
        _ = StringNamespace.windowGroup()

        ViewModelUIRegistry.remove(id: modalViewModelUI.id)

        let removedViewModelUI: ViewModelUI<StringNamespace>? = ViewModelUIRegistry.get(id: modalViewModelUI.id)
        XCTAssertNil(removedViewModelUI)
#endif
    }

#if os(macOS)
    @MainActor
    func testHostedSwiftUIContainersRenderNavigationAndWindowPaths() async {
        let flowRoot = TestStringViewModel(name: "flow-root")
        let pushed = TestStringViewModel(name: "pushed")
        let flowExpectation = expectation(description: "navigation flow run")
        let flowWindow = hostInWindow(
            NavigationFlow(RootNavigationNode<StringNamespace>(flowRoot)) { _, proxy in
                _ = proxy.push(ViewModelUI<StringNamespace>(pushed))
                flowExpectation.fulfill()
            }
        )

        defer {
            flowWindow.close()
        }

        await renderHostedView()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            flowRoot.publish("go")
        }
        await fulfillment(of: [flowExpectation], timeout: 1)
        await renderHostedView()
        flowRoot.cancel()

        let customRoot = TestStringViewModel(name: "custom-root")
        let customPushed = TestStringViewModel(name: "custom-pushed")
        let customExpectation = expectation(description: "custom flow run")
        let customWindow = hostInWindow(
            CustomNavigationFlow(RootNavigationNode<StringNamespace>(customRoot)) { _, proxy in
                _ = proxy.push(ViewModelUI<StringNamespace>(customPushed))
                customExpectation.fulfill()
            }
        )

        defer {
            customWindow.close()
        }

        await renderHostedView()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            customRoot.publish("go")
        }
        await fulfillment(of: [customExpectation], timeout: 1)
        await renderHostedView()
        customRoot.cancel()

        let presentationState = HostedPresentationState()
        let presentationWindow = hostInWindow(HostedPresentationView(state: presentationState))

        defer {
            presentationWindow.close()
        }

        await renderHostedView()

        let modalViewModel = TestStringViewModel(name: "modal")
        let modalViewModelUI = ViewModelUI<StringNamespace>(modalViewModel)
        presentationState.viewModelUI = modalViewModelUI
        presentationState.isPresented = true

        await renderHostedView()

        let storedViewModelUI: ViewModelUI<StringNamespace>? = ViewModelUIRegistry.get(id: modalViewModelUI.id)
        XCTAssertTrue(storedViewModelUI?.viewModel === modalViewModel)

        presentationState.isPresented = false
        presentationState.viewModelUI = nil
        await renderHostedView()

        let removedViewModelUI: ViewModelUI<StringNamespace>? = ViewModelUIRegistry.get(id: modalViewModelUI.id)
        XCTAssertNil(removedViewModelUI)

        let contentViewWindow = hostInWindow(
            WindowContentView<ViewModelUI<StringNamespace>>.ContentView(viewModelUI: modalViewModelUI)
        )

        await renderHostedView()
        modalViewModel.cancel()
        await renderHostedView()
        contentViewWindow.close()
        await renderHostedView()
    }
#endif
}
