#if os(macOS)
import AppKit
import AsyncNavigation
import Observation
import SwiftUI

// A separate process is necessary to exercise SwiftUI scenes and AppKit restoration at launch.
@main
struct UtilityWindowTestApp: App {
    @NSApplicationDelegateAdaptor(TestAppDelegate.self) private var delegate
    @State private var driver = WindowTestDriver.shared

    var body: some Scene {
        WindowGroup("Document Test", id: "document") {
            VStack {
                if driver.showsPresenter {
                    Presenter(driver: driver)
                }
                else {
                    Text("Presenter removed")
                }
            }
            .frame(width: 320, height: 240)
        }

        .defaultLaunchBehavior(.presented)

        utilityWindow(TestUtility.self, defaults: driver.defaults)
            .defaultSize(width: 320, height: 240)

        // This scene must restore on relaunch, proving that restoration was actually attempted.
        WindowGroup("Restoration Control", id: "control", for: String.self) { _ in
            Text("Restoration control").frame(width: 250, height: 180)
        }
        .defaultLaunchBehavior(.suppressed)
        .commandsRemoved()
    }
}

@MainActor
final class TestAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { await WindowTestDriver.shared.run() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool { false }
}

private struct Presenter: View {
    let driver: WindowTestDriver
    @Environment(\.openWindow) private var openWindow
    var childUI: ViewModelUI<TestUtility>? { driver.child }

    var body: some View {
        Text("Document")
            .fullScreenOrWindow(self, \.childUI, isModal: false, windowFrameKey: driver.frameKey) {
                childUI?.makeView()
            }
            .onAppear { driver.openControl = { openWindow(id: "control", value: "saved-control") } }
    }
}

private enum TestUtility: ViewModelUINamespace {
    final class ViewModel: BaseViewModel<Int> {
        weak var window: NSWindow?
        var cancelledViewInitializations = 0
        var appeared = false
    }

    struct ContentView: ViewModelContentView {
        let viewModel: ViewModel

        init(_ viewModel: ViewModel) {
            self.viewModel = viewModel
            if viewModel.isCancelled { viewModel.cancelledViewInitializations += 1 }
        }

        var body: some View {
            Text("Utility content")
                .frame(minWidth: 320, maxWidth: .infinity, minHeight: 240, maxHeight: .infinity)
                .navigationTitle("Utility Test")
                .background(WindowProbe { viewModel.window = $0 })
                .onAppear { viewModel.appeared = true }
        }
    }
}

private struct WindowProbe: NSViewRepresentable {
    let attach: (NSWindow) -> Void

    func makeNSView(context: Context) -> ProbeView { ProbeView(attach: attach) }
    func updateNSView(_ view: ProbeView, context: Context) {}

    final class ProbeView: NSView {
        let attach: (NSWindow) -> Void

        init(attach: @escaping (NSWindow) -> Void) {
            self.attach = attach
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { attach(window) }
        }
    }
}

@MainActor
@Observable
private final class WindowTestDriver {
    static let shared = WindowTestDriver()
    let defaults: UserDefaults
    let frameKey = "document-A.utility"
    var child: ViewModelUI<TestUtility>?
    var showsPresenter = true
    var openControl: (() -> Void)?
    private var started = false
    private var failures: [String] = []
    private var checks: [String] = []
    private let mode: String
    private let reportURL: URL

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        mode = arguments[1]
        reportURL = URL(fileURLWithPath: arguments[2])
        defaults = UserDefaults(suiteName: arguments[3])!
        UserDefaults.standard.set(true, forKey: "NSQuitAlwaysKeepsWindows")
    }

    func run() async {
        guard !started else { return }
        started = true
        do {
            // Allow launch restoration to finish before inspecting the scene list.
            try await Task.sleep(for: .milliseconds(500))
            if mode == "relaunch" {
                try await wait("ordinary window restores after relaunch") {
                    self.visibleWindows.contains { $0.title == "Restoration Control" }
                }
                check(visibleWindows.count == 2, "utility window does not reopen after quitting with it open")
                check(child == nil, "relaunch has no utility view model")
                check(defaults.string(forKey: frameKey) != nil, "saved frame survives relaunch")
            }
            else {
                check(visibleWindows.allSatisfy { $0.title == "Document Test" },
                      "utility scene is suppressed at initial launch")
                if visibleWindows.isEmpty {
                    // Launch Services may start a document app without requesting an untitled document.
                    for menu in NSApp.mainMenu?.items.compactMap(\.submenu) ?? [] {
                        if let index = menu.items.firstIndex(where: { $0.keyEquivalent == "n" }) {
                            let item = menu.items[index]
                            if let action = item.action {
                                NSApp.sendAction(action, to: item.target, from: item)
                            }
                            break
                        }
                    }
                }
                try await wait("document presenter appears") { self.openControl != nil }
                if mode == "leave-open" {
                    let (_, window) = try await present()
                    window.setFrameOrigin(NSPoint(x: 130, y: 140))
                    openControl?()
                    try await wait("restoration control opens") { self.visibleWindows.count == 3 }
                    check(defaults.string(forKey: frameKey) != nil, "supplied defaults store the frame")
                    // Leave both auxiliary windows open and quit through AppKit's normal termination path.
                }
                else {
                    try await exerciseLifecycle()
                }
            }
        }
        catch {
            failures.append(String(describing: error))
        }
        let report = ["checks": checks, "failures": failures, "windows": visibleWindows.map(\.title)]
        do {
            let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: reportURL, options: .atomic)
        }
        catch {
            fatalError("Cannot write fixture report: \(error)")
        }
        NSApp.terminate(nil)
    }

    private var visibleWindows: [NSWindow] {
        NSApp.windows.filter { $0.isVisible && $0.styleMask.contains(.titled) }
    }

    private func exerciseLifecycle() async throws {
        let (first, firstWindow) = try await present()
        let screen = firstWindow.screen ?? NSScreen.main!
        firstWindow.setContentSize(NSSize(width: 440, height: 320))
        firstWindow.setFrameOrigin(NSPoint(x: screen.visibleFrame.minX + 110, y: screen.visibleFrame.minY + 130))
        let expected = firstWindow.frame
        firstWindow.performClose(nil)
        try await wait("title-bar close cancels the view model") { first.isCancelled }
        check(!firstWindow.isRestorable, "utility window disables native restoration")
        check(defaults.string(forKey: frameKey) != nil, "presenter forwards its frame key to supplied defaults")
        check(UserDefaults.standard.string(forKey: frameKey) == nil, "frame does not leak into standard defaults")
        child = nil
        try await Task.sleep(for: .milliseconds(100))

        let (reopened, reopenedWindow) = try await present()
        check(first.id != reopened.id, "reopening uses a fresh view model ID")
        check(abs(reopenedWindow.frame.minX - expected.minX) < 2, "reopening restores the horizontal position")
        check(abs(reopenedWindow.frame.minY - expected.minY) < 2, "reopening restores the vertical position")
        check(reopenedWindow.frame.size == expected.size, "reopening restores the size")
        check(!reopened.isCancelled, "reopened view model remains active")

        showsPresenter = false
        try await wait("removing presenter cancels its view model") { reopened.isCancelled }
        try await wait("removing presenter closes its utility window") { !reopenedWindow.isVisible }
        check(first.cancelledViewInitializations == 0, "closed presentation never rebuilds cancelled content")
        check(reopened.cancelledViewInitializations == 0, "owner removal never rebuilds cancelled content")
    }

    private func present() async throws -> (TestUtility.ViewModel, NSWindow) {
        let model = TestUtility.ViewModel()
        child = ViewModelUI<TestUtility>(model)
        try await wait("utility window appears") {
            model.appeared && model.window?.isVisible == true && model.window?.alphaValue == 1
        }
        return (model, model.window!)
    }

    private func check(_ condition: Bool, _ message: String) {
        checks.append(message)
        if !condition { failures.append(message) }
    }

    private func wait(_ message: String, condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(5)
        while !condition() {
            guard Date() < deadline else { throw FixtureFailure(message: message) }
            try await Task.sleep(for: .milliseconds(10))
        }
        checks.append(message)
    }
}

private struct FixtureFailure: Error, CustomStringConvertible {
    let message: String
    var description: String { "Timed out: \(message)" }
}
#else
@main
struct UtilityWindowTestApp {
    static func main() {}
}
#endif
