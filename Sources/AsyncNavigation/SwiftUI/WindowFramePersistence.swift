#if os(macOS)
import AppKit
import SwiftUI

public extension View {
    /// Saves the containing window's frame and restores it before revealing a newly opened window.
    /// A nil key disables persistence. Use a stable key independent of the presentation's view model ID.
    @MainActor
    func persistWindowFrame(key: String?, defaults: UserDefaults = .standard) -> some View {
        persistWindowFrame(key.map { key in
            Binding(
                get: { defaults.string(forKey: key) ?? "" },
                set: { defaults.set($0, forKey: key) }
            )
        })
    }

    /// Uses custom storage for the AppKit frame descriptor. An empty string means no saved frame.
    /// Supply a binding backed by persistence storage; a nil binding disables persistence.
    @MainActor
    func persistWindowFrame(_ savedFrame: Binding<String>?) -> some View {
        background {
            if let savedFrame {
                WindowFrameStorage(savedFrame: savedFrame)
            }
        }
    }
}

// Persist geometry independently of SwiftUI scene restoration, which would reopen windows without live stores.
private struct WindowFrameStorage: NSViewRepresentable {
    let savedFrame: Binding<String>

    func makeNSView(context: Context) -> FrameView {
        FrameView(savedFrame: savedFrame)
    }

    func updateNSView(_ nsView: FrameView, context: Context) {
        nsView.savedFrame = savedFrame
    }

    static func dismantleNSView(_ nsView: FrameView, coordinator: ()) {
        nsView.stopSavingFrame()
    }

    final class FrameView: NSView {
        var savedFrame: Binding<String>
        private weak var configuredWindow: NSWindow?
        private var hasRestoredFrame = false
        private var pendingAppearance: (alpha: CGFloat, animation: NSWindow.AnimationBehavior)?

        init(savedFrame: Binding<String>) {
            self.savedFrame = savedFrame
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window !== configuredWindow else { return }
            stopSavingFrame()
            guard let window else { return }
            configuredWindow = window
            if !window.isVisible {
                // SwiftUI places the window before our first update; conceal that intermediate frame.
                pendingAppearance = (window.alphaValue, window.animationBehavior)
                window.animationBehavior = .none
                window.alphaValue = 0
            }
            // Restore after SwiftUI's initial placement, including when the app opens in the background.
            NotificationCenter.default.addObserver(
                self, selector: #selector(windowDidUpdate), name: NSWindow.didUpdateNotification, object: window
            )
            NotificationCenter.default.addObserver(
                self, selector: #selector(windowWillClose), name: NSWindow.willCloseNotification, object: window
            )
            for notification in [NSWindow.didMoveNotification, NSWindow.didResizeNotification] {
                NotificationCenter.default.addObserver(
                    self, selector: #selector(windowFrameDidChange), name: notification, object: window
                )
            }
            restoreFrameIfVisible()
        }

        @objc private func windowDidUpdate(_ notification: Notification) {
            restoreFrameIfVisible()
        }

        private func restoreFrameIfVisible() {
            guard let configuredWindow, configuredWindow.isVisible else { return }
            NotificationCenter.default.removeObserver(
                self, name: NSWindow.didUpdateNotification, object: configuredWindow
            )
            configuredWindow.contentView?.layoutSubtreeIfNeeded()
            let frame = savedFrame.wrappedValue
            if !frame.isEmpty {
                configuredWindow.setFrame(from: frame)
            }
            configuredWindow.contentView?.layoutSubtreeIfNeeded()
            hasRestoredFrame = true
            restoreAppearance()
        }

        private func restoreAppearance() {
            guard let configuredWindow, let pendingAppearance else { return }
            self.pendingAppearance = nil
            configuredWindow.alphaValue = pendingAppearance.alpha
            configuredWindow.animationBehavior = pendingAppearance.animation
        }

        @objc private func windowFrameDidChange(_ notification: Notification) {
            saveFrame()
        }

        private func saveFrame() {
            guard hasRestoredFrame, let configuredWindow,
                  configuredWindow.frame.width > 0, configuredWindow.frame.height > 0 else { return }
            savedFrame.wrappedValue = configuredWindow.frameDescriptor
        }

        @objc private func windowWillClose(_ notification: Notification) {
            stopSavingFrame()
        }

        func stopSavingFrame() {
            saveFrame()
            if pendingAppearance != nil {
                // Cancellation before the first update must not reveal an unfinished window.
                configuredWindow?.orderOut(nil)
                restoreAppearance()
            }
            configuredWindow = nil
            hasRestoredFrame = false
            NotificationCenter.default.removeObserver(self)
        }
    }
}

#endif
