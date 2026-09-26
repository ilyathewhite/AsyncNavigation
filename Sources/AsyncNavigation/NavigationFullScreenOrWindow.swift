//
//  NavigationFullScreenOrWindow.swift
//
//  Created by Ilya Belenkiy on 3/28/23.
//

import Foundation
import os
import SwiftUI

@MainActor
enum ViewModelUIRegistry {
    private struct Presentation {
        let viewModelUI: any ViewModelUIContainer
        let frameKey: String?
    }

    private static var dict: [UUID: Presentation] = [:]
    private static var dismissActions: [UUID: () -> Void] = [:]

    static func add(_ viewModelUI: any ViewModelUIContainer, frameKey: String? = nil) {
        guard dict[viewModelUI.id] == nil else { return }
        dict[viewModelUI.id] = Presentation(viewModelUI: viewModelUI, frameKey: frameKey)
    }

    static func remove(id: UUID) {
        dict.removeValue(forKey: id)
        removeDismissAction(id: id)
    }

    static func setDismissAction(id: UUID, action: @escaping () -> Void) {
        dismissActions[id] = action
    }

    static func removeDismissAction(id: UUID) {
        dismissActions.removeValue(forKey: id)
    }

    static func requestDismiss(id: UUID) {
        if let action = dismissActions[id] {
            action()
        }
        else {
            dict[id]?.viewModelUI.cancel()
        }
    }

    static func frameKey(id: UUID) -> String? {
        dict[id]?.frameKey
    }

    static func get<C: ViewModelUIContainer>(id: UUID) -> C? {
        guard let anyViewModelUI = dict[id]?.viewModelUI else { return nil }
        guard let viewModelUI = anyViewModelUI as? C else {
            assertionFailure()
            return nil
        }
        return viewModelUI
    }
}

// Sheet or Window

#if os(macOS)

private struct DismissModalWindowActionKey: EnvironmentKey {
    static var defaultValue: (() -> Void)? { nil }
}

public extension EnvironmentValues {
    var dismissModalWindowAction: (() -> Void)? {
        get { self[DismissModalWindowActionKey.self] }
        set { self[DismissModalWindowActionKey.self] = newValue }
    }
}

#endif

struct FullScreenOrWindow<C: ViewModelUIContainer, V: View>: ViewModifier {
#if os(macOS)
    @Environment(\.openWindow) private var openWindow
    @State private var id: UUID?
#endif
    
    let isPresented: Binding<Bool>
    let viewModelUI: C?
    let isModal: Bool
    let windowFrameKey: String?
    let presentedContent: () -> V?
    
#if os(macOS)
    var canDismissModalWindow: Bool {
        isModal && isPresented.wrappedValue
    }
#endif
    
    init(
        isPresented: Binding<Bool>,
        viewModelUI: C?,
        isModal: Bool,
        windowFrameKey: String?,
        content: @escaping () -> V?
    ) {
        self.isPresented = isPresented
        self.viewModelUI = viewModelUI
        self.isModal = isModal
        self.windowFrameKey = windowFrameKey
        self.presentedContent = content
    }

    func body(content: Content) -> some View {
#if os(iOS)
        content.fullScreenCover(isPresented: isPresented, content: presentedContent)
#else
        content.onChange(of: viewModelUI) { _, viewModelUI in
            if let viewModelUI {
                id = viewModelUI.id
                ViewModelUIRegistry.add(viewModelUI, frameKey: windowFrameKey)
                openWindow(id: C.Nsp.ViewModel.viewModelDefaultKey, value: viewModelUI.id)
            }
            else {
                if let id {
                    ViewModelUIRegistry.remove(id: id)
                }
            }
        }
        .overlay {
            if isModal, id != nil, let viewModelUI, !viewModelUI.viewModel.isCancelled {
                Color.primary.opacity(0.1)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        ViewModelUIRegistry.requestDismiss(id: viewModelUI.id)
                    }
            }
        }
        .onDisappear {
            if let id {
                ViewModelUIRegistry.remove(id: id)
            }
            id = nil
            viewModelUI?.cancel()
        }
        .transformEnvironment(\.dismissModalWindowAction) { action in
            if let prevAction = action {
                action = {
                    prevAction()
                    if canDismissModalWindow, let viewModelUI {
                        ViewModelUIRegistry.requestDismiss(id: viewModelUI.id)
                    }
                }
            }
            else if canDismissModalWindow, let viewModelUI {
                action = { ViewModelUIRegistry.requestDismiss(id: viewModelUI.id) }
            }
            else {
                action = nil
            }
        }
#endif
    }
}

extension View {
    /// On iOS, this is the same as `fullScreenCover`. On macOS, this shows
    /// `viewModelUI` in a separate window.
    /// If the presentation is modal (the default), the presenting view has
    /// a semi-transparent cover. Tapping that cover closes the window.
    /// `windowFrameKey` provides a stable geometry key independently of the view model's lifetime.
    /// The window scene can use `WindowContentView.frameKey` to persist its frame.
    public func fullScreenOrWindow<C: ViewModelUIContainer, V: View>(
        isPresented: Binding<Bool>,
        viewModelUI: C?,
        isModal: Bool = true,
        windowFrameKey: String? = nil,
        content: @escaping () -> V?
    )
    -> some View {
        self.modifier(FullScreenOrWindow(
            isPresented: isPresented,
            viewModelUI: viewModelUI,
            isModal: isModal,
            windowFrameKey: windowFrameKey,
            content: content
        ))
    }
}

/// The view-model content view for a window.
///
/// - Note: When `viewModelUI` is cancelled, the window is closed using the
/// standard `dismiss` action from the SwiftUI environment.
public struct WindowContentView<C: ViewModelUIContainer>: View {
    let viewModelUI: C?
    /// An optional geometry persistence key supplied by the presenter, independent of the view model ID.
    public let frameKey: String?

    struct ContentView: View {
        let viewModelUI: C
        // Triggers a view update on cancellation; the view model is not observed here.
        @State private var isCancelled = false
        @Environment(\.dismiss) private var dismiss
        
        public init(viewModelUI: C) {
            self.viewModelUI = viewModelUI
        }
        
        @ViewBuilder
        private var content: some View {
            // Closing can trigger a final update after the view model has been cancelled.
            if !isCancelled && !viewModelUI.viewModel.isCancelled {
                viewModelUI.makeView()
            }
        }

        var body: some View {
            content
                .onAppear {
                    ViewModelUIRegistry.setDismissAction(id: viewModelUI.id) { dismiss() }
                }
                .onDisappear {
                    ViewModelUIRegistry.removeDismissAction(id: viewModelUI.id)
                    viewModelUI.cancel()
                }
                .task {
                    var iterator = viewModelUI.viewModel.cancellation.makeAsyncIterator()
                    guard await iterator.next() != nil, !Task.isCancelled else { return }
                    isCancelled = true
                    // The owner has already ended the flow; there is no live editor to return to.
#if os(macOS)
                    if #available(macOS 15.0, *) {
                        withTransaction(\.dismissBehavior, .destructive) { dismiss() }
                    }
                    else {
                        dismiss()
                    }
#else
                    dismiss()
#endif
                }
        }
    }
    
    public init(id: UUID?) {
        self.viewModelUI = id.flatMap { ViewModelUIRegistry.get(id: $0) }
        self.frameKey = id.flatMap { ViewModelUIRegistry.frameKey(id: $0) }
    }
    
    public var body: some View {
        if let viewModelUI {
            ContentView(viewModelUI: viewModelUI)
        }
    }
}

extension ViewModelUINamespace {
    // A window group for the UI namespace.
    @MainActor
    public static func windowGroup()
    -> WindowGroup<PresentedWindowContent<UUID, WindowContentView<ViewModelUI<Self>>>>
    {
        WindowGroup(id: ViewModel.viewModelDefaultKey, for: UUID.self) { id in
            WindowContentView<ViewModelUI<Self>>(id: id.wrappedValue)
        }
    }
}
