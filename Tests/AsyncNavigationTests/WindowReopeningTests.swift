#if os(macOS)
import Foundation
import SwiftUI
import Testing
@testable import AsyncNavigation

@MainActor
private final class ReopeningViewModel: BasicViewModel {
    typealias PublishedValue = String

    let id = UUID()
    let publishedValue = PublishedValues<String>()
    var children: [String: any BasicViewModel] = [:]
    var cancelledViewInitializations = 0
    var appearedWithInstance: ObjectIdentifier?
}

private enum ReopeningNamespace: ViewModelUINamespace {
    typealias ViewModel = ReopeningViewModel

    struct ContentView: ViewModelContentView {
        let viewModel: ReopeningViewModel
        @State private var initialInstance: ObjectIdentifier

        init(_ viewModel: ReopeningViewModel) {
            self.viewModel = viewModel
            _initialInstance = State(initialValue: ObjectIdentifier(viewModel))
            if viewModel.isCancelled {
                viewModel.cancelledViewInitializations += 1
            }
        }

        var body: some View {
            Text("Window content")
                .onAppear { viewModel.appearedWithInstance = initialInstance }
        }
    }
}

extension AsyncNavigationTestSuites {
    @MainActor
    @Suite(.serialized) struct WindowReopeningTests {}
}

extension AsyncNavigationTestSuites.WindowReopeningTests {
    @Test
    func sharedFrameKeyDoesNotShareStoresOrDismissActions() {
        let frameKey = "document.utility"
        let first = ViewModelUI<ReopeningNamespace>(ReopeningViewModel())
        let reopened = ViewModelUI<ReopeningNamespace>(ReopeningViewModel())
        #expect(first.id != reopened.id)
        ViewModelUIRegistry.add(first, frameKey: frameKey)
        ViewModelUIRegistry.add(reopened, frameKey: frameKey)
        defer {
            ViewModelUIRegistry.remove(id: first.id)
            ViewModelUIRegistry.remove(id: reopened.id)
        }
        let firstContent = WindowContentView<ViewModelUI<ReopeningNamespace>>(id: first.id)
        let reopenedContent = WindowContentView<ViewModelUI<ReopeningNamespace>>(id: reopened.id)
        #expect(firstContent.viewModelUI?.viewModel === first.viewModel)
        #expect(reopenedContent.viewModelUI?.viewModel === reopened.viewModel)
        #expect(firstContent.frameKey == frameKey)
        #expect(reopenedContent.frameKey == frameKey)

        var closeRequests = 0
        ViewModelUIRegistry.setDismissAction(id: reopened.id) { closeRequests += 1 }
        first.cancel()
        ViewModelUIRegistry.remove(id: first.id)
        ViewModelUIRegistry.removeDismissAction(id: first.id)
        ViewModelUIRegistry.requestDismiss(id: reopened.id)
        #expect(closeRequests == 1)
        #expect(!reopened.viewModel.isCancelled)
        #expect(ViewModelUIRegistry.frameKey(id: first.id) == nil)
        #expect(ViewModelUIRegistry.frameKey(id: reopened.id) == frameKey)
        // A constructed scene keeps its frame key while cancellation removes its registry entry.
        #expect(firstContent.frameKey == frameKey)
    }

    @Test
    func newPresentationsStartWithFreshViewState() async {
        for _ in 0..<3 {
            let viewModel = ReopeningViewModel()
            ViewModelUIRegistry.add(ViewModelUI<ReopeningNamespace>(viewModel), frameKey: "document.utility")
            let window = hostInWindow(WindowContentView<ViewModelUI<ReopeningNamespace>>(id: viewModel.id))
            defer {
                window.close()
                ViewModelUIRegistry.remove(id: viewModel.id)
            }
            let appeared = await waitUntil { viewModel.appearedWithInstance != nil }
            #expect(appeared)
            #expect(viewModel.appearedWithInstance == ObjectIdentifier(viewModel))
            viewModel.cancel()
            await renderHostedView()
            #expect(viewModel.cancelledViewInitializations == 0)
        }
    }

    @Test
    func cancelledPresentationDoesNotBuildFeatureContent() async {
        let viewModel = ReopeningViewModel()
        ViewModelUIRegistry.add(ViewModelUI<ReopeningNamespace>(viewModel))
        viewModel.cancel()
        let window = hostInWindow(WindowContentView<ViewModelUI<ReopeningNamespace>>(id: viewModel.id))
        defer {
            window.close()
            ViewModelUIRegistry.remove(id: viewModel.id)
        }
        await renderHostedView()
        #expect(viewModel.cancelledViewInitializations == 0)
        #expect(viewModel.appearedWithInstance == nil)
    }
}
#endif
