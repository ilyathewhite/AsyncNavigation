import SwiftUI
import Testing
@testable import AsyncNavigation

extension AsyncNavigationTestSuites {
    @MainActor
    @Suite struct SwiftUIUtilityTests {}
}

extension AsyncNavigationTestSuites.SwiftUIUtilityTests {
    @Test
    func viewModelUIMirrorsViewModelIdentityAndCancellation() {
        let viewModel = TestStringViewModel(name: "screen")
        let viewModelUI = ViewModelUI<StringNamespace>(viewModel)
        let duplicate = ViewModelUI<StringNamespace>(viewModel)
        let different = ViewModelUI<StringNamespace>(TestStringViewModel(name: "other"))
        let optionalViewModel: TestStringViewModel? = viewModel

        #expect(viewModelUI.id == viewModel.id)
        #expect(viewModelUI == duplicate)
        #expect(viewModelUI != different)
        #expect(viewModelUI.anyViewModel === viewModel)
        _ = viewModelUI.value

        _ = viewModelUI.makeView()
        _ = viewModelUI.makeAnyView()

        viewModelUI.cancel()

        #expect(viewModel.isCancelled)
        #expect(ViewModelUI<StringNamespace>(optionalViewModel) != nil)
        #expect(ViewModelUI<StringNamespace>(nil) == nil)
    }

    @Test
    func navigationEnvironmentValuesAndPreferenceKeyBehaveAsExpected() {
        let first = ViewModelUI<StringNamespace>(TestStringViewModel(name: "first"))
        let sameIdentity = ViewModelUI<StringNamespace>(first.viewModel)
        let different = ViewModelUI<StringNamespace>(TestStringViewModel(name: "different"))
        let expectedStack = NavigationPathStack(value: [first])
        let sameStack = NavigationPathStack(value: [sameIdentity])
        let differentStack = NavigationPathStack(value: [different])
        var reducedValue: NavigationPathStack?
        var environment = EnvironmentValues()
        var didCallBack = false

        #expect(expectedStack == sameStack)
        #expect(expectedStack != differentStack)

        NavigationPathStackKey.reduce(value: &reducedValue) { expectedStack }
        NavigationPathStackKey.reduce(value: &reducedValue) { differentStack }

        #expect(reducedValue == expectedStack)

        environment.backAction = {
            didCallBack = true
        }
        environment.backAction?()

        #expect(didCallBack)

#if os(macOS)
        var didDismissWindow = false
        environment.dismissModalWindowAction = {
            didDismissWindow = true
        }
        environment.dismissModalWindowAction?()

        #expect(didDismissWindow)
#endif
    }

    @Test
    func presentationHelpersCanBeConstructedAndShowUICancelsOnDismiss() {
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

        #expect(binding.wrappedValue)
        #expect(!noChildBinding.wrappedValue)

        binding.wrappedValue = false

        #expect(viewModel.isCancelled)

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

    @Test
    func navigationFlowsAndWindowHelpersBuildViews() {
        let root = TestStringViewModel(name: "root")
        let rootNode = RootNavigationNode<StringNamespace>(root)
        let flow = NavigationFlow(rootNode) { _, _ in }

        _ = flow.addNavigation(ViewModelUI<StringNamespace>(root))
        _ = Text("Root").addNavigation(StringNamespace.self)

#if os(macOS)
        let modalViewModel = TestStringViewModel(name: "modal")
        let modalViewModelUI = ViewModelUI<StringNamespace>(modalViewModel)
        _ = CustomNavigationFlow(rootNode) { _, _ in }

        ViewModelUIRegistry.add(modalViewModelUI)
        let storedViewModelUI: ViewModelUI<StringNamespace>? = ViewModelUIRegistry.get(id: modalViewModelUI.id)

        #expect(storedViewModelUI?.viewModel === modalViewModel)

        let windowContent = WindowContentView<ViewModelUI<StringNamespace>>(id: modalViewModelUI.id)
        let missingWindowContent = WindowContentView<ViewModelUI<StringNamespace>>(id: nil)

        #expect(windowContent.viewModelUI?.viewModel === modalViewModel)
        #expect(missingWindowContent.viewModelUI == nil)

        _ = windowContent.body
        _ = missingWindowContent.body
        _ = StringNamespace.windowGroup()

        ViewModelUIRegistry.remove(id: modalViewModelUI.id)

        let removedViewModelUI: ViewModelUI<StringNamespace>? = ViewModelUIRegistry.get(id: modalViewModelUI.id)
        #expect(removedViewModelUI == nil)
#endif
    }

#if os(macOS)
    @Test
    func hostedSwiftUIContainersRenderNavigationAndWindowPaths() async {
        let flowRoot = TestStringViewModel(name: "flow-root")
        let pushed = TestStringViewModel(name: "pushed")
        var didRunFlow = false
        let flowWindow = hostInWindow(
            NavigationFlow(RootNavigationNode<StringNamespace>(flowRoot)) { _, proxy in
                _ = proxy.push(ViewModelUI<StringNamespace>(pushed))
                didRunFlow = true
            }
        )

        defer {
            flowWindow.close()
        }

        await renderHostedView()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            flowRoot.publish("go")
        }
        #expect(await waitUntil { didRunFlow })
        await renderHostedView()
        flowRoot.cancel()

        let customRoot = TestStringViewModel(name: "custom-root")
        let customPushed = TestStringViewModel(name: "custom-pushed")
        var didRunCustomFlow = false
        let customWindow = hostInWindow(
            CustomNavigationFlow(RootNavigationNode<StringNamespace>(customRoot)) { _, proxy in
                _ = proxy.push(ViewModelUI<StringNamespace>(customPushed))
                didRunCustomFlow = true
            }
        )

        defer {
            customWindow.close()
        }

        await renderHostedView()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            customRoot.publish("go")
        }
        #expect(await waitUntil { didRunCustomFlow })
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
        #expect(storedViewModelUI?.viewModel === modalViewModel)

        presentationState.isPresented = false
        presentationState.viewModelUI = nil
        await renderHostedView()

        let removedViewModelUI: ViewModelUI<StringNamespace>? = ViewModelUIRegistry.get(id: modalViewModelUI.id)
        #expect(removedViewModelUI == nil)

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
