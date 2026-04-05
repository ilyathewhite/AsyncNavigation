import AsyncNavigation
import Foundation
import SwiftUI
import Combine
import CombineEx
import Testing

@Suite
enum AsyncNavigationTestSuites {}

@MainActor
final class TestStringViewModel: BaseViewModel<String> {
    let name: String
    private(set) var cancelCallCount = 0

    init(name: String = UUID().uuidString) {
        self.name = name
        super.init()
    }

    override func cancel() {
        cancelCallCount += 1
        super.cancel()
    }
}

@MainActor
final class TestIntViewModel: BaseViewModel<Int> {
    let seed: Int
    private(set) var cancelCallCount = 0

    init(seed: Int = 0) {
        self.seed = seed
        super.init()
    }

    override func cancel() {
        cancelCallCount += 1
        super.cancel()
    }
}

@MainActor
final class DefaultStringViewModel: BasicViewModel {
    typealias PublishedValue = String

    let id = UUID()
    var isCancelled = false
    var hasRequest = false
    let publishedValue = PassthroughSubject<String, Cancel>()
    var children: [String: any BasicViewModel] = [:]
}

enum StringNamespace: ViewModelUINamespace {
    typealias ViewModel = TestStringViewModel

    struct ContentView: ViewModelContentView {
        let viewModel: TestStringViewModel

        init(_ viewModel: TestStringViewModel) {
            self.viewModel = viewModel
        }

        var body: some View {
            Text(viewModel.name)
        }
    }
}

enum IntNamespace: ViewModelUINamespace {
    typealias ViewModel = TestIntViewModel

    struct ContentView: ViewModelContentView {
        let viewModel: TestIntViewModel

        init(_ viewModel: TestIntViewModel) {
            self.viewModel = viewModel
        }

        var body: some View {
            Text("\(viewModel.seed)")
        }
    }
}

struct TestHostView: View {
    let childUI: ViewModelUI<StringNamespace>?

    var body: some View {
        Text("Host")
    }
}

enum TestError: Error, Equatable {
    case boom
}

@MainActor
func flushMainQueue() async {
    await withCheckedContinuation { continuation in
        DispatchQueue.main.async {
            continuation.resume()
        }
    }
}

@MainActor
func waitUntil(
    timeout: TimeInterval = 1,
    pollIntervalNanoseconds: UInt64 = 10_000_000,
    condition: @escaping @MainActor () -> Bool
) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() {
        if deadline <= Date() {
            return false
        }
        await flushMainQueue()
        try? await Task.sleep(nanoseconds: pollIntervalNanoseconds)
    }
    return true
}

@MainActor
final class HostedPresentationState: ObservableObject {
    @Published var isPresented = false
    @Published var viewModelUI: ViewModelUI<StringNamespace>?
}

@MainActor
struct HostedPresentationView: View {
    @ObservedObject var state: HostedPresentationState

    var body: some View {
        Color.clear
            .frame(width: 160, height: 120)
            .fullScreenOrWindow(
                isPresented: $state.isPresented,
                viewModelUI: state.viewModelUI
            ) {
                Text("Presented")
            }
    }
}

@MainActor
struct HostedSheetView: View {
    @ObservedObject var state: HostedPresentationState

    var body: some View {
        let hostView = TestHostView(childUI: state.viewModelUI)
        return Color.clear
            .frame(width: 160, height: 120)
            .sheet(hostView, \.childUI) { viewModelUI in
                viewModelUI.makeView()
            }
    }
}

#if os(macOS)
import AppKit

@MainActor
func hostInWindow<V: View>(_ view: V) -> NSWindow {
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
        styleMask: [.titled, .closable],
        backing: .buffered,
        defer: false
    )
    window.isReleasedWhenClosed = false
    window.contentView = NSHostingView(rootView: view)
    window.makeKeyAndOrderFront(nil)
    return window
}

@MainActor
func renderHostedView() async {
    await flushMainQueue()
    await flushMainQueue()
}
#endif

#if os(iOS)
import UIKit

@MainActor
func hostInWindow<V: View>(_ view: V) -> UIWindow {
    let window = UIWindow(frame: UIScreen.main.bounds)
    window.rootViewController = UIHostingController(rootView: view)
    window.makeKeyAndVisible()
    return window
}

@MainActor
func renderHostedView() async {
    await flushMainQueue()
    await flushMainQueue()
}
#endif
