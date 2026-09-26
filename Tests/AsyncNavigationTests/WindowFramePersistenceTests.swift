#if os(macOS)
import AppKit
import SwiftUI
import Testing
import AsyncNavigation

extension AsyncNavigationTestSuites {
    @MainActor
    @Suite(.serialized) struct WindowFramePersistenceTests {}
}

extension AsyncNavigationTestSuites.WindowFramePersistenceTests {
    @Test(arguments: [false, true])
    func freshWindowsRestoreMovedAndResizedFrames(useUserDefaults: Bool) async throws {
        let suiteName = "AsyncNavigation.WindowFramePersistenceTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        var frame = ""
        let binding = Binding(get: { frame }, set: { frame = $0 })
        let key = "utility.frame"
        var appearances = 0

        @ViewBuilder
        func content() -> some View {
            let view = Text("Window content")
                .frame(minWidth: 320, maxWidth: .infinity, minHeight: 240, maxHeight: .infinity)
                .onAppear { appearances += 1 }
            if useUserDefaults {
                view.persistWindowFrame(key: key, defaults: defaults)
            }
            else {
                view.persistWindowFrame(binding)
            }
        }

        func openWindow() -> NSWindow {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: content())
            window.makeKeyAndOrderFront(nil)
            return window
        }

        let first = openWindow()
        defer { first.close() }
        let firstReady = await waitUntil { appearances >= 1 && first.alphaValue == 1 }
        try #require(firstReady)
        let screen = try #require(first.screen)
        first.setContentSize(NSSize(width: 440, height: 320))
        first.setFrameOrigin(NSPoint(x: screen.visibleFrame.minX + 100, y: screen.visibleFrame.minY + 150))
        await renderHostedView()
        let expectedFrame = first.frame
        first.close()
        let savedFrame = useUserDefaults ? defaults.string(forKey: key) ?? "" : frame
        #expect(!savedFrame.isEmpty)

        let reopened = openWindow()
        defer { reopened.close() }
        let reopenedReady = await waitUntil { appearances >= 2 && reopened.alphaValue == 1 }
        try #require(reopenedReady)
        #expect(abs(reopened.frame.minX - expectedFrame.minX) < 2)
        #expect(abs(reopened.frame.minY - expectedFrame.minY) < 2)
        #expect(reopened.frame.size == expectedFrame.size)
    }
}
#endif
