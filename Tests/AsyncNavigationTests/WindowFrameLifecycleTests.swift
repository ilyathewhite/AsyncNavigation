#if os(macOS)
import AppKit
import SwiftUI
import Testing
import AsyncNavigation

extension AsyncNavigationTestSuites {
    @MainActor
    @Suite(.serialized) struct WindowFrameLifecycleTests {}
}

extension AsyncNavigationTestSuites.WindowFrameLifecycleTests {
    @Test
    func firstRevealUsesSavedFrameAndRestoresAppearance() async throws {
        let host = FrameTestHost()
        defer { host.close() }
        let expected = try host.saveFrameOnCurrentScreen()
        host.window.alphaValue = 0.75
        host.window.animationBehavior = .utilityWindow
        host.mount()
        try #require(await waitUntil { host.window.alphaValue == 0 })
        #expect(host.window.animationBehavior == .none)
        #expect(host.writes == 0)

        host.show()
        try #require(await waitUntil { host.window.alphaValue == 0.75 })
        #expect(host.window.animationBehavior == .utilityWindow)
        #expect(!host.window.revealedFrames.isEmpty)
        for frame in host.window.revealedFrames {
            expectEqualFrames(frame, expected)
        }
        expectEqualFrames(host.window.frame, expected)
    }

    @Test(arguments: [false, true])
    func cancellationBeforePlacementDoesNotRevealOrSaveWindow(closeWindow: Bool) async throws {
        let host = FrameTestHost()
        defer { host.close() }
        _ = try host.saveFrameOnCurrentScreen()
        let savedFrame = host.savedFrame
        host.window.alphaValue = 0.75
        host.window.animationBehavior = .utilityWindow
        host.mount()
        try #require(await waitUntil { host.window.alphaValue == 0 })

        if closeWindow {
            host.window.close()
        }
        else {
            host.removePersistence()
        }
        try #require(await waitUntil { host.window.alphaValue == 0.75 })
        #expect(!host.window.isVisible)
        #expect(host.window.revealedFrames.isEmpty)
        #expect(host.window.animationBehavior == .utilityWindow)
        #expect(host.savedFrame == savedFrame)
        #expect(host.writes == 0)

        // Notifications arriving after teardown must neither restore nor overwrite the saved geometry.
        host.window.setFrameOrigin(NSPoint(x: 30, y: 40))
        host.window.setContentSize(NSSize(width: 500, height: 350))
        host.window.update()
        await renderHostedView()
        #expect(host.savedFrame == savedFrame)
        #expect(host.writes == 0)
        #expect(!host.window.isVisible)
    }

    @Test
    func removingPersistenceStopsSavingFromTheOldWindow() async throws {
        let host = FrameTestHost()
        defer { host.close() }
        host.mount()
        try #require(await waitUntil { host.window.alphaValue == 0 })
        host.show()
        try #require(await waitUntil { host.window.alphaValue == 1 })
        host.window.setContentSize(NSSize(width: 440, height: 320))
        host.removePersistence()
        try #require(await waitUntil { host.writes > 0 })
        await renderHostedView()
        let writes = host.writes
        let savedFrame = host.savedFrame

        host.window.setContentSize(NSSize(width: 600, height: 420))
        host.window.setFrameOrigin(NSPoint(x: 20, y: 30))
        host.window.close()
        await renderHostedView()
        #expect(host.writes == writes)
        #expect(host.savedFrame == savedFrame)
    }

    @Test(arguments: ["", "not a window frame", "0 0 0 0 0 0 0 0"])
    func unusableSavedFramesLeaveAUsableWindow(savedFrame: String) async throws {
        let host = FrameTestHost()
        defer { host.close() }
        host.savedFrame = savedFrame
        host.mount()
        try #require(await waitUntil { host.window.alphaValue == 0 })
        host.show()
        try #require(await waitUntil { host.window.alphaValue == 1 })
        let frame = host.window.frame
        #expect(frame.width >= 320)
        #expect(frame.height >= 240)
        #expect(NSScreen.screens.contains { $0.visibleFrame.intersects(frame) })
        #expect(host.window.revealedFrames.allSatisfy { $0 == frame })
    }

    @Test
    func frameFromDisconnectedDisplayIsRecoveredBeforeReveal() async throws {
        let host = FrameTestHost()
        defer { host.close() }
        // AppKit descriptors include both window and screen rectangles. This screen no longer exists.
        host.savedFrame = "50100 50100 440 342 50000 50000 1920 1080 "
        host.mount()
        try #require(await waitUntil { host.window.alphaValue == 0 })
        host.show()
        try #require(await waitUntil { host.window.alphaValue == 1 })
        let frame = host.window.frame
        #expect(NSScreen.screens.contains { $0.visibleFrame.intersects(frame) })
        #expect(frame.width == 440)
        #expect(frame.height == 342)
        #expect(!host.window.revealedFrames.isEmpty)
        #expect(host.window.revealedFrames.allSatisfy { $0 == frame })
    }

    @Test(arguments: [false, true])
    func nilStorageLeavesWindowAppearanceAlone(useKey: Bool) async throws {
        let host = FrameTestHost()
        defer { host.close() }
        let content = Text("No persistence").frame(width: 320, height: 240)
            .onAppear { host.appearances += 1 }
        if useKey {
            host.mount(AnyView(content.persistWindowFrame(key: nil)))
        }
        else {
            host.mount(AnyView(content.persistWindowFrame(nil)))
        }
        host.show()
        try #require(await waitUntil { host.appearances > 0 })
        #expect(host.window.alphaValue == 1)
        #expect(host.window.animationBehavior == .default)
        host.window.setContentSize(NSSize(width: 440, height: 320))
        #expect(host.writes == 0)
    }
}

@MainActor
private final class FrameTestHost {
    let window = RevealRecordingWindow(
        contentRect: NSRect(x: 50, y: 50, width: 320, height: 240),
        styleMask: [.titled, .closable, .resizable],
        backing: .buffered,
        defer: false
    )
    var savedFrame = ""
    var writes = 0
    var appearances = 0
    private var hostingView: NSHostingView<AnyView>?

    init() {
        window.isReleasedWhenClosed = false
    }

    func saveFrameOnCurrentScreen() throws -> NSRect {
        let screen = try #require(NSScreen.main)
        let original = window.frame
        window.setContentSize(NSSize(width: 440, height: 320))
        window.setFrameOrigin(NSPoint(x: screen.visibleFrame.minX + 110, y: screen.visibleFrame.minY + 130))
        let expected = window.frame
        savedFrame = window.frameDescriptor
        window.setFrame(original, display: false)
        return expected
    }

    func mount() {
        let binding = Binding(
            get: { self.savedFrame },
            set: {
                self.savedFrame = $0
                self.writes += 1
            }
        )
        mount(AnyView(Text("Window content")
            .frame(minWidth: 320, maxWidth: .infinity, minHeight: 240, maxHeight: .infinity)
            .persistWindowFrame(binding)))
    }

    func mount(_ content: AnyView) {
        let hostingView = NSHostingView(rootView: content)
        self.hostingView = hostingView
        window.contentView = hostingView
        hostingView.layoutSubtreeIfNeeded()
    }

    func show() {
        window.orderFront(nil)
        // SwiftPM has no application event loop to send the first window update for us.
        window.update()
    }

    func close() {
        window.close()
        window.contentView = nil
        hostingView = nil
    }

    func removePersistence() {
        hostingView?.rootView = AnyView(Text("Detached").frame(width: 320, height: 240))
        hostingView?.layoutSubtreeIfNeeded()
    }
}

@MainActor
private final class RevealRecordingWindow: NSWindow {
    var revealedFrames: [NSRect] = []

    override var alphaValue: CGFloat {
        didSet {
            if isVisible && alphaValue > 0 {
                revealedFrames.append(frame)
            }
        }
    }
}

@MainActor
private func expectEqualFrames(_ actual: NSRect, _ expected: NSRect) {
    #expect(abs(actual.minX - expected.minX) < 2)
    #expect(abs(actual.minY - expected.minY) < 2)
    #expect(actual.size == expected.size)
}
#endif
