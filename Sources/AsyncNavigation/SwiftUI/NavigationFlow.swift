//
//  NavigationFlow.swift
//  ReducerArchitecture
//
//  Created by Ilya Belenkiy on 11/4/25.
//

import SwiftUI

public struct NavigationFlow<Nsp: ViewModelUINamespace>: View {
    public enum AnimationPolicy {
        /// Preserve automatic animations for clients that do not supply transactions.
        case automatic
        /// Programmatic changes inherit the caller's transaction; native Back still uses SwiftUI's transaction.
        case caller
    }
    public typealias RootViewModel = Nsp.ViewModel
    @State private var root: RootViewModel
    let run: (RootViewModel.PublishedValue, _ proxy: NavigationProxy) async -> Void
    let animationPolicy: AnimationPolicy

    @StateObject private var pathContainer = NavigationPathContainer()

    public init(
        _ rootNode: RootNavigationNode<Nsp>,
        animationPolicy: AnimationPolicy = .automatic,
        run: @escaping (RootViewModel.PublishedValue, _: NavigationProxy) async -> Void
    ) {
        self.root = rootNode.root
        self.run = run
        self.animationPolicy = animationPolicy
    }

    func addNavigation(_ viewModelUI: some ViewModelUIContainer) -> AnyView {
        AnyView(EmptyView() .addNavigation(type(of: viewModelUI).Nsp.self))
    }

    public var body: some View {
        // Animate path writes made by SwiftUI's native Back button.
        NavigationStack(path: animationPolicy == .automatic ? $pathContainer.path.animation(.default) : $pathContainer.path) {
            Nsp.ContentView(root)
                .background(
                    ForEach(pathContainer.stack, id: \.id) { viewModelUI in
                        addNavigation(viewModelUI)
                    }
                )
        }
        // Animate path changes made directly by NavigationProxy.
        .modifier(NavigationAnimation(policy: animationPolicy, path: pathContainer.path))
        .onAppear {
            pathContainer.root = ViewModelUI<Nsp>(root)
        }
        .environment(\.backAction, { pathContainer.pop() })
        .preference(key: NavigationPathStackKey.self, value: .init(value: pathContainer.stack))
        .task {
            await root.get { value in
                await run(value, pathContainer)
            }
        }
    }

    private struct NavigationAnimation: ViewModifier {
        let policy: AnimationPolicy
        let path: NavigationPath

        @ViewBuilder
        func body(content: Content) -> some View {
            switch policy {
            case .automatic: content.animation(.default, value: path)
            case .caller: content
            }
        }
    }
}

public struct AddNavigation<Nsp: ViewModelUINamespace>: ViewModifier {
    let type: Nsp.Type

    public func body(content: Content) -> some View {
        content.navigationDestination(for: ViewModelUI<Nsp>.self) { viewModelUI in
            viewModelUI.makeView()
        }
    }
}

public extension View {
    func addNavigation<Nsp: ViewModelUINamespace>(_ type: Nsp.Type) -> some View {
        self.modifier(AddNavigation(type: type))
    }
}
